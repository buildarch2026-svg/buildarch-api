<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Project;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
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
            ->where('user_id', $user->id)
            ->orWhereHas('members', fn ($query) => $query->where('user_id', $user->id))
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

    private function projectResponse($project, Request $request): array
    {
        $membership = $project->members->first();
        $acceptedInvitation = $project->invitations->first();

        return [
            ...$project->attributesToArray(),
            'is_owner' => $project->user_id === $request->user()->id,
            'member_role' => $membership?->role,
            'invited_by_name' => $acceptedInvitation?->invitedBy?->name,
            'photo_url' => $project->image_path
                ? $request->getSchemeAndHttpHost().'/storage/'.$project->image_path
                : null,
        ];
    }
}
