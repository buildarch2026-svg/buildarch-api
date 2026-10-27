<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Project;
use App\Models\ProjectConversation;
use App\Models\ProjectMessage;
use App\Models\User;
use App\Notifications\ProjectActivityNotification;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;
use Symfony\Component\HttpFoundation\BinaryFileResponse;

class ProjectMessageController extends Controller
{
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

        $query = $conversation->messages()->with('sender:id,name');
        $messages = $afterId === 0
            ? $query->latest('id')->limit(100)->get()->reverse()
            : $query->where('id', '>', $afterId)->oldest('id')->limit(100)->get();
        $messages = $messages
            ->values()
            ->map(fn (ProjectMessage $message) => $this->messageResponse($message));

        return response()->json([
            'messages' => $messages,
            'last_message_id' => $conversation->messages()->max('id') ?? 0,
        ]);
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
        ]);

        $message = $conversation->messages()->create([
            'sender_user_id' => $request->user()->id,
            'body' => trim($validated['body']),
        ])->load('sender:id,name');
        $this->notifyConversationRecipient(
            $request,
            $project,
            $conversation,
            $message,
        );

        return response()->json([
            'message' => $this->messageResponse($message),
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
        ]);
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
        ])->load('sender:id,name');
        $this->notifyConversationRecipient(
            $request,
            $project,
            $conversation,
            $message,
        );

        return response()->json([
            'message' => $this->messageResponse($message),
        ], 201);
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

    private function messageResponse(ProjectMessage $message): array
    {
        return [
            'id' => $message->id,
            'body' => $message->body,
            'message_type' => $message->message_type,
            'attachment_name' => $message->attachment_name,
            'attachment_mime_type' => $message->attachment_mime_type,
            'attachment_size' => $message->attachment_size,
            'sender_user_id' => $message->sender_user_id,
            'sender_name' => $message->sender?->name,
            'created_at' => $message->created_at?->toIso8601String(),
        ];
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
            default => mb_strimwidth($message->body ?? '', 0, 120, '…'),
        };
        User::query()->findOrFail($recipientId)->notify(
            new ProjectActivityNotification(
                event: 'chat_message',
                title: "New message from {$actor->name}",
                message: $preview,
                projectId: $project->id,
                projectName: $project->name,
                actorId: $actor->id,
                actorName: $actor->name,
                relatedId: $message->id,
            ),
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
