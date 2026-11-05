<?php

namespace App\Http\Controllers\Api;

use App\Events\ProjectChatMessageChanged;
use App\Http\Controllers\Controller;
use App\Models\Project;
use App\Models\ProjectConversation;
use App\Models\ProjectGroupConversation;
use App\Models\ProjectGroupMessage;
use App\Models\ProjectMessage;
use App\Models\User;
use App\Notifications\ProjectActivityNotification;
use App\Services\FirebasePushService;
use App\Services\ProjectChatMessageSerializer;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use Throwable;

class ProjectChatController extends Controller
{
    public function __construct(
        private readonly FirebasePushService $firebasePushService,
    ) {}

    public function index(Request $request): JsonResponse
    {
        $user = $request->user();
        $projects = Project::query()
            ->whereNull('archived_at')
            ->where(function ($query) use ($user) {
                $query->where('user_id', $user->id)
                    ->orWhereHas(
                        'members',
                        fn ($members) => $members->where('user_id', $user->id),
                    );
            })
            ->with([
                'user:id,name',
                'members.user:id,name,role',
                'directConversations.member:id,name,role',
                'directConversations.latestMessage.sender:id,name',
                'groupConversation.latestMessage.sender:id,name',
            ])
            ->latest('id')
            ->get();

        $chats = [];
        foreach ($projects as $project) {
            $groupConversation = $project->groupConversation;
            $groupLatest = $groupConversation?->latestMessage;
            $chats[] = $this->chatResponse(
                project: $project,
                type: 'group',
                conversationId: $groupConversation?->id,
                participantUserId: null,
                displayName: "{$project->name} Team",
                latestMessage: $groupLatest,
                userId: $user->id,
            );

            if ($project->user_id === $user->id) {
                foreach ($project->directConversations as $conversation) {
                    $membership = $project->members->firstWhere(
                        'user_id',
                        $conversation->member_user_id,
                    );
                    if ($membership === null) {
                        continue;
                    }
                    $chats[] = $this->chatResponse(
                        project: $project,
                        type: 'direct',
                        conversationId: $conversation->id,
                        participantUserId: $conversation->member_user_id,
                        displayName: $membership->display_name
                            ?: $conversation->member?->name
                                ?: 'Project member',
                        latestMessage: $conversation->latestMessage,
                        userId: $user->id,
                    );
                }

                continue;
            }

            $conversation = $project->directConversations->firstWhere(
                'member_user_id',
                $user->id,
            );
            if ($conversation !== null) {
                $chats[] = $this->chatResponse(
                    project: $project,
                    type: 'direct',
                    conversationId: $conversation->id,
                    participantUserId: $user->id,
                    displayName: $project->user?->name ?? 'Home Owner',
                    latestMessage: $conversation->latestMessage,
                    userId: $user->id,
                );
            }
        }

        usort($chats, fn (array $a, array $b) => strcmp($b['sort_at'] ?? '', $a['sort_at'] ?? '')
        );

        foreach ($chats as &$chat) {
            unset($chat['sort_at']);
        }

        return response()->json(['chats' => $chats]);
    }

    public function forward(Request $request, Project $project): JsonResponse
    {
        $validated = $request->validate([
            'source_type' => ['required', 'in:direct,group'],
            'source_message_id' => ['required', 'integer', 'min:1'],
            'source_member_user_id' => [
                'required_if:source_type,direct',
                'nullable',
                'integer',
                'min:1',
            ],
            'target_type' => ['required', 'in:direct,group'],
            'target_member_user_id' => [
                'required_if:target_type,direct',
                'nullable',
                'integer',
                'min:1',
            ],
        ]);

        $sourceType = $validated['source_type'];
        $sourceMemberUserId = isset($validated['source_member_user_id'])
            ? (int) $validated['source_member_user_id']
            : null;
        $sourceConversation = $this->sourceConversation(
            $request,
            $project,
            $sourceType,
            $sourceMemberUserId,
        );
        $sourceMessage = $sourceConversation->messages()
            ->with(['sender:id,name,role'])
            ->findOrFail($validated['source_message_id']);
        abort_unless($sourceMessage->deleted_at === null, 422, 'Deleted messages cannot be forwarded.');

        $targetType = $validated['target_type'];
        $targetMemberUserId = isset($validated['target_member_user_id'])
            ? (int) $validated['target_member_user_id']
            : null;
        $targetConversation = $this->targetConversation(
            $request,
            $project,
            $targetType,
            $targetMemberUserId,
        );
        abort_unless(
            $sourceType !== $targetType
                || $sourceConversation->id !== $targetConversation->id,
            422,
            'Choose a different conversation to forward this message.',
        );

        $attachmentPath = $this->copyAttachment(
            $sourceMessage,
            $targetType,
            $targetConversation->id,
        );
        $members = ProjectChatMessageSerializer::projectMembers($project);
        $sourceIdentity = ProjectChatMessageSerializer::serialize(
            $sourceMessage,
            $project,
            $members,
        );
        $forwardedFromName = $sourceMessage->forwarded_from_name
            ?: $sourceIdentity['sender_name'];
        $attributes = [
            'sender_user_id' => $request->user()->id,
            'body' => $sourceMessage->body,
            'message_type' => $sourceMessage->message_type,
            'attachment_path' => $attachmentPath,
            'attachment_name' => $sourceMessage->attachment_name,
            'attachment_mime_type' => $sourceMessage->attachment_mime_type,
            'attachment_size' => $sourceMessage->attachment_size,
            'forwarded_from_name' => $forwardedFromName,
            'location_latitude' => $sourceMessage->location_latitude,
            'location_longitude' => $sourceMessage->location_longitude,
            'location_address' => $sourceMessage->location_address,
        ];

        try {
            $message = $targetConversation->messages()
                ->create($attributes)
                ->load(['sender:id,name,role']);
        } catch (Throwable $error) {
            if ($attachmentPath !== null) {
                Storage::disk('local')->delete($attachmentPath);
            }
            throw $error;
        }

        $readReceipts = null;
        broadcast(new ProjectChatMessageChanged(
            projectId: $project->id,
            conversationType: $targetType,
            conversationId: $targetConversation->id,
            memberUserId: $targetType === 'direct' ? $targetMemberUserId : null,
            message: ProjectChatMessageSerializer::serialize(
                $message,
                $project,
                $members,
                $readReceipts,
            ),
        ));
        $this->notifyForwardRecipients(
            $request,
            $project,
            $targetType,
            $targetMemberUserId,
            $message,
        );

        return response()->json([
            'message' => ProjectChatMessageSerializer::serialize(
                $message,
                $project,
                $members,
            ),
        ], 201);
    }

    private function sourceConversation(
        Request $request,
        Project $project,
        string $type,
        ?int $memberUserId,
    ): ProjectConversation|ProjectGroupConversation {
        $userId = $request->user()->id;
        if ($type === 'group') {
            $this->ensureProjectParticipant($project, $userId);

            return $project->groupConversation()
                ->firstOrFail();
        }

        abort_if($memberUserId === null, 422);
        $this->ensureDirectParticipant($project, $userId, $memberUserId);

        return $project->directConversations()
            ->where('member_user_id', $memberUserId)
            ->firstOrFail();
    }

    private function targetConversation(
        Request $request,
        Project $project,
        string $type,
        ?int $memberUserId,
    ): ProjectConversation|ProjectGroupConversation {
        $userId = $request->user()->id;
        if ($type === 'group') {
            $this->ensureProjectParticipant($project, $userId);

            return $project->groupConversation()->firstOrCreate([]);
        }

        abort_if($memberUserId === null, 422);
        $this->ensureDirectParticipant($project, $userId, $memberUserId);

        return $project->directConversations()->firstOrCreate([
            'member_user_id' => $memberUserId,
        ]);
    }

    private function ensureProjectParticipant(Project $project, int $userId): void
    {
        abort_unless(
            $project->user_id === $userId
                || $project->members()->where('user_id', $userId)->exists(),
            403,
        );
    }

    private function ensureDirectParticipant(
        Project $project,
        int $userId,
        int $memberUserId,
    ): void {
        abort_unless(
            $memberUserId !== $project->user_id
                && $project->members()->where('user_id', $memberUserId)->exists(),
            404,
        );
        abort_unless(
            $userId === $project->user_id || $userId === $memberUserId,
            403,
        );
    }

    private function copyAttachment(
        ProjectMessage|ProjectGroupMessage $source,
        string $targetType,
        int $targetConversationId,
    ): ?string {
        if ($source->attachment_path === null) {
            return null;
        }

        $disk = Storage::disk('local');
        abort_unless($disk->exists($source->attachment_path), 404);
        $directory = $targetType === 'group'
            ? "project-group-chat/{$targetConversationId}"
            : "project-chat/{$targetConversationId}";
        $extension = pathinfo($source->attachment_path, PATHINFO_EXTENSION);
        $path = "{$directory}/forwarded-".Str::uuid()
            .($extension === '' ? '' : ".{$extension}");
        abort_unless($disk->copy($source->attachment_path, $path), 500, 'The forwarded attachment could not be saved.');

        return $path;
    }

    private function notifyForwardRecipients(
        Request $request,
        Project $project,
        string $type,
        ?int $memberUserId,
        ProjectMessage|ProjectGroupMessage $message,
    ): void {
        $actor = $request->user();
        $recipients = $type === 'group'
            ? User::query()->whereIn(
                'id',
                $project->members()
                    ->where('user_id', '!=', $actor->id)
                    ->pluck('user_id')
                    ->push($project->user_id)
                    ->unique(),
            )->get()
            : User::query()->whereKey(
                $actor->id === $project->user_id
                    ? $memberUserId
                    : $project->user_id,
            )->get();
        $preview = match ($message->message_type) {
            'image' => 'Forwarded an image.',
            'file' => 'Forwarded a file.',
            'voice' => 'Forwarded a voice message.',
            'location' => 'Forwarded a location.',
            default => 'Forwarded: '.mb_strimwidth($message->body ?? '', 0, 100, '…'),
        };

        foreach ($recipients->reject(fn (User $recipient) => $recipient->id === $actor->id) as $recipient) {
            $notification = new ProjectActivityNotification(
                event: 'chat_message',
                title: "New message from {$actor->name}",
                message: $preview,
                projectId: $project->id,
                projectName: $project->name,
                actorId: $actor->id,
                actorName: $actor->name,
                relatedId: $message->id,
            );
            $pushData = ['conversation_type' => $type];
            if ($type === 'direct') {
                $pushData['member_user_id'] = (string) $memberUserId;
            }
            $recipient->notify($notification);
            $this->firebasePushService->queue(
                $recipient,
                $notification->toPushPayload($pushData),
            );
        }
    }

    private function chatResponse(
        Project $project,
        string $type,
        ?int $conversationId,
        ?int $participantUserId,
        string $displayName,
        ProjectMessage|ProjectGroupMessage|null $latestMessage,
        int $userId,
    ): array {
        $lastReadMessageId = $conversationId === null
            ? 0
            : (int) DB::table('project_chat_reads')
                ->where('project_id', $project->id)
                ->where('user_id', $userId)
                ->where('conversation_type', $type)
                ->where('conversation_id', $conversationId)
                ->value('last_read_message_id');

        $unreadCount = 0;
        if ($conversationId !== null) {
            $messageModel = $type === 'group'
                ? new ProjectGroupMessage
                : new ProjectMessage;
            $unreadCount = $messageModel->newQuery()
                ->where('conversation_id', $conversationId)
                ->where('id', '>', $lastReadMessageId)
                ->where('sender_user_id', '!=', $userId)
                ->whereNull('deleted_at')
                ->count();
        }

        return [
            'id' => "{$type}:{$project->id}:"
                .($participantUserId ?? 'group'),
            'type' => $type,
            'conversation_id' => $conversationId,
            'project_id' => $project->id,
            'project_name' => $project->name,
            'project_location' => $project->location,
            'project_type' => $project->type,
            'project_latitude' => $project->latitude,
            'project_longitude' => $project->longitude,
            'is_owner' => $project->user_id === $userId,
            'project_image_url' => $project->image_path
                ? request()->getSchemeAndHttpHost().'/storage/'.$project->image_path
                : null,
            'name' => $displayName,
            'participant_user_id' => $participantUserId,
            'counterpart_user_id' => $type === 'group'
                ? null
                : ($project->user_id === $userId
                    ? $participantUserId
                    : $project->user_id),
            'counterpart_role' => $type === 'group'
                ? null
                : ($project->user_id === $userId
                    ? $project->members->firstWhere('user_id', $participantUserId)?->role
                    : 'homeOwner'),
            'counterpart_designation' => $type === 'group'
                ? null
                : ($project->user_id === $userId
                    ? $project->members->firstWhere('user_id', $participantUserId)?->designation
                    : null),
            'last_message' => $latestMessage === null
                ? null
                : $this->messagePreview($latestMessage),
            'last_message_at' => $latestMessage?->created_at?->toIso8601String(),
            'unread_count' => $unreadCount,
            'sort_at' => $latestMessage?->created_at?->toIso8601String()
                ?? $project->updated_at?->toIso8601String(),
        ];
    }

    private function messagePreview(
        ProjectMessage|ProjectGroupMessage $message,
    ): array {
        return [
            'id' => $message->id,
            'body' => $message->deleted_at !== null
                ? 'This message was deleted'
                : $message->body,
            'message_type' => $message->deleted_at !== null
                ? 'deleted'
                : $message->message_type,
            'sender_name' => $message->sender?->name,
        ];
    }
}
