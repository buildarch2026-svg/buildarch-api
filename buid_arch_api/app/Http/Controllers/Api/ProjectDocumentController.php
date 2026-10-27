<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Project;
use App\Models\ProjectDocument;
use App\Models\User;
use App\Notifications\ProjectActivityNotification;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;
use Symfony\Component\HttpFoundation\BinaryFileResponse;

class ProjectDocumentController extends Controller
{
    public function index(Request $request, Project $project): JsonResponse
    {
        $this->authorizeProjectAccess($request, $project);

        $documents = $project->documents()
            ->with('uploadedBy:id,name')
            ->latest('id')
            ->get()
            ->map(fn (ProjectDocument $document) => $this->documentResponse($document));

        return response()->json(['documents' => $documents]);
    }

    public function store(Request $request, Project $project): JsonResponse
    {
        $this->authorizeProjectAccess($request, $project);

        $validated = $request->validate([
            'file' => [
                'required',
                'file',
                'mimes:jpg,jpeg,png,webp,pdf',
                'max:102400',
            ],
        ]);
        $file = $validated['file'];
        $path = $file->store("project-documents/{$project->id}", 'local');

        if ($path === false) {
            return response()->json([
                'message' => 'The file could not be saved. Please try again.',
            ], 500);
        }

        $isDesigner = $project->members()
            ->where('user_id', $request->user()->id)
            ->where('role', 'designer')
            ->exists();

        $document = $project->documents()->create([
            'uploaded_by_user_id' => $request->user()->id,
            'name' => $file->getClientOriginalName(),
            'path' => $path,
            'mime_type' => $file->getMimeType() ?: 'application/octet-stream',
            'size' => $file->getSize(),
            'category' => $isDesigner ? 'drawings' : 'general',
        ])->load('uploadedBy:id,name');

        $recipientIds = $project->members()
            ->where('user_id', '!=', $request->user()->id)
            ->pluck('user_id')
            ->push($project->user_id)
            ->unique();
        $actor = $request->user();
        User::query()->whereIn('id', $recipientIds)->get()->each(
            fn (User $recipient) => $recipient->notify(
                new ProjectActivityNotification(
                    event: 'file_upload',
                    title: 'New project file',
                    message: "{$actor->name} uploaded {$document->name}.",
                    projectId: $project->id,
                    projectName: $project->name,
                    actorId: $actor->id,
                    actorName: $actor->name,
                    relatedId: $document->id,
                ),
            ),
        );

        return response()->json([
            'document' => $this->documentResponse($document),
        ], 201);
    }

    public function download(
        Request $request,
        Project $project,
        ProjectDocument $document,
    ): BinaryFileResponse {
        $this->authorizeProjectAccess($request, $project);
        abort_unless($document->project_id === $project->id, 404);

        $disk = Storage::disk('local');
        abort_unless($disk->exists($document->path), 404);

        return response()->download(
            $disk->path($document->path),
            $document->name,
            ['Content-Type' => $document->mime_type],
        );
    }

    private function authorizeProjectAccess(Request $request, Project $project): void
    {
        $user = $request->user();
        $isOwner = $project->user_id === $user->id;
        $isMember = $project->members()->where('user_id', $user->id)->exists();

        abort_unless($isOwner || $isMember, 403);
    }

    private function documentResponse(ProjectDocument $document): array
    {
        return [
            'id' => $document->id,
            'name' => $document->name,
            'mime_type' => $document->mime_type,
            'size' => $document->size,
            'category' => $document->category,
            'uploaded_by' => $document->uploadedBy?->name,
            'created_at' => $document->created_at?->toIso8601String(),
        ];
    }
}
