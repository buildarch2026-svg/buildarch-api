<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Project;
use App\Models\ProjectInvitation;
use App\Models\ProjectMember;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class ProjectMemberController extends Controller
{
    public function index(Request $request, Project $project): JsonResponse
    {
        $user = $request->user();
        $isOwner = $project->user_id === $user->id;
        $isMember = $project->members()->where('user_id', $user->id)->exists();
        abort_unless($isOwner || $isMember, 403);

        $members = $project->members()
            ->with('user:id,name,role')
            ->oldest('id')
            ->get()
            ->map(fn ($member) => [
                'user_id' => $member->user_id,
                'name' => $member->display_name ?: $member->user->name,
                'designation' => $member->designation ?: match ($member->user->role) {
                    'homeOwner' => 'Home Owner',
                    'contractor' => 'Contractor',
                    'designer' => 'Designer',
                    default => null,
                },
                'role' => $member->role,
                'joined_at' => $member->created_at->toIso8601String(),
            ]);

        return response()->json([
            'owner' => [
                'user_id' => $project->user_id,
                'name' => $project->user()->value('name'),
                'role' => 'homeOwner',
            ],
            'members' => $members,
        ]);
    }

    public function destroy(
        Request $request,
        Project $project,
        int $memberUserId,
    ): JsonResponse {
        abort_unless($project->user_id === $request->user()->id, 403);
        abort_if($memberUserId === $project->user_id, 422, 'The project owner cannot be removed.');

        DB::transaction(function () use ($project, $memberUserId): void {
            $membership = ProjectMember::query()
                ->where('project_id', $project->id)
                ->where('user_id', $memberUserId)
                ->lockForUpdate()
                ->firstOrFail();
            $membership->delete();

            ProjectInvitation::query()
                ->where('project_id', $project->id)
                ->where('accepted_by_user_id', $memberUserId)
                ->where('status', 'accepted')
                ->update([
                    'status' => 'removed',
                    'removed_at' => now(),
                    'updated_at' => now(),
                ]);
        });

        return response()->json([
            'message' => 'Project member removed.',
        ]);
    }
}
