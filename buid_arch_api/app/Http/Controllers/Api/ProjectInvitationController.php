<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Project;
use App\Models\ProjectInvitation;
use App\Models\ProjectMember;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Crypt;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;

class ProjectInvitationController extends Controller
{
    public function index(Request $request, Project $project): JsonResponse
    {
        abort_unless($project->user_id === $request->user()->id, 403);

        $invitations = $project->invitations()
            ->with(['invitedBy:id,name', 'acceptedBy:id,name'])
            ->latest('id')
            ->get()
            ->map(function (ProjectInvitation $invitation) {
                $invitation->refreshExpirationStatus();

                return $this->ownerInvitationResponse($invitation);
            });

        return response()->json(['invitations' => $invitations]);
    }

    public function store(Request $request, Project $project): JsonResponse
    {
        abort_unless($project->user_id === $request->user()->id, 403);

        $validated = $request->validate([
            'role' => ['required', Rule::in(['contractor', 'designer'])],
        ]);

        $token = bin2hex(random_bytes(32));
        $invitation = $project->invitations()->create([
            'invited_by_user_id' => $request->user()->id,
            'role' => $validated['role'],
            'token_hash' => hash('sha256', $token),
            'token_encrypted' => Crypt::encryptString($token),
            'status' => 'pending',
            'expires_at' => now()->addDays(7),
        ]);
        $invitation->load('invitedBy:id,name');

        return response()->json([
            'invitation' => $this->ownerInvitationResponse($invitation),
        ], 201);
    }

    public function revoke(
        Request $request,
        Project $project,
        ProjectInvitation $invitation,
    ): JsonResponse {
        abort_unless($project->user_id === $request->user()->id, 403);
        abort_unless($invitation->project_id === $project->id, 404);

        $status = DB::transaction(function () use ($invitation, $project): string {
            $locked = ProjectInvitation::query()
                ->whereKey($invitation->id)
                ->where('project_id', $project->id)
                ->lockForUpdate()
                ->firstOrFail();
            $locked->refreshExpirationStatus();
            if ($locked->status !== 'pending') {
                return $locked->status;
            }

            $locked->update([
                'status' => 'revoked',
                'revoked_at' => now(),
            ]);

            return $locked->status;
        });

        if ($status !== 'revoked') {
            return response()->json([
                'message' => 'Only a pending invitation can be revoked.',
                'invitation_status' => $status,
            ], 409);
        }

        return response()->json([
            'message' => 'Invitation revoked.',
            'status' => $status,
        ]);
    }

    public function show(Request $request, string $token): JsonResponse
    {
        $invitation = $this->findByToken($token);
        $invitation->load(['project.user:id,name', 'invitedBy:id,name']);
        $invitation->refreshExpirationStatus();

        $user = $request->user();
        $canAccept = $invitation->status === 'pending'
            && $user->id !== $invitation->invited_by_user_id
            && $user->role === $invitation->role
            && ! $invitation->project->members()->where('user_id', $user->id)->exists();

        return response()->json([
            'invitation' => [
                'id' => $invitation->id,
                'role' => $invitation->role,
                'status' => $invitation->status,
                'created_at' => $invitation->created_at->toIso8601String(),
                'expires_at' => $invitation->expires_at->toIso8601String(),
                'inviter_name' => $invitation->invitedBy->name,
                'can_accept' => $canAccept,
                'project' => [
                    'id' => $invitation->project->id,
                    'name' => $invitation->project->name,
                    'location' => $invitation->project->location,
                    'type' => $invitation->project->type,
                    'progress' => $invitation->project->progress,
                    'latitude' => $invitation->project->latitude,
                    'longitude' => $invitation->project->longitude,
                    'is_owner' => false,
                    'photo_url' => $invitation->project->image_path
                        ? $request->getSchemeAndHttpHost()
                            .'/storage/'.$invitation->project->image_path
                        : null,
                    'owner_name' => $invitation->project->user->name,
                ],
            ],
        ]);
    }

    public function accept(Request $request, string $token): JsonResponse
    {
        $result = DB::transaction(function () use ($request, $token): array {
            $invitation = $this->findByToken($token, lockForUpdate: true);
            $project = Project::query()
                ->whereKey($invitation->project_id)
                ->lockForUpdate()
                ->firstOrFail();
            $invitation->refreshExpirationStatus();

            if ($invitation->status !== 'pending') {
                return [
                    'error' => 'This invitation is '.$invitation->status.'.',
                    'code' => $invitation->status === 'expired' ? 410 : 409,
                ];
            }

            $user = $request->user();
            if ($user->id === $invitation->invited_by_user_id
                || $user->role !== $invitation->role) {
                return [
                    'error' => 'Sign in with an account matching the invited role.',
                    'code' => 403,
                ];
            }

            if ($project->members()->where('user_id', $user->id)->exists()) {
                return [
                    'error' => 'You are already a member of this project.',
                    'code' => 409,
                ];
            }

            ProjectMember::create([
                'project_id' => $project->id,
                'user_id' => $user->id,
                'role' => $invitation->role,
            ]);
            $invitation->update([
                'status' => 'accepted',
                'accepted_by_user_id' => $user->id,
                'accepted_at' => now(),
            ]);

            return [
                'project_id' => $project->id,
                'role' => $invitation->role,
            ];
        });

        if (isset($result['error'])) {
            return response()->json([
                'message' => $result['error'],
            ], $result['code']);
        }

        return response()->json([
            'accepted' => true,
            'project_id' => $result['project_id'],
            'role' => $result['role'],
        ]);
    }

    public function decline(Request $request, string $token): JsonResponse
    {
        $result = DB::transaction(function () use ($request, $token): array {
            $invitation = $this->findByToken($token, lockForUpdate: true);
            $invitation->refreshExpirationStatus();

            if ($invitation->status !== 'pending') {
                return [
                    'error' => 'This invitation is '.$invitation->status.'.',
                    'code' => $invitation->status === 'expired' ? 410 : 409,
                ];
            }

            $user = $request->user();
            if ($user->id === $invitation->invited_by_user_id
                || $user->role !== $invitation->role) {
                return [
                    'error' => 'Sign in with an account matching the invited role.',
                    'code' => 403,
                ];
            }

            $invitation->update([
                'status' => 'declined',
                'declined_by_user_id' => $user->id,
                'declined_at' => now(),
            ]);

            return ['declined' => true];
        });

        if (isset($result['error'])) {
            return response()->json([
                'message' => $result['error'],
            ], $result['code']);
        }

        return response()->json([
            'declined' => true,
            'message' => 'Invitation declined.',
        ]);
    }

    private function findByToken(string $token, bool $lockForUpdate = false): ProjectInvitation
    {
        abort_unless(preg_match('/^[a-f0-9]{64}$/', $token) === 1, 404);

        $query = ProjectInvitation::query()
            ->where('token_hash', hash('sha256', $token));
        if ($lockForUpdate) {
            $query->lockForUpdate();
        }

        return $query->firstOrFail();
    }

    private function ownerInvitationResponse(ProjectInvitation $invitation): array
    {
        return [
            'id' => $invitation->id,
            'role' => $invitation->role,
            'status' => $invitation->status,
            'token' => Crypt::decryptString($invitation->token_encrypted),
            'created_at' => $invitation->created_at->toIso8601String(),
            'expires_at' => $invitation->expires_at->toIso8601String(),
            'accepted_at' => $invitation->accepted_at?->toIso8601String(),
            'declined_at' => $invitation->declined_at?->toIso8601String(),
            'revoked_at' => $invitation->revoked_at?->toIso8601String(),
            'inviter_name' => $invitation->invitedBy?->name,
            'accepted_by_name' => $invitation->acceptedBy?->name,
        ];
    }
}
