<?php

use App\Models\Project;
use Illuminate\Support\Facades\Broadcast;

Broadcast::channel('project-chat.group.{projectId}', function ($user, int $projectId) {
    return Project::query()
        ->whereKey($projectId)
        ->whereNull('archived_at')
        ->where(function ($query) use ($user) {
            $query->where('user_id', $user->id)
                ->orWhereHas(
                    'members',
                    fn ($members) => $members->where('user_id', $user->id),
                );
        })
        ->exists();
});

Broadcast::channel(
    'project-chat.direct.{projectId}.{memberUserId}',
    function ($user, int $projectId, int $memberUserId) {
        return Project::query()
            ->whereKey($projectId)
            ->whereNull('archived_at')
            ->whereHas(
                'members',
                fn ($members) => $members->where('user_id', $memberUserId),
            )
            ->where(function ($query) use ($user, $memberUserId) {
                $query->where('user_id', $user->id)
                    ->orWhereHas(
                        'members',
                        fn ($members) => $members->where('user_id', $user->id),
                    );
            })
            ->exists();
    });
