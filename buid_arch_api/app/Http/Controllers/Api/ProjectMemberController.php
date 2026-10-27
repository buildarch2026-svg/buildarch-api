<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Project;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class ProjectMemberController extends Controller
{
    public function index(Request $request, Project $project): JsonResponse
    {
        $user = $request->user();
        $isOwner = $project->user_id === $user->id;
        $isMember = $project->members()->where('user_id', $user->id)->exists();
        abort_unless($isOwner || $isMember, 403);

        $members = $project->members()
            ->with('user:id,name')
            ->oldest('id')
            ->get()
            ->map(fn ($member) => [
                'user_id' => $member->user_id,
                'name' => $member->user->name,
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
}
