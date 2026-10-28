<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Project;
use App\Models\ProjectGroupConversation;
use App\Models\ProjectGroupMessage;
use App\Models\User;
use App\Notifications\ProjectActivityNotification;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;
use Illuminate\Http\UploadedFile;
use Symfony\Component\HttpFoundation\BinaryFileResponse;

class ProjectGroupChatController extends Controller
{
    public function index(Request $request, Project $project): JsonResponse
    {
        $conversation = $this->conversationForParticipant($request, $project);
        $afterId = max(0, (int) $request->query('after_id', 0));
        $query = $conversation->messages()->with('sender:id,name');
        $messages = $afterId === 0
            ? $query->latest('id')->limit(100)->get()->reverse()
            : $query->where('id', '>', $afterId)->oldest('id')->limit(100)->get();

        return response()->json([
            'messages' => $messages->values()->map(
                fn (ProjectGroupMessage $message) => $this->messageResponse($message),
            ),
            'last_message_id' => $conversation->messages()->max('id') ?? 0,
        ]);
    }

    public function files(Request $request, Project $project): JsonResponse
    {
        $conversation = $this->conversationForParticipant($request, $project);
        $messages = $conversation->messages()
            ->whereNotNull('attachment_path')
            ->with('sender:id,name')
            ->latest('id')
            ->get();

        return response()->json([
            'files' => $messages->map(
                fn (ProjectGroupMessage $message) => $this->messageResponse($message),
            ),
        ]);
    }

    public function storeText(Request $request, Project $project): JsonResponse
    {
        $conversation = $this->conversationForParticipant($request, $project);
        $validated = $request->validate([
            'body' => ['required', 'string', 'max:4000'],
            'file' => ['prohibited'],
        ]);
        $message = $conversation->messages()->create([
            'sender_user_id' => $request->user()->id,
            'body' => trim($validated['body']),
            'message_type' => 'text',
        ])->load('sender:id,name');
        $this->notifyGroupMembers($request, $project, $message);

        return response()->json([
            'message' => $this->messageResponse($message),
        ], 201);
    }

    public function storeAttachment(Request $request, Project $project): JsonResponse
    {
        $conversation = $this->conversationForParticipant($request, $project);
        $validated = $request->validate([
            'file' => ['required', 'file', 'max:25600'],
            'message_type' => ['nullable', 'in:image,voice'],
            'body' => ['prohibited'],
        ]);
        /** @var UploadedFile $file */
        $file = $validated['file'];
        $type = $validated['message_type'] ?? 'voice';
        $extension = strtolower($file->getClientOriginalExtension());
        $path = $file->getRealPath();
        abort_unless(
            $path !== false && (
                ($type === 'voice' && $this->isSupportedVoiceFile($path, $extension))
                || ($type === 'image' && $this->isSupportedImageFile($path, $extension))
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
        ])->load('sender:id,name');

        $this->notifyGroupMembers($request, $project, $message);

        return response()->json([
            'message' => $this->messageResponse($message),
        ], 201);
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
            fn (User $recipient) => $recipient->notify(
                new ProjectActivityNotification(
                    event: 'chat_message',
                    title: "New message from {$actor->name}",
                    message: match ($message->message_type) {
                        'voice' => "{$actor->name} sent a voice message in the group.",
                        'image' => "{$actor->name} shared an image in the group.",
                        default => "{$actor->name}: "
                            .mb_strimwidth($message->body ?? '', 0, 120, '…'),
                    },
                    projectId: $project->id,
                    projectName: $project->name,
                    actorId: $actor->id,
                    actorName: $actor->name,
                    relatedId: $message->id,
                ),
            ),
        );
    }

    public function downloadAttachment(
        Request $request,
        Project $project,
        ProjectGroupMessage $message,
    ): BinaryFileResponse {
        $conversation = $this->conversationForParticipant($request, $project);
        abort_unless($message->conversation_id === $conversation->id, 404);

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

    private function messageResponse(ProjectGroupMessage $message): array
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
}
