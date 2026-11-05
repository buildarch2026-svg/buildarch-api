<?php

namespace App\Services;

use App\Models\Project;
use App\Models\ProjectGroupMessage;
use App\Models\ProjectMember;
use App\Models\ProjectMessage;
use Illuminate\Database\Eloquent\Collection;
use Illuminate\Support\Facades\DB;

class ProjectChatMessageSerializer
{
    public static function projectMembers(Project $project): Collection
    {
        $project->loadMissing('user:id,name');

        return $project->members()
            ->with('user:id,name,role')
            ->get()
            ->keyBy('user_id');
    }

    public static function serialize(
        ProjectMessage|ProjectGroupMessage $message,
        Project $project,
        ?Collection $members = null,
        ?array $readReceipts = null,
    ): array {
        $identity = self::senderIdentity($message, $project, $members);
        $deleted = $message->deleted_at !== null;
        $readReceipts ??= self::readReceipts(
            $project,
            $message instanceof ProjectMessage ? 'direct' : 'group',
            $message->conversation_id,
        );
        $readByUserIds = [];
        foreach ($readReceipts as $userId => $lastReadMessageId) {
            if ((int) $userId !== $message->sender_user_id
                && $message->id <= $lastReadMessageId) {
                $readByUserIds[] = (int) $userId;
            }
        }

        return [
            'id' => $message->id,
            'body' => $deleted ? null : $message->body,
            'message_type' => $deleted ? 'deleted' : $message->message_type,
            'attachment_name' => $deleted ? null : $message->attachment_name,
            'attachment_mime_type' => $deleted ? null : $message->attachment_mime_type,
            'attachment_size' => $deleted ? null : $message->attachment_size,
            'sender_user_id' => $message->sender_user_id,
            'sender_name' => $identity['name'],
            'sender_designation' => $identity['designation'],
            'forwarded_from_name' => $deleted ? null : $message->forwarded_from_name,
            'reply_to_message_id' => $message->reply_to_message_id,
            'reply_to' => self::replyResponse($message, $project, $members),
            'edited_at' => $message->edited_at?->toIso8601String(),
            'deleted_at' => $message->deleted_at?->toIso8601String(),
            'location_latitude' => $deleted ? null : $message->location_latitude,
            'location_longitude' => $deleted ? null : $message->location_longitude,
            'location_address' => $deleted ? null : $message->location_address,
            'read_by_user_ids' => $readByUserIds,
            'created_at' => $message->created_at?->toIso8601String(),
        ];
    }

    public static function readReceipts(
        Project $project,
        string $conversationType,
        int $conversationId,
    ): array {
        $participantIds = $project->members()
            ->pluck('user_id')
            ->push($project->user_id)
            ->unique()
            ->all();

        return DB::table('project_chat_reads')
            ->where('project_id', $project->id)
            ->where('conversation_type', $conversationType)
            ->where('conversation_id', $conversationId)
            ->whereIn('user_id', $participantIds)
            ->pluck('last_read_message_id', 'user_id')
            ->map(fn ($messageId) => (int) $messageId)
            ->all();
    }

    private static function replyResponse(
        ProjectMessage|ProjectGroupMessage $message,
        Project $project,
        ?Collection $members,
    ): ?array {
        $reply = $message->replyTo;
        if ($reply === null) {
            return null;
        }

        $identity = self::senderIdentity($reply, $project, $members);
        $deleted = $reply->deleted_at !== null;

        return [
            'id' => $reply->id,
            'body' => $deleted ? null : $reply->body,
            'message_type' => $deleted ? 'deleted' : $reply->message_type,
            'attachment_name' => $deleted ? null : $reply->attachment_name,
            'sender_name' => $identity['name'],
            'deleted_at' => $reply->deleted_at?->toIso8601String(),
        ];
    }

    private static function senderIdentity(
        ProjectMessage|ProjectGroupMessage $message,
        Project $project,
        ?Collection $members,
    ): array {
        $sender = $message->sender;
        $membership = $members?->get($message->sender_user_id);
        if ($membership === null && $message->sender_user_id !== $project->user_id) {
            $membership = ProjectMember::query()
                ->where('project_id', $project->id)
                ->where('user_id', $message->sender_user_id)
                ->first();
        }

        if ($message->sender_user_id === $project->user_id) {
            $project->loadMissing('user:id,name');

            return [
                'name' => $project->user?->name ?? $sender?->name ?? 'Home Owner',
                'designation' => 'Home Owner',
            ];
        }

        $role = $membership?->role ?? $sender?->role;
        $defaultDesignation = match ($role) {
            'contractor' => 'Contractor',
            'designer' => 'Designer',
            default => null,
        };

        return [
            'name' => $membership?->display_name ?: $sender?->name ?: 'Project member',
            'designation' => $membership?->designation ?: $defaultDesignation,
        ];
    }
}
