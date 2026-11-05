<?php

namespace App\Http\Controllers\Api;

use App\Events\ProjectChatMessageChanged;
use App\Http\Controllers\Controller;
use App\Models\Project;
use App\Models\ProjectGroupConversation;
use App\Models\ProjectGroupMessage;
use App\Models\User;
use App\Notifications\ProjectActivityNotification;
use App\Services\FirebasePushService;
use App\Services\ProjectChatMessageSerializer;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Symfony\Component\HttpFoundation\BinaryFileResponse;

class ProjectGroupChatController extends Controller
{
    public function __construct(
        private readonly FirebasePushService $firebasePushService,
    ) {}

    public function index(Request $request, Project $project): JsonResponse
    {
        $conversation = $this->conversationForParticipant($request, $project);
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
            'group',
            $conversation->id,
        );

        return response()->json([
            'messages' => $messages->map(
                fn (ProjectGroupMessage $message) => ProjectChatMessageSerializer::serialize(
                    $message,
                    $project,
                    $members,
                    $readReceipts,
                ),
            ),
            'last_message_id' => $conversation->messages()->max('id') ?? 0,
            'has_more' => $messages->count() === 100,
        ]);
    }

    public function files(Request $request, Project $project): JsonResponse
    {
        $conversation = $this->conversationForParticipant($request, $project);
        $messages = $conversation->messages()
            ->whereNotNull('attachment_path')
            ->whereNull('deleted_at')
            ->with('sender:id,name,role')
            ->latest('id')
            ->get();

        return response()->json([
            'files' => $messages->map(
                fn (ProjectGroupMessage $message) => ProjectChatMessageSerializer::serialize(
                    $message,
                    $project,
                    ProjectChatMessageSerializer::projectMembers($project),
                ),
            ),
        ]);
    }

    public function storeText(Request $request, Project $project): JsonResponse
    {
        $conversation = $this->conversationForParticipant($request, $project);
        $validated = $request->validate([
            'body' => ['required', 'string', 'max:4000'],
            'file' => ['prohibited'],
            'reply_to_message_id' => ['nullable', 'integer'],
        ]);
        $replyTo = $this->replyTarget(
            $conversation,
            $validated['reply_to_message_id'] ?? null,
        );
        $message = $conversation->messages()->create([
            'sender_user_id' => $request->user()->id,
            'body' => trim($validated['body']),
            'message_type' => 'text',
            'reply_to_message_id' => $replyTo?->id,
        ])->load(['sender:id,name,role', 'replyTo.sender:id,name,role']);
        $this->notifyGroupMembers($request, $project, $message);
        $this->broadcastMessage($project, $conversation, $message);

        return response()->json([
            'message' => ProjectChatMessageSerializer::serialize(
                $message,
                $project,
                ProjectChatMessageSerializer::projectMembers($project),
            ),
        ], 201);
    }

    public function storeAttachment(Request $request, Project $project): JsonResponse
    {
        $conversation = $this->conversationForParticipant($request, $project);
        $validated = $request->validate([
            'file' => ['required', 'file', 'max:25600'],
            'message_type' => ['nullable', 'in:image,file,voice'],
            'body' => ['prohibited'],
            'reply_to_message_id' => ['nullable', 'integer'],
        ]);
        $replyTo = $this->replyTarget(
            $conversation,
            $validated['reply_to_message_id'] ?? null,
        );
        /** @var UploadedFile $file */
        $file = $validated['file'];
        $type = $validated['message_type'] ?? 'voice';
        $extension = strtolower($file->getClientOriginalExtension());
        $path = $file->getRealPath();
        abort_unless(
            $path !== false && (
                ($type === 'voice' && $this->isSupportedVoiceFile($path, $extension))
                || ($type === 'image' && $this->isSupportedImageFile($path, $extension))
                || ($type === 'file' && $this->isSupportedDocumentFile($path, $extension))
            ),
            422,
            'The attachment content does not match the selected message type.',
        );

        $attachmentPath = $file->store(
            "project-group-chat/{$conversation->id}",
            'local',
        );
        if ($attachmentPath === false) {
            return response()->json([
                'message' => 'The voice recording could not be saved. Please try again.',
            ], 500);
        }

        $message = $conversation->messages()->create([
            'sender_user_id' => $request->user()->id,
            'message_type' => $type,
            'attachment_path' => $attachmentPath,
            'attachment_name' => $file->getClientOriginalName(),
            'attachment_mime_type' => $file->getMimeType() ?: 'application/octet-stream',
            'attachment_size' => $file->getSize(),
            'reply_to_message_id' => $replyTo?->id,
        ])->load(['sender:id,name,role', 'replyTo.sender:id,name,role']);

        $this->notifyGroupMembers($request, $project, $message);
        $this->broadcastMessage($project, $conversation, $message);

        return response()->json([
            'message' => ProjectChatMessageSerializer::serialize(
                $message,
                $project,
                ProjectChatMessageSerializer::projectMembers($project),
            ),
        ], 201);
    }

    public function storeLocation(Request $request, Project $project): JsonResponse
    {
        $conversation = $this->conversationForParticipant($request, $project);
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
            'message_type' => 'location',
            'body' => $validated['address'],
            'reply_to_message_id' => $replyTo?->id,
            'location_latitude' => $validated['latitude'],
            'location_longitude' => $validated['longitude'],
            'location_address' => $validated['address'],
        ])->load(['sender:id,name,role', 'replyTo.sender:id,name,role']);

        $this->notifyGroupMembers($request, $project, $message);
        $this->broadcastMessage($project, $conversation, $message);

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
        ProjectGroupMessage $message,
    ): JsonResponse {
        $conversation = $this->conversationForParticipant($request, $project);
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
        $this->broadcastMessage($project, $conversation, $message, 'updated');

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
        ProjectGroupMessage $message,
    ): JsonResponse {
        $conversation = $this->conversationForParticipant($request, $project);
        abort_unless($message->conversation_id === $conversation->id, 404);
        abort_unless($message->deleted_at === null, 404);
        abort_unless(
            $message->sender_user_id === $request->user()->id
                || $project->user_id === $request->user()->id,
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
        $this->broadcastMessage($project, $conversation, $message, 'deleted');

        return response()->json([
            'message' => ProjectChatMessageSerializer::serialize(
                $message,
                $project,
                ProjectChatMessageSerializer::projectMembers($project),
            ),
        ]);
    }

    public function markRead(Request $request, Project $project): JsonResponse
    {
        $conversation = $this->conversationForParticipant($request, $project);
        $lastMessageId = (int) ($conversation->messages()->max('id') ?? 0);
        DB::table('project_chat_reads')->updateOrInsert(
            [
                'project_id' => $project->id,
                'user_id' => $request->user()->id,
                'conversation_type' => 'group',
                'conversation_id' => $conversation->id,
            ],
            [
                'last_read_message_id' => $lastMessageId,
                'updated_at' => now(),
            ],
        );

        return response()->json(['last_read_message_id' => $lastMessageId]);
    }

    private function notifyGroupMembers(
        Request $request,
        Project $project,
        ProjectGroupMessage $message,
    ): void {
        $recipientIds = $project->members()
            ->where('user_id', '!=', $request->user()->id)
            ->pluck('user_id')
            ->push($project->user_id)
            ->unique()
            ->reject(fn (int $userId) => $userId === $request->user()->id);
        $actor = $request->user();
        User::query()->whereIn('id', $recipientIds)->get()->each(
            function (User $recipient) use ($actor, $project, $message) {
                $notification = new ProjectActivityNotification(
                    event: 'chat_message',
                    title: "New message from {$actor->name}",
                    message: match ($message->message_type) {
                        'voice' => "{$actor->name} sent a voice message in the group.",
                        'image' => "{$actor->name} shared an image in the group.",
                        'file' => "{$actor->name} shared a file in the group.",
                        'location' => "{$actor->name} shared a location in the group.",
                        default => "{$actor->name}: "
                            .mb_strimwidth($message->body ?? '', 0, 120, '…'),
                    },
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
                        'conversation_type' => 'group',
                    ]),
                );
            },
        );
    }

    public function downloadAttachment(
        Request $request,
        Project $project,
        ProjectGroupMessage $message,
    ): BinaryFileResponse {
        $conversation = $this->conversationForParticipant($request, $project);
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
            $message->attachment_name,
            ['Content-Type' => $message->attachment_mime_type ?? 'application/octet-stream'],
        );
    }

    private function conversationForParticipant(
        Request $request,
        Project $project,
    ): ProjectGroupConversation {
        $userId = $request->user()->id;
        $isOwner = $project->user_id === $userId;
        $isMember = $project->members()->where('user_id', $userId)->exists();
        abort_unless($isOwner || $isMember, 403);

        return ProjectGroupConversation::firstOrCreate([
            'project_id' => $project->id,
        ]);
    }

    private function replyTarget(
        ProjectGroupConversation $conversation,
        mixed $replyToId,
    ): ?ProjectGroupMessage {
        if ($replyToId === null) {
            return null;
        }

        return $conversation->messages()
            ->whereNull('deleted_at')
            ->findOrFail($replyToId);
    }

    private function broadcastMessage(
        Project $project,
        ProjectGroupConversation $conversation,
        ProjectGroupMessage $message,
        string $change = 'created',
    ): void {
        $members = ProjectChatMessageSerializer::projectMembers($project);
        broadcast(new ProjectChatMessageChanged(
            projectId: $project->id,
            conversationType: 'group',
            conversationId: $conversation->id,
            memberUserId: null,
            message: ProjectChatMessageSerializer::serialize(
                $message,
                $project,
                $members,
            ),
            change: $change,
        ));
    }

    private function isSupportedVoiceFile(string $path, string $extension): bool
    {
        $header = file_get_contents($path, false, null, 0, 12);
        if ($header === false) {
            return false;
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

    private function isSupportedImageFile(string $path, string $extension): bool
    {
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

    private function isSupportedDocumentFile(string $path, string $extension): bool
    {
        if ($extension !== 'pdf') {
            return false;
        }
        $header = file_get_contents($path, false, null, 0, 5);

        return $header !== false && str_starts_with($header, '%PDF-');
    }
}
