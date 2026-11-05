<?php

namespace App\Http\Controllers\Api;

use App\Events\ProjectChatMessageChanged;
use App\Http\Controllers\Controller;
use App\Models\Project;
use App\Models\ProjectConversation;
use App\Models\ProjectMessage;
use App\Models\User;
use App\Notifications\ProjectActivityNotification;
use App\Services\FirebasePushService;
use App\Services\ProjectChatMessageSerializer;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Symfony\Component\HttpFoundation\BinaryFileResponse;

class ProjectMessageController extends Controller
{
    public function __construct(
        private readonly FirebasePushService $firebasePushService,
    ) {}

    public function index(
        Request $request,
        Project $project,
        int $memberUserId,
    ): JsonResponse {
        $conversation = $this->conversationForParticipant(
            $request,
            $project,
            $memberUserId,
        );
        $afterId = max(0, (int) $request->query('after_id', 0));
        $beforeId = max(0, (int) $request->query('before_id', 0));

        $query = $conversation->messages()
            ->with(['sender:id,name,role', 'replyTo.sender:id,name,role']);
        if ($beforeId > 0) {
            $messages = $query->where('id', '<', $beforeId)
                ->latest('id')
                ->limit(100)
                ->get()
                ->reverse()
                ->values();
        } elseif ($afterId > 0) {
            $messages = $query->where('id', '>', $afterId)
                ->oldest('id')
                ->limit(100)
                ->get();
        } else {
            $messages = $query->latest('id')
                ->limit(100)
                ->get()
                ->reverse()
                ->values();
        }
        $members = ProjectChatMessageSerializer::projectMembers($project);
        $readReceipts = ProjectChatMessageSerializer::readReceipts(
            $project,
            'direct',
            $conversation->id,
        );

        return response()->json([
            'messages' => $messages->map(fn (ProjectMessage $message) => ProjectChatMessageSerializer::serialize(
                $message,
                $project,
                $members,
                $readReceipts,
            )
            ),
            'last_message_id' => $conversation->messages()->max('id') ?? 0,
            'has_more' => $messages->count() === 100,
        ]);
    }

    public function files(Request $request, Project $project): JsonResponse
    {
        $userId = $request->user()->id;
        $isOwner = $project->user_id === $userId;
        $isMember = $project->members()->where('user_id', $userId)->exists();
        abort_unless($isOwner || $isMember, 403);

        $members = ProjectChatMessageSerializer::projectMembers($project);
        $conversations = $project->directConversations()
            ->with([
                'member:id,name,role',
                'messages' => fn ($query) => $query
                    ->whereNotNull('attachment_path')
                    ->whereNull('deleted_at')
                    ->with('sender:id,name,role')
                    ->latest('id'),
            ])
            ->when(
                $isOwner,
                fn ($query) => $query->whereIn(
                    'member_user_id',
                    $project->members()->select('user_id'),
                ),
                fn ($query) => $query->where('member_user_id', $userId),
            )
            ->get();

        $files = $conversations->flatMap(function ($conversation) use ($project, $members) {
            $membership = $members->get($conversation->member_user_id);
            $member = $conversation->member;

            return $conversation->messages->map(function (ProjectMessage $message) use (
                $project,
                $members,
                $membership,
                $member,
            ) {
                return [
                    ...ProjectChatMessageSerializer::serialize(
                        $message,
                        $project,
                        $members,
                    ),
                    'conversation_member' => [
                        'user_id' => $member->id,
                        'name' => $membership?->display_name ?: $member->name,
                        'role' => $membership?->role ?: $member->role,
                        'designation' => $membership?->designation,
                    ],
                ];
            });
        })->values();

        return response()->json(['files' => $files]);
    }

    public function store(
        Request $request,
        Project $project,
        int $memberUserId,
    ): JsonResponse {
        $conversation = $this->conversationForParticipant(
            $request,
            $project,
            $memberUserId,
        );
        $validated = $request->validate([
            'body' => ['required', 'string', 'max:4000'],
            'reply_to_message_id' => ['nullable', 'integer'],
        ]);
        $replyTo = $this->replyTarget(
            $conversation,
            $validated['reply_to_message_id'] ?? null,
        );

        $message = $conversation->messages()->create([
            'sender_user_id' => $request->user()->id,
            'body' => trim($validated['body']),
            'reply_to_message_id' => $replyTo?->id,
        ])->load(['sender:id,name,role', 'replyTo.sender:id,name,role']);
        $this->notifyConversationRecipient(
            $request,
            $project,
            $conversation,
            $message,
        );
        $this->broadcastMessage(
            $project,
            $conversation,
            $memberUserId,
            $message,
        );

        return response()->json([
            'message' => ProjectChatMessageSerializer::serialize(
                $message,
                $project,
                ProjectChatMessageSerializer::projectMembers($project),
            ),
        ], 201);
    }

    public function storeAttachment(
        Request $request,
        Project $project,
        int $memberUserId,
    ): JsonResponse {
        $conversation = $this->conversationForParticipant(
            $request,
            $project,
            $memberUserId,
        );
        $validated = $request->validate([
            'file' => [
                'required',
                'file',
                'max:25600',
            ],
            'message_type' => ['required', 'in:image,file,voice'],
            'reply_to_message_id' => ['nullable', 'integer'],
        ]);
        $replyTo = $this->replyTarget(
            $conversation,
            $validated['reply_to_message_id'] ?? null,
        );
        $file = $validated['file'];
        $extension = strtolower($file->getClientOriginalExtension());
        $type = $validated['message_type'];
        abort_unless($this->attachmentMatchesType($file->getRealPath(), $extension, $type), 422,
            'The attachment content does not match a supported image, PDF, or voice-note format.');

        $path = $file->store("project-chat/{$conversation->id}", 'local');
        if ($path === false) {
            return response()->json([
                'message' => 'The attachment could not be saved. Please try again.',
            ], 500);
        }

        $message = $conversation->messages()->create([
            'sender_user_id' => $request->user()->id,
            'body' => null,
            'message_type' => $type,
            'attachment_path' => $path,
            'attachment_name' => $file->getClientOriginalName(),
            'attachment_mime_type' => $file->getMimeType() ?: 'application/octet-stream',
            'attachment_size' => $file->getSize(),
            'reply_to_message_id' => $replyTo?->id,
        ])->load(['sender:id,name,role', 'replyTo.sender:id,name,role']);
        $this->notifyConversationRecipient(
            $request,
            $project,
            $conversation,
            $message,
        );
        $this->broadcastMessage(
            $project,
            $conversation,
            $memberUserId,
            $message,
        );

        return response()->json([
            'message' => ProjectChatMessageSerializer::serialize(
                $message,
                $project,
                ProjectChatMessageSerializer::projectMembers($project),
            ),
        ], 201);
    }

    public function storeLocation(
        Request $request,
        Project $project,
        int $memberUserId,
    ): JsonResponse {
        $conversation = $this->conversationForParticipant(
            $request,
            $project,
            $memberUserId,
        );
        $validated = $request->validate([
            'latitude' => ['required', 'numeric', 'between:-90,90'],
            'longitude' => ['required', 'numeric', 'between:-180,180'],
            'address' => ['required', 'string', 'max:255'],
            'reply_to_message_id' => ['nullable', 'integer'],
        ]);
        $replyTo = $this->replyTarget(
            $conversation,
            $validated['reply_to_message_id'] ?? null,
        );
        $message = $conversation->messages()->create([
            'sender_user_id' => $request->user()->id,
            'body' => $validated['address'],
            'message_type' => 'location',
            'reply_to_message_id' => $replyTo?->id,
            'location_latitude' => $validated['latitude'],
            'location_longitude' => $validated['longitude'],
            'location_address' => $validated['address'],
        ])->load(['sender:id,name,role', 'replyTo.sender:id,name,role']);
        $this->notifyConversationRecipient(
            $request,
            $project,
            $conversation,
            $message,
        );
        $this->broadcastMessage(
            $project,
            $conversation,
            $memberUserId,
            $message,
        );

        return response()->json([
            'message' => ProjectChatMessageSerializer::serialize(
                $message,
                $project,
                ProjectChatMessageSerializer::projectMembers($project),
            ),
        ], 201);
    }

    public function updateMessage(
        Request $request,
        Project $project,
        int $memberUserId,
        ProjectMessage $message,
    ): JsonResponse {
        $conversation = $this->conversationForParticipant(
            $request,
            $project,
            $memberUserId,
        );
        abort_unless($message->conversation_id === $conversation->id, 404);
        abort_unless(
            $message->sender_user_id === $request->user()->id
                && $message->deleted_at === null
                && $message->message_type === 'text',
            403,
        );
        $validated = $request->validate([
            'body' => ['required', 'string', 'max:4000'],
        ]);
        $message->forceFill([
            'body' => trim($validated['body']),
            'edited_at' => now(),
        ])->save();
        $message->load(['sender:id,name,role', 'replyTo.sender:id,name,role']);
        $this->broadcastMessage(
            $project,
            $conversation,
            $memberUserId,
            $message,
            'updated',
        );

        return response()->json([
            'message' => ProjectChatMessageSerializer::serialize(
                $message,
                $project,
                ProjectChatMessageSerializer::projectMembers($project),
            ),
        ]);
    }

    public function deleteMessage(
        Request $request,
        Project $project,
        int $memberUserId,
        ProjectMessage $message,
    ): JsonResponse {
        $conversation = $this->conversationForParticipant(
            $request,
            $project,
            $memberUserId,
        );
        abort_unless($message->conversation_id === $conversation->id, 404);
        abort_unless(
            $message->sender_user_id === $request->user()->id
                && $message->deleted_at === null,
            403,
        );
        if ($message->attachment_path !== null) {
            $disk = Storage::disk('local');
            if ($disk->exists($message->attachment_path)
                && ! $disk->delete($message->attachment_path)) {
                return response()->json([
                    'message' => 'The attachment could not be deleted. Please try again.',
                ], 500);
            }
        }
        $message->forceFill([
            'body' => null,
            'message_type' => 'deleted',
            'attachment_path' => null,
            'attachment_name' => null,
            'attachment_mime_type' => null,
            'attachment_size' => null,
            'location_latitude' => null,
            'location_longitude' => null,
            'location_address' => null,
            'deleted_at' => now(),
        ])->save();
        $message->load(['sender:id,name,role', 'replyTo.sender:id,name,role']);
        $this->broadcastMessage(
            $project,
            $conversation,
            $memberUserId,
            $message,
            'deleted',
        );

        return response()->json([
            'message' => ProjectChatMessageSerializer::serialize(
                $message,
                $project,
                ProjectChatMessageSerializer::projectMembers($project),
            ),
        ]);
    }

    public function markRead(
        Request $request,
        Project $project,
        int $memberUserId,
    ): JsonResponse {
        $conversation = $this->conversationForParticipant(
            $request,
            $project,
            $memberUserId,
        );
        $lastMessageId = (int) ($conversation->messages()->max('id') ?? 0);
        DB::table('project_chat_reads')->updateOrInsert(
            [
                'project_id' => $project->id,
                'user_id' => $request->user()->id,
                'conversation_type' => 'direct',
                'conversation_id' => $conversation->id,
            ],
            [
                'last_read_message_id' => $lastMessageId,
                'updated_at' => now(),
            ],
        );

        return response()->json(['last_read_message_id' => $lastMessageId]);
    }

    public function downloadAttachment(
        Request $request,
        Project $project,
        int $memberUserId,
        ProjectMessage $message,
    ): BinaryFileResponse {
        $conversation = $this->conversationForParticipant(
            $request,
            $project,
            $memberUserId,
        );
        abort_unless(
            $message->conversation_id === $conversation->id
                && $message->deleted_at === null
                && $message->attachment_path !== null,
            404,
        );

        $disk = Storage::disk('local');
        abort_unless($disk->exists($message->attachment_path), 404);

        return response()->download(
            $disk->path($message->attachment_path),
            $message->attachment_name ?? 'project-attachment',
            ['Content-Type' => $message->attachment_mime_type ?? 'application/octet-stream'],
        );
    }

    private function conversationForParticipant(
        Request $request,
        Project $project,
        int $memberUserId,
    ): ProjectConversation {
        $userId = $request->user()->id;
        $isOwner = $project->user_id === $userId;
        $isProjectMember = $project->members()
            ->where('user_id', $memberUserId)
            ->exists();
        abort_unless($isProjectMember && $memberUserId !== $project->user_id, 404);
        abort_unless($isOwner || $userId === $memberUserId, 403);

        return $project->directConversations()->firstOrCreate([
            'member_user_id' => $memberUserId,
        ]);
    }

    private function replyTarget(
        ProjectConversation $conversation,
        mixed $replyToId,
    ): ?ProjectMessage {
        if ($replyToId === null) {
            return null;
        }

        return $conversation->messages()
            ->whereNull('deleted_at')
            ->findOrFail($replyToId);
    }

    private function broadcastMessage(
        Project $project,
        ProjectConversation $conversation,
        int $memberUserId,
        ProjectMessage $message,
        string $change = 'created',
    ): void {
        broadcast(new ProjectChatMessageChanged(
            projectId: $project->id,
            conversationType: 'direct',
            conversationId: $conversation->id,
            memberUserId: $memberUserId,
            message: ProjectChatMessageSerializer::serialize(
                $message,
                $project,
                ProjectChatMessageSerializer::projectMembers($project),
            ),
            change: $change,
        ));
    }

    private function notifyConversationRecipient(
        Request $request,
        Project $project,
        ProjectConversation $conversation,
        ProjectMessage $message,
    ): void {
        $actor = $request->user();
        $recipientId = $actor->id === $project->user_id
            ? $conversation->member_user_id
            : $project->user_id;
        $preview = match ($message->message_type) {
            'image' => 'Sent an image.',
            'file' => 'Sent a file: '.($message->attachment_name ?? 'attachment'),
            'voice' => 'Sent a voice message.',
            'location' => 'Shared a location.',
            default => mb_strimwidth($message->body ?? '', 0, 120, '…'),
        };
        $recipient = User::query()->findOrFail($recipientId);
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
        $recipient->notify($notification);
        $this->firebasePushService->queue(
            $recipient,
            $notification->toPushPayload([
                'conversation_type' => 'direct',
                'member_user_id' => (string) $conversation->member_user_id,
            ]),
        );
    }

    private function attachmentMatchesType(string $path, string $extension, string $type): bool
    {
        if ($type === 'image') {
            $image = @getimagesize($path);
            if ($image === false) {
                return false;
            }

            return match ($extension) {
                'jpg', 'jpeg' => $image[2] === IMAGETYPE_JPEG,
                'png' => $image[2] === IMAGETYPE_PNG,
                'webp' => $image[2] === IMAGETYPE_WEBP,
                default => false,
            };
        }

        $header = file_get_contents($path, false, null, 0, 12);
        if ($header === false) {
            return false;
        }

        if ($type === 'file') {
            return $extension === 'pdf' && str_starts_with($header, '%PDF-');
        }

        return match ($extension) {
            'm4a' => strlen($header) >= 8 && substr($header, 4, 4) === 'ftyp',
            'mp3' => str_starts_with($header, 'ID3')
                || (strlen($header) >= 2
                    && ord($header[0]) === 0xFF
                    && (ord($header[1]) & 0xE0) === 0xE0),
            'wav' => strlen($header) >= 12
                && substr($header, 0, 4) === 'RIFF'
                && substr($header, 8, 4) === 'WAVE',
            'aac' => strlen($header) >= 2
                && ord($header[0]) === 0xFF
                && (ord($header[1]) & 0xF6) === 0xF0,
            'ogg' => str_starts_with($header, 'OggS'),
            'webm' => str_starts_with($header, "\x1A\x45\xDF\xA3"),
            default => false,
        };
    }
}
