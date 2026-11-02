<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Project;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;
use Illuminate\Validation\Rule;

class ProjectController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $user = $request->user();
        $projects = Project::query()
            ->with([
                'members' => fn ($query) => $query->where('user_id', $user->id),
                'invitations' => fn ($query) => $query
                    ->where('accepted_by_user_id', $user->id)
                    ->where('status', 'accepted')
                    ->with('invitedBy:id,name'),
            ])
            ->where(function ($query) use ($user) {
                $query->where('projects.user_id', $user->id)
                    ->orWhere(function ($membership) use ($user) {
                        $membership->whereNull('projects.deleted_at')
                            ->whereNull('projects.archived_at')
                            ->whereHas(
                                'members',
                                fn ($members) => $members->where('user_id', $user->id),
                            );
                    });
            })
            ->latest('id')
            ->get()
            ->map(fn ($project) => $this->projectResponse($project, $request));

        return response()->json([
            'projects' => $projects,
        ]);
    }

    public function store(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'location' => ['required', 'string', 'max:255'],
            'latitude' => ['nullable', 'required_with:longitude', 'numeric', 'between:-90,90'],
            'longitude' => ['nullable', 'required_with:latitude', 'numeric', 'between:-180,180'],
            'type' => [
                'required',
                Rule::in([
                    'new_construction',
                    'renovation',
                    'interior_designing',
                ]),
            ],
            'photo' => ['nullable', 'image', 'mimes:jpg,jpeg,png,webp', 'max:10240'],
        ]);

        $imagePath = $request->file('photo')?->store('projects', 'public');
        if ($request->hasFile('photo') && $imagePath === false) {
            return response()->json([
                'message' => 'The project photo could not be saved. Please try again.',
            ], 500);
        }

        $project = $request->user()->projects()->create([
            ...collect($validated)->except('photo')->all(),
            'image_path' => $imagePath,
        ])->refresh();

        return response()->json([
            'project' => $this->projectResponse($project, $request),
        ], 201);
    }

    public function update(Request $request, Project $project): JsonResponse
    {
        abort_unless($project->user_id === $request->user()->id, 403);

        $validated = $request->validate([
            'name' => ['sometimes', 'required', 'string', 'max:255'],
            'location' => ['sometimes', 'required', 'string', 'max:255'],
            'latitude' => ['sometimes', 'nullable', 'required_with:longitude', 'numeric', 'between:-90,90'],
            'longitude' => ['sometimes', 'nullable', 'required_with:latitude', 'numeric', 'between:-180,180'],
            'type' => [
                'sometimes',
                'required',
                Rule::in([
                    'new_construction',
                    'renovation',
                    'interior_designing',
                ]),
            ],
        ]);

        $project->update($validated);

        return response()->json([
            'project' => $this->projectResponse($project->refresh(), $request),
        ]);
    }

    public function archive(Request $request, Project $project): JsonResponse
    {
        abort_unless($project->user_id === $request->user()->id, 403);

        if ($project->archived_at === null) {
            $project->forceFill(['archived_at' => now()])->save();
        }

        return response()->json([
            'project' => $this->projectResponse($project->refresh(), $request),
        ]);
    }

    public function delete(Request $request, Project $project): JsonResponse
    {
        abort_unless($project->user_id === $request->user()->id, 403);

        if (! $project->trashed()) {
            $project->delete();
        }

        return response()->json([
            'project' => $this->projectResponse($project->refresh(), $request),
        ]);
    }

    public function restore(Request $request, Project $project): JsonResponse
    {
        abort_unless($project->user_id === $request->user()->id, 403);

        if ($project->trashed()) {
            $project->restore();
        }
        if ($project->archived_at !== null) {
            $project->forceFill(['archived_at' => null])->save();
        }

        return response()->json([
            'project' => $this->projectResponse($project->refresh(), $request),
        ]);
    }

    public function updatePhoto(Request $request, Project $project): JsonResponse
    {
        abort_unless($project->user_id === $request->user()->id, 403);

        $validated = $request->validate([
            'photo' => ['required', 'image', 'mimes:jpg,jpeg,png,webp', 'max:10240'],
        ]);
        $imagePath = $validated['photo']->store('projects', 'public');
        if ($imagePath === false) {
            return response()->json([
                'message' => 'The project photo could not be saved. Please try again.',
            ], 500);
        }

        $previousImagePath = $project->image_path;
        $project->image_path = $imagePath;
        $project->save();
        $project->refresh();

        if ($previousImagePath && $previousImagePath !== $imagePath) {
            Storage::disk('public')->delete($previousImagePath);
        }

        return response()->json([
            'project' => $this->projectResponse($project, $request),
        ]);
    }

    private function projectResponse($project, Request $request): array
    {
        $membership = $project->members->first();
        $acceptedInvitation = $project->invitations->first();

        return [
            ...$project->attributesToArray(),
            'is_owner' => $project->user_id === $request->user()->id,
            'is_archived' => $project->archived_at !== null,
            'is_deleted' => $project->trashed(),
            'member_role' => $membership?->role,
            'invited_by_name' => $acceptedInvitation?->invitedBy?->name,
            'photo_url' => $project->image_path
                ? $request->getSchemeAndHttpHost().'/storage/'.$project->image_path
                : null,
        ];
    }
}
