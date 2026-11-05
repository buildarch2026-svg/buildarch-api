<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Project;
use App\Models\ProjectTransaction;
use Illuminate\Database\QueryException;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class ProjectTransactionController extends Controller
{
    public function index(Request $request, Project $project): JsonResponse
    {
        $this->authorizeProjectAccess($request, $project);

        $transactions = $project->transactions()
            ->with('payer:id,name')
            ->latest('created_at')
            ->get()
            ->map(fn (ProjectTransaction $transaction) => $this->transactionResponse($transaction));

        return response()->json([
            'transactions' => $transactions,
        ]);
    }

    public function store(Request $request, Project $project): JsonResponse
    {
        $this->authorizeProjectAccess($request, $project);

        $validated = $request->validate([
            'payee_name' => ['required', 'string', 'max:255'],
            'payee_type' => ['nullable', 'string', 'max:50', Rule::in(['shop', 'supplier', 'contractor', 'other'])],
            'payee_vpa' => ['nullable', 'string', 'max:255'],
            'amount' => ['required', 'numeric', 'gt:0'],
            'currency' => ['required', 'string', 'size:3'],
            'status' => ['required', Rule::in(['pending', 'completed', 'failed', 'cancelled', 'refunded'])],
            'payment_method' => ['nullable', 'string', 'max:80'],
            'payment_type' => ['nullable', 'string', 'max:30', Rule::in(['manual', 'external', 'provider'])],
            'description' => ['nullable', 'string', 'max:500'],
            'category' => ['nullable', 'string', 'max:80'],
            'provider_reference' => ['nullable', 'string', 'max:255'],
            'attempt_id' => ['nullable', 'string', 'max:255'],
            'qr_payload' => ['nullable', 'string', 'max:2000'],
        ]);

        $attributes = [
            'payer_user_id' => $request->user()->id,
            'payee_name' => $validated['payee_name'],
            'payee_type' => $validated['payee_type'] ?? 'shop',
            'payee_vpa' => $validated['payee_vpa'] ?? null,
            'amount' => $validated['amount'],
            'currency' => strtoupper($validated['currency']),
            'status' => $validated['status'],
            'payment_method' => $validated['payment_method'] ?? 'manual',
            'payment_type' => $validated['payment_type'] ?? 'manual',
            'description' => $validated['description'] ?? null,
            'category' => $validated['category'] ?? null,
            'provider_reference' => $validated['provider_reference'] ?? null,
            'attempt_id' => $validated['attempt_id'] ?? null,
            'qr_payload' => $validated['qr_payload'] ?? null,
        ];

        if ($attributes['attempt_id'] !== null) {
            $existing = ProjectTransaction::where('attempt_id', $attributes['attempt_id'])->first();
            if ($existing !== null) {
                return $this->respondToExistingAttempt($existing, $project, $attributes);
            }
        }

        try {
            $transaction = $project->transactions()->create($attributes)->load('payer:id,name');
        } catch (QueryException $exception) {
            if ($attributes['attempt_id'] === null) {
                throw $exception;
            }

            $existing = ProjectTransaction::where('attempt_id', $attributes['attempt_id'])->first();
            if ($existing === null) {
                throw $exception;
            }

            return $this->respondToExistingAttempt($existing, $project, $attributes);
        }

        return response()->json(['transaction' => $this->transactionResponse($transaction)], 201);
    }

    public function updateStatus(
        Request $request,
        Project $project,
        ProjectTransaction $transaction,
    ): JsonResponse {
        $this->authorizeProjectAccess($request, $project);
        abort_unless($transaction->project_id === $project->id, 404);

        $validated = $request->validate([
            'status' => ['required', Rule::in(['pending', 'completed', 'failed', 'cancelled', 'refunded'])],
            'provider_reference' => ['nullable', 'string', 'max:255'],
        ]);

        abort_unless($transaction->payer_user_id === $request->user()->id, 403);
        abort_unless($transaction->payment_type === 'provider', 422);

        $transaction->update([
            'status' => $validated['status'],
            'provider_reference' => $validated['provider_reference'] ?? $transaction->provider_reference,
        ]);

        return response()->json([
            'transaction' => $this->transactionResponse($transaction->load('payer:id,name')),
        ]);
    }

    private function authorizeProjectAccess(Request $request, Project $project): void
    {
        $user = $request->user();
        $isOwner = $project->user_id === $user->id;
        $isMember = $project->members()->where('user_id', $user->id)->exists();

        abort_unless($isOwner || $isMember, 403);
    }

    private function respondToExistingAttempt(
        ProjectTransaction $existing,
        Project $project,
        array $attributes,
    ): JsonResponse {
        $matches = (int) $existing->project_id === (int) $project->id
            && (int) $existing->payer_user_id === (int) $attributes['payer_user_id']
            && $existing->payee_name === $attributes['payee_name']
            && $existing->payee_type === $attributes['payee_type']
            && $existing->payee_vpa === $attributes['payee_vpa']
            && number_format((float) $existing->amount, 2, '.', '')
                === number_format((float) $attributes['amount'], 2, '.', '')
            && $existing->currency === $attributes['currency']
            && $existing->payment_method === $attributes['payment_method']
            && $existing->payment_type === $attributes['payment_type']
            && $existing->description === $attributes['description']
            && $existing->category === $attributes['category']
            && $existing->qr_payload === $attributes['qr_payload'];

        if (! $matches) {
            return response()->json([
                'message' => 'This attempt ID has already been used for a different transaction.',
            ], 409);
        }

        $existing->load('payer:id,name');

        return response()->json([
            'transaction' => $this->transactionResponse($existing),
        ]);
    }

    private function transactionResponse(ProjectTransaction $transaction): array
    {
        return [
            'id' => $transaction->id,
            'project_id' => $transaction->project_id,
            'payer_user_id' => $transaction->payer_user_id,
            'payer_name' => $transaction->payer?->name,
            'payee_name' => $transaction->payee_name,
            'payee_type' => $transaction->payee_type,
            'payee_vpa' => $transaction->payee_vpa,
            'amount' => (float) $transaction->amount,
            'currency' => $transaction->currency,
            'status' => $transaction->status,
            'payment_method' => $transaction->payment_method,
            'payment_type' => $transaction->payment_type,
            'description' => $transaction->description,
            'category' => $transaction->category,
            'provider_reference' => $transaction->provider_reference,
            'attempt_id' => $transaction->attempt_id,
            'created_at' => $transaction->created_at?->toIso8601String(),
        ];
    }
}
