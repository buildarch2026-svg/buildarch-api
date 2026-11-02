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

        $project->invitations()
            ->where('status', 'pending')
            ->where('expires_at', '<=', now())
            ->update([
                'status' => 'expired',
                'updated_at' => now(),
            ]);

        $invitations = $project->invitations()
            ->where('status', 'pending')
            ->where('expires_at', '>', now())
            ->with(['invitedBy:id,name', 'acceptedBy:id,name'])
            ->latest('id')
            ->get()
            ->map(fn (ProjectInvitation $invitation) => $this->ownerInvitationResponse($invitation));

        return response()->json(['invitations' => $invitations]);
    }

    public function store(Request $request, Project $project): JsonResponse
    {
        abort_unless($project->user_id === $request->user()->id, 403);

        $validated = $request->validate([
            'invitee_name' => ['required', 'string', 'max:255'],
            'invitee_designation' => ['required', 'string', 'max:255'],
            'role' => ['nullable', Rule::in(['general', 'contractor', 'designer'])],
        ]);

        $inviteeName = trim((string) $validated['invitee_name']);
        $inviteeDesignation = trim((string) $validated['invitee_designation']);

        if ($inviteeName === '' || $inviteeDesignation === '') {
            return response()->json([
                'message' => 'Invitee name and designation are required.',
            ], 422);
        }

        $token = bin2hex(random_bytes(32));
        $invitation = $project->invitations()->create([
            'invited_by_user_id' => $request->user()->id,
            'role' => $validated['role'] ?? 'general',
            'invitee_name' => $inviteeName,
            'invitee_designation' => $inviteeDesignation,
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
        $project = Project::withTrashed()->find($invitation->project_id);
        if (! $project || $project->trashed() || $project->archived_at !== null) {
            return response()->json([
                'message' => 'This project is not accepting invitations.',
            ], 410);
        }
        $invitation->setRelation('project', $project);
        $invitation->load(['project.user:id,name', 'invitedBy:id,name']);
        $invitation->refreshExpirationStatus();

        $user = $request->user();
        $canAccept = $invitation->status === 'pending'
            && $user !== null
            && $user->id !== $invitation->invited_by_user_id
            && ! $invitation->project->members()->where('user_id', $user->id)->exists();

        return response()->json([
            'invitation' => [
                'id' => $invitation->id,
                'role' => $invitation->role ?? 'general',
                'invitee_name' => $invitation->invitee_name,
                'invitee_designation' => $invitation->invitee_designation,
                'status' => $invitation->status,
                'created_at' => $invitation->created_at->toIso8601String(),
                'expires_at' => $invitation->expires_at->toIso8601String(),
                'inviter_name' => $invitation->invitedBy?->name,
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
                ->withTrashed()
                ->whereKey($invitation->project_id)
                ->lockForUpdate()
                ->firstOrFail();
            $invitation->refreshExpirationStatus();

            if ($project->trashed() || $project->archived_at !== null) {
                return [
                    'error' => 'This project is not accepting invitations.',
                    'code' => 410,
                ];
            }

            if ($invitation->status !== 'pending') {
                return [
                    'error' => 'This invitation is '.$invitation->status.'.',
                    'code' => $invitation->status === 'expired' ? 410 : 409,
                ];
            }

            $user = $request->user();
            if (! $user) {
                return [
                    'error' => 'Authentication required.',
                    'code' => 401,
                ];
            }

            if ($user->id === $invitation->invited_by_user_id) {
                return [
                    'error' => 'The project owner cannot accept their own invitation.',
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
                'role' => $user->role ?? 'homeOwner',
                'display_name' => $invitation->invitee_name,
                'designation' => $invitation->invitee_designation,
            ]);
            $invitation->update([
                'status' => 'accepted',
                'accepted_by_user_id' => $user->id,
                'accepted_at' => now(),
            ]);

            return [
                'project_id' => $project->id,
                'role' => $user->role ?? 'homeOwner',
                'invitee_name' => $invitation->invitee_name,
                'invitee_designation' => $invitation->invitee_designation,
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
            'invitee_name' => $result['invitee_name'],
            'invitee_designation' => $result['invitee_designation'],
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
            if (! $user) {
                return [
                    'error' => 'Authentication required.',
                    'code' => 401,
                ];
            }

            if ($user->id === $invitation->invited_by_user_id) {
                return [
                    'error' => 'The project owner cannot decline their own invitation.',
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
            'role' => $invitation->role ?? 'general',
            'invitee_name' => $invitation->invitee_name,
            'invitee_designation' => $invitation->invitee_designation,
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
