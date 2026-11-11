<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\CommunityCategory;
use App\Models\CommunityComment;
use App\Models\CommunityContactRequest;
use App\Models\CommunityMemberBlock;
use App\Models\CommunityPost;
use App\Models\CommunityProfile;
use App\Models\CommunityReport;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;
use Symfony\Component\HttpFoundation\BinaryFileResponse;

class CommunityController extends Controller
{
    private const PROFESSIONS = [
        'Homeowner',
        'Designer',
        'Contractor',
        'Architect',
        'Civil Engineer',
        'Interior Designer',
        'Student',
        'Other',
    ];

    private const REPORT_REASONS = [
        'spam',
        'harassment',
        'misinformation',
        'inappropriate',
        'other',
    ];

    public function categories(): JsonResponse
    {
        return response()->json([
            'categories' => CommunityCategory::query()
                ->orderBy('id')
                ->get(['id', 'slug', 'name']),
        ]);
    }

    public function profile(Request $request): JsonResponse
    {
        $profile = CommunityProfile::query()
            ->where('user_id', $request->user()->id)
            ->withCount('posts')
            ->first();

        return response()->json([
            'registered' => $profile !== null,
            'profile' => $profile
                ? $this->profileResponse(
                    $profile,
                    includePhoneVisibility: true,
                    includePrivateContact: true,
                )
                : null,
        ]);
    }

    public function register(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'display_name' => ['required', 'string', 'max:80'],
            'profession' => ['nullable', Rule::in(self::PROFESSIONS)],
            'other_profession' => [
                'nullable',
                'required_if:profession,Other',
                'string',
                'max:80',
            ],
            'location' => ['nullable', 'string', 'max:255'],
            'bio' => ['nullable', 'string', 'max:500'],
            'guidelines_accepted' => ['accepted'],
            'profile_image' => ['nullable', 'image', 'mimes:jpg,jpeg,png,webp', 'max:5120'],
        ]);

        if (CommunityProfile::query()->where('user_id', $request->user()->id)->exists()) {
            return response()->json([
                'message' => 'A Community profile already exists for this account.',
            ], 409);
        }

        $imagePath = $request->file('profile_image')?->store(
            'community/profiles',
            'local',
        );
        if ($request->hasFile('profile_image') && $imagePath === false) {
            return response()->json([
                'message' => 'The profile image could not be saved. Please try again.',
            ], 500);
        }

        $profile = DB::transaction(function () use ($request, $validated, $imagePath) {
            $displayName = trim($validated['display_name']);
            $location = isset($validated['location'])
                ? trim($validated['location'])
                : null;
            $profile = CommunityProfile::query()->create([
                'user_id' => $request->user()->id,
                'display_name' => $displayName,
                'profession' => $validated['profession'] ?? null,
                'other_profession' => ($validated['profession'] ?? null) === 'Other'
                    ? trim($validated['other_profession'])
                    : null,
                'location' => $location,
                'bio' => isset($validated['bio']) ? trim($validated['bio']) : null,
                'profile_image_path' => $imagePath,
                'guidelines_accepted_at' => now(),
            ]);

            $user = $request->user();
            $user->forceFill([
                'name' => $displayName,
                'location' => $location ?? $user->location,
            ])->save();

            return $profile->loadCount('posts');
        });

        return response()->json([
            'profile' => $this->profileResponse(
                $profile,
                includePhoneVisibility: true,
                includePrivateContact: true,
            ),
        ], 201);
    }

    public function updateProfile(Request $request): JsonResponse
    {
        $profile = $this->requireProfile($request);
        $validated = $request->validate([
            'display_name' => ['sometimes', 'required', 'string', 'max:80'],
            'profession' => ['sometimes', 'nullable', Rule::in(self::PROFESSIONS)],
            'other_profession' => ['nullable', 'string', 'max:80'],
            'location' => ['sometimes', 'nullable', 'string', 'max:255'],
            'bio' => ['nullable', 'string', 'max:500'],
            'is_phone_visible' => ['sometimes', 'boolean'],
            'latitude' => ['sometimes', 'nullable', 'numeric', 'between:-90,90'],
            'longitude' => ['sometimes', 'nullable', 'numeric', 'between:-180,180'],
            'trade' => ['sometimes', 'nullable', 'string', 'max:120'],
            'skills' => ['sometimes', 'nullable', 'array', 'max:50'],
            'skills.*' => ['string', 'max:80'],
            'experience_years' => ['sometimes', 'nullable', 'integer', 'between:0,80'],
            'preferred_location' => ['sometimes', 'nullable', 'string', 'max:255'],
            'preferred_latitude' => ['sometimes', 'nullable', 'numeric', 'between:-90,90'],
            'preferred_longitude' => ['sometimes', 'nullable', 'numeric', 'between:-180,180'],
            'preferred_categories' => ['sometimes', 'nullable', 'array', 'max:20'],
            'preferred_categories.*' => [
                'integer',
                Rule::exists('job_portal_categories', 'id')->where('is_active', true),
            ],
            'preferred_radius_km' => ['sometimes', 'integer', Rule::in([5, 10, 25, 50, 100])],
            'job_notifications_enabled' => ['sometimes', 'boolean'],
        ]);
        foreach ([
            ['latitude', 'longitude'],
            ['preferred_latitude', 'preferred_longitude'],
        ] as [$latitude, $longitude]) {
            if ($request->has($latitude) !== $request->has($longitude)) {
                throw ValidationException::withMessages([
                    $latitude => 'Provide both coordinates or neither.',
                ]);
            }
        }
        if ($request->boolean('job_notifications_enabled')) {
            if (($validated['preferred_categories'] ?? $profile->preferred_categories ?? []) === []) {
                throw ValidationException::withMessages([
                    'preferred_categories' => 'Choose at least one preferred job category for nearby alerts.',
                ]);
            }
            $hasPreferredCoordinates = ($validated['preferred_latitude'] ?? $profile->preferred_latitude) !== null
                && ($validated['preferred_longitude'] ?? $profile->preferred_longitude) !== null;
            $hasProfileCoordinates = ($validated['latitude'] ?? $profile->latitude) !== null
                && ($validated['longitude'] ?? $profile->longitude) !== null;
            if (! $hasPreferredCoordinates && ! $hasProfileCoordinates) {
                throw ValidationException::withMessages([
                    'preferred_location' => 'Choose a preferred location to enable nearby alerts.',
                ]);
            }
        }

        $profession = array_key_exists('profession', $validated)
            ? $validated['profession']
            : $profile->profession;
        if ($profession === 'Other' &&
            trim((string) ($validated['other_profession'] ?? $profile->other_profession)) === '') {
            return response()->json([
                'message' => 'Enter your profession.',
                'errors' => ['other_profession' => ['Enter your profession.']],
            ], 422);
        }

        $attributes = collect($validated)->only([
            'display_name',
            'profession',
            'location',
            'bio',
            'is_phone_visible',
            'latitude',
            'longitude',
            'trade',
            'skills',
            'experience_years',
            'preferred_location',
            'preferred_latitude',
            'preferred_longitude',
            'preferred_categories',
            'preferred_radius_km',
            'job_notifications_enabled',
        ])->all();
        if (array_key_exists('display_name', $attributes)) {
            $attributes['display_name'] = trim($attributes['display_name']);
        }
        if (array_key_exists('bio', $attributes)) {
            $attributes['bio'] = $attributes['bio'] === null
                ? null
                : trim($attributes['bio']);
        }
        if (array_key_exists('location', $attributes)) {
            $attributes['location'] = $attributes['location'] === null
                ? null
                : trim($attributes['location']);
        }
        foreach (['trade', 'preferred_location'] as $field) {
            if (array_key_exists($field, $attributes)) {
                $attributes[$field] = $attributes[$field] === null
                    ? null
                    : trim($attributes[$field]);
            }
        }
        $attributes['other_profession'] = $profession === 'Other'
            ? trim((string) ($validated['other_profession'] ?? $profile->other_profession))
            : null;

        DB::transaction(function () use ($profile, $attributes): void {
            $profile->update($attributes);

            $userAttributes = [];
            if (array_key_exists('display_name', $attributes)) {
                $userAttributes['name'] = $attributes['display_name'];
            }
            if (array_key_exists('location', $attributes)) {
                $userAttributes['location'] = $attributes['location'];
            }
            if ($userAttributes !== []) {
                $profile->user()->update($userAttributes);
            }
        });

        return response()->json([
            'profile' => $this->profileResponse(
                $profile->fresh()->loadCount('posts'),
                includePhoneVisibility: true,
                includePrivateContact: true,
            ),
        ]);
    }

    public function updateProfileImage(Request $request): JsonResponse
    {
        $profile = $this->requireProfile($request);
        $validated = $request->validate([
            'profile_image' => ['required', 'image', 'mimes:jpg,jpeg,png,webp', 'max:5120'],
        ]);
        $imagePath = $validated['profile_image']->store('community/profiles', 'local');
        if ($imagePath === false) {
            return response()->json([
                'message' => 'The profile image could not be saved. Please try again.',
            ], 500);
        }
        $oldImage = $profile->profile_image_path;
        $profile->update(['profile_image_path' => $imagePath]);
        if ($oldImage !== null) {
            Storage::disk('local')->delete($oldImage);
        }

        return response()->json([
            'profile' => $this->profileResponse(
                $profile->fresh()->loadCount('posts'),
                includePhoneVisibility: true,
                includePrivateContact: true,
            ),
        ]);
    }

    public function removeProfileImage(Request $request): JsonResponse
    {
        $profile = $this->requireProfile($request);
        $oldImage = $profile->profile_image_path;
        $profile->update(['profile_image_path' => null]);
        if ($oldImage !== null) {
            Storage::disk('local')->delete($oldImage);
        }

        return response()->json([
            'profile' => $this->profileResponse(
                $profile->fresh()->loadCount('posts'),
                includePhoneVisibility: true,
                includePrivateContact: true,
            ),
        ]);
    }

    public function showProfile(Request $request, CommunityProfile $profile): JsonResponse
    {
        $viewer = $this->requireProfile($request);
        $profile->loadCount('posts');
        $includePhoneNumber = $viewer->user_id !== $profile->user_id
            && CommunityContactRequest::query()
                ->where('status', 'accepted')
                ->where(fn ($query) => $query
                    ->where(fn ($pair) => $pair
                        ->where('requester_id', $viewer->user_id)
                        ->where('receiver_id', $profile->user_id))
                    ->orWhere(fn ($pair) => $pair
                        ->where('requester_id', $profile->user_id)
                        ->where('receiver_id', $viewer->user_id)))
                ->exists()
            && ! CommunityMemberBlock::query()
                ->where(fn ($query) => $query
                    ->where(fn ($pair) => $pair
                        ->where('blocker_id', $viewer->user_id)
                        ->where('blocked_id', $profile->user_id))
                    ->orWhere(fn ($pair) => $pair
                        ->where('blocker_id', $profile->user_id)
                        ->where('blocked_id', $viewer->user_id)))
                ->exists();

        return response()->json([
            'profile' => $this->profileResponse(
                $profile,
                includePhoneNumber: $includePhoneNumber,
            ),
        ]);
    }

    public function profilePosts(Request $request, CommunityProfile $profile): JsonResponse
    {
        $viewer = $this->requireProfile($request);
        $posts = $this->postQuery($viewer)
            ->where('community_profile_id', $profile->id)
            ->latest('id')
            ->paginate(15);

        return response()->json([
            'posts' => $posts->through(fn (CommunityPost $post) => $this->postResponse(
                $post,
                null,
            )),
        ]);
    }

    public function preview(): JsonResponse
    {
        $post = $this->postQuery(null)->latest('id')->first();

        return response()->json([
            'post' => $post ? $this->postResponse($post, null) : null,
        ]);
    }

    public function feed(Request $request): JsonResponse
    {
        $profile = $this->requireProfile($request);
        $validated = $request->validate([
            'category' => ['nullable', 'string', 'exists:community_categories,slug'],
            'page' => ['nullable', 'integer', 'min:1'],
        ]);

        $posts = $this->postQuery($profile)
            ->when(
                $validated['category'] ?? null,
                fn (Builder $query, string $slug) => $query->whereHas(
                    'category',
                    fn (Builder $categoryQuery) => $categoryQuery->where('slug', $slug),
                ),
            )
            ->latest('id')
            ->paginate(15);

        return response()->json([
            'posts' => $posts->through(fn (CommunityPost $post) => $this->postResponse(
                $post,
                $profile,
            )),
            'categories' => CommunityCategory::query()->orderBy('id')->get(['id', 'slug', 'name']),
        ]);
    }

    public function createPost(Request $request): JsonResponse
    {
        $profile = $this->requireProfile($request);
        $validated = $request->validate([
            'content' => ['required', 'string', 'max:3000'],
            'category_id' => ['nullable', 'integer', 'exists:community_categories,id'],
            'image' => ['nullable', 'image', 'mimes:jpg,jpeg,png,webp', 'max:10240'],
            'images' => ['nullable', 'array', 'max:5'],
            'images.*' => ['image', 'mimes:jpg,jpeg,png,webp', 'max:10240'],
        ]);
        $content = trim($validated['content']);
        if ($content === '') {
            return response()->json([
                'message' => 'Write something before publishing.',
                'errors' => ['content' => ['Write something before publishing.']],
            ], 422);
        }

        $uploadedImages = array_filter([
            $request->file('image'),
            ...($request->file('images', []) ?? []),
        ]);
        $imagePaths = [];
        foreach ($uploadedImages as $image) {
            $path = $image->store('community/posts', 'local');
            if ($path === false) {
                Storage::disk('local')->delete($imagePaths);

                return response()->json([
                    'message' => 'An image could not be saved. Please try again.',
                ], 500);
            }
            $imagePaths[] = $path;
        }

        try {
            $post = $profile->posts()->create([
                'community_category_id' => $validated['category_id'] ?? null,
                'content' => $content,
                'image_path' => $imagePaths[0] ?? null,
                'image_paths' => $imagePaths === [] ? null : $imagePaths,
                'status' => 'published',
            ]);
        } catch (\Throwable $error) {
            Storage::disk('local')->delete($imagePaths);
            throw $error;
        }
        $post = $this->postQuery($profile)->whereKey($post->id)->firstOrFail();

        return response()->json([
            'post' => $this->postResponse($post, $profile),
        ], 201);
    }

    public function updatePost(Request $request, CommunityPost $post): JsonResponse
    {
        $profile = $this->requireProfile($request);
        abort_unless($post->community_profile_id === $profile->id, 403);
        abort_unless($post->status === 'published', 404);
        $validated = $request->validate([
            'content' => ['sometimes', 'required', 'string', 'max:3000'],
            'category_id' => ['nullable', 'integer', 'exists:community_categories,id'],
            'remove_image' => ['sometimes', 'boolean'],
            'image' => ['nullable', 'image', 'mimes:jpg,jpeg,png,webp', 'max:10240'],
        ]);

        $attributes = [];
        if (array_key_exists('content', $validated)) {
            $content = trim($validated['content']);
            if ($content === '') {
                return response()->json([
                    'message' => 'Write something before publishing.',
                ], 422);
            }
            $attributes['content'] = $content;
        }
        if (array_key_exists('category_id', $validated)) {
            $attributes['community_category_id'] = $validated['category_id'];
        }

        $oldImage = null;
        if ($request->hasFile('image')) {
            $imagePath = $request->file('image')->store('community/posts', 'local');
            if ($imagePath === false) {
                return response()->json([
                    'message' => 'The image could not be saved. Please try again.',
                ], 500);
            }
            $oldImage = $this->postImagePaths($post);
            $attributes['image_path'] = $imagePath;
            $attributes['image_paths'] = [$imagePath];
        } elseif (($validated['remove_image'] ?? false) === true) {
            $oldImage = $this->postImagePaths($post);
            $attributes['image_path'] = null;
            $attributes['image_paths'] = null;
        }

        $post->update($attributes);
        Storage::disk('local')->delete($oldImage ?? []);
        $post = $this->postQuery($profile)->whereKey($post->id)->firstOrFail();

        return response()->json(['post' => $this->postResponse($post, $profile)]);
    }

    public function deletePost(Request $request, CommunityPost $post): JsonResponse
    {
        $profile = $this->requireProfile($request);
        abort_unless($post->community_profile_id === $profile->id, 403);
        $imagePaths = $this->postImagePaths($post);
        DB::transaction(function () use ($post): void {
            $post->comments()->update(['deleted_at' => now(), 'updated_at' => now()]);
            $post->likes()->delete();
            $post->delete();
        });
        Storage::disk('local')->delete($imagePaths);

        return response()->json(['message' => 'Post deleted.']);
    }

    public function setLike(Request $request, CommunityPost $post): JsonResponse
    {
        $profile = $this->requireProfile($request);
        abort_unless($post->status === 'published', 404);
        $liked = DB::transaction(function () use ($profile, $post): bool {
            $lockedPost = CommunityPost::query()
                ->whereKey($post->id)
                ->lockForUpdate()
                ->firstOrFail();
            $like = $lockedPost->likes()
                ->where('community_profile_id', $profile->id)
                ->first();
            if ($like !== null) {
                $like->delete();

                return false;
            }

            $lockedPost->likes()->create(['community_profile_id' => $profile->id]);

            return true;
        });

        return response()->json([
            'liked' => $liked,
            'likes_count' => $post->likes()->count(),
        ]);
    }

    public function comments(Request $request, CommunityPost $post): JsonResponse
    {
        $profile = $this->requireProfile($request);
        abort_unless($post->status === 'published', 404);
        $comments = $post->comments()
            ->whereNull('parent_comment_id')
            ->with([
                'profile',
                'replies' => fn ($query) => $query
                    ->with('profile')
                    ->withCount('replies')
                    ->oldest('id')
                    ->limit(50),
            ])
            ->withCount('replies')
            ->oldest('id')
            ->paginate(30);

        return response()->json([
            'comments' => $comments->through(fn (CommunityComment $comment) => [
                ...$this->commentResponse($comment),
                'replies' => $comment->replies
                    ->map(fn (CommunityComment $reply) => $this->commentResponse($reply))
                    ->values(),
            ]),
            'current_profile_id' => $profile->id,
        ]);
    }

    public function createComment(Request $request, CommunityPost $post): JsonResponse
    {
        $profile = $this->requireProfile($request);
        abort_unless($post->status === 'published', 404);
        $validated = $request->validate([
            'content' => ['required', 'string', 'max:2000'],
            'parent_comment_id' => ['nullable', 'integer'],
        ]);
        $content = trim($validated['content']);
        if ($content === '') {
            return response()->json([
                'message' => 'Write a reply before sending.',
            ], 422);
        }

        $parentId = $validated['parent_comment_id'] ?? null;
        if ($parentId !== null) {
            $parent = $post->comments()
                ->whereKey($parentId)
                ->whereNull('parent_comment_id')
                ->first();
            if ($parent === null) {
                return response()->json([
                    'message' => 'Replies must be attached to a comment on this post.',
                ], 422);
            }
        }

        $comment = $post->comments()->create([
            'community_profile_id' => $profile->id,
            'parent_comment_id' => $parentId,
            'content' => $content,
        ])->load('profile');

        return response()->json([
            'comment' => $this->commentResponse($comment),
        ], 201);
    }

    public function deleteComment(
        Request $request,
        CommunityPost $post,
        CommunityComment $comment,
    ): JsonResponse {
        $profile = $this->requireProfile($request);
        abort_unless($comment->community_post_id === $post->id, 404);
        abort_unless($comment->community_profile_id === $profile->id, 403);
        $comment->replies()->update(['deleted_at' => now(), 'updated_at' => now()]);
        $comment->delete();

        return response()->json(['message' => 'Comment deleted.']);
    }

    public function report(Request $request): JsonResponse
    {
        $profile = $this->requireProfile($request);
        $validated = $request->validate([
            'target_type' => ['required', Rule::in(['post', 'comment'])],
            'target_id' => ['required', 'integer', 'min:1'],
            'reason' => ['required', Rule::in(self::REPORT_REASONS)],
            'details' => ['nullable', 'string', 'max:500'],
        ]);
        $target = $validated['target_type'] === 'post'
            ? CommunityPost::query()->where('status', 'published')->find($validated['target_id'])
            : CommunityComment::query()->find($validated['target_id']);
        if ($target === null ||
            ($target instanceof CommunityComment && $target->post?->status !== 'published')) {
            return response()->json(['message' => 'This content is unavailable.'], 404);
        }
        if ($target->community_profile_id === $profile->id) {
            return response()->json(['message' => 'You cannot report your own content.'], 422);
        }
        if (CommunityReport::query()
            ->where('reporter_profile_id', $profile->id)
            ->where('target_type', $validated['target_type'])
            ->where('target_id', $target->id)
            ->exists()) {
            return response()->json(['message' => 'You have already reported this content.'], 409);
        }

        CommunityReport::query()->create([
            'reporter_profile_id' => $profile->id,
            'target_type' => $validated['target_type'],
            'target_id' => $target->id,
            'reason' => $validated['reason'],
            'details' => isset($validated['details'])
                ? trim($validated['details'])
                : null,
        ]);

        return response()->json(['message' => 'Report submitted for review.'], 201);
    }

    public function reports(Request $request): JsonResponse
    {
        $this->authorizeModerator($request);
        $reports = CommunityReport::query()
            ->with('reporter')
            ->latest('id')
            ->paginate(30)
            ->through(function (CommunityReport $report): array {
                $target = $report->target_type === 'post'
                    ? CommunityPost::withTrashed()->find($report->target_id)
                    : CommunityComment::withTrashed()->find($report->target_id);

                return [
                    'id' => $report->id,
                    'target_type' => $report->target_type,
                    'target_id' => $report->target_id,
                    'content' => $target?->content,
                    'reason' => $report->reason,
                    'details' => $report->details,
                    'status' => $report->status,
                    'reporter' => $report->reporter?->display_name,
                    'created_at' => $report->created_at?->toIso8601String(),
                ];
            });

        return response()->json(['reports' => $reports]);
    }

    public function reviewReport(Request $request, CommunityReport $report): JsonResponse
    {
        $this->authorizeModerator($request);
        $validated = $request->validate([
            'action' => ['required', Rule::in(['dismiss', 'review', 'hide'])],
        ]);
        if ($report->status !== 'open') {
            return response()->json(['message' => 'This report has already been reviewed.'], 409);
        }

        if ($validated['action'] === 'hide') {
            if ($report->target_type === 'post') {
                CommunityPost::query()->whereKey($report->target_id)->update([
                    'status' => 'hidden',
                    'updated_at' => now(),
                ]);
            } else {
                $comment = CommunityComment::query()->find($report->target_id);
                $comment?->delete();
            }
        }
        $report->update([
            'status' => $validated['action'] === 'dismiss' ? 'dismissed' : 'reviewed',
            'reviewed_by_user_id' => $request->user()->id,
            'reviewed_at' => now(),
        ]);

        return response()->json(['message' => 'Report reviewed.']);
    }

    public function profileImage(CommunityProfile $profile): BinaryFileResponse
    {
        abort_if($profile->profile_image_path === null, 404);

        return $this->mediaResponse($profile->profile_image_path);
    }

    public function postImage(CommunityPost $post): BinaryFileResponse
    {
        abort_unless($post->status === 'published' && $post->image_path !== null, 404);

        return $this->mediaResponse($post->image_path);
    }

    public function postImageAtIndex(
        CommunityPost $post,
        int $image,
    ): BinaryFileResponse {
        $imagePaths = $this->postImagePaths($post);
        abort_unless($post->status === 'published' && isset($imagePaths[$image - 1]), 404);

        return $this->mediaResponse($imagePaths[$image - 1]);
    }

    private function postQuery(?CommunityProfile $profile): Builder
    {
        return CommunityPost::query()
            ->where('status', 'published')
            ->with(['profile', 'category'])
            ->withCount(['likes', 'comments'])
            ->when(
                $profile,
                fn (Builder $query, CommunityProfile $current) => $query->withExists([
                    'likes as liked_by_me' => fn (Builder $likes) => $likes
                        ->where('community_profile_id', $current->id),
                ]),
            );
    }

    private function postResponse(
        CommunityPost $post,
        ?CommunityProfile $viewer,
    ): array {
        $author = $post->profile;
        $imagePaths = $this->postImagePaths($post);

        return [
            'id' => $post->id,
            'content' => $post->content,
            'image_url' => $imagePaths === []
                ? null
                : url("/api/community/media/posts/{$post->id}"),
            'image_urls' => array_map(
                fn (int $index): string => url(
                    "/api/community/media/posts/{$post->id}/".($index + 1),
                ),
                array_keys($imagePaths),
            ),
            'category' => $post->category ? [
                'id' => $post->category->id,
                'slug' => $post->category->slug,
                'name' => $post->category->name,
            ] : null,
            'author' => $author ? $this->profileResponse($author) : null,
            'likes_count' => (int) ($post->likes_count ?? 0),
            'comments_count' => (int) ($post->comments_count ?? 0),
            'liked_by_me' => $viewer !== null && (bool) ($post->liked_by_me ?? false),
            'created_at' => $post->created_at?->toIso8601String(),
            'updated_at' => $post->updated_at?->toIso8601String(),
        ];
    }

    /**
     * @return list<string>
     */
    private function postImagePaths(CommunityPost $post): array
    {
        $paths = $post->image_paths;
        if (is_array($paths) && $paths !== []) {
            return array_values(array_filter($paths, 'is_string'));
        }

        return $post->image_path === null ? [] : [$post->image_path];
    }

    private function profileResponse(
        CommunityProfile $profile,
        bool $includePhoneVisibility = false,
        bool $includePhoneNumber = false,
        bool $includePrivateContact = false,
    ): array {
        $response = [
            'id' => $profile->id,
            'user_id' => $profile->user_id,
            'display_name' => $profile->display_name,
            'profession' => $profile->profession === 'Other'
                ? $profile->other_profession
                : ($profile->profession ?? 'Community member'),
            'profession_type' => $profile->profession,
            'other_profession' => $profile->other_profession,
            'location' => $profile->location,
            'bio' => $profile->bio,
            'profile_image_url' => $profile->profile_image_path === null
                ? null
                : url("/api/community/media/profiles/{$profile->id}"),
            'posts_count' => (int) ($profile->posts_count ?? 0),
            'latitude' => $profile->latitude,
            'longitude' => $profile->longitude,
            'trade' => $profile->trade,
            'skills' => $profile->skills ?? [],
            'experience_years' => $profile->experience_years,
            'preferred_location' => $profile->preferred_location,
            'preferred_latitude' => $profile->preferred_latitude,
            'preferred_longitude' => $profile->preferred_longitude,
            'preferred_categories' => $profile->preferred_categories ?? [],
            'preferred_radius_km' => $profile->preferred_radius_km ?? 25,
            'job_notifications_enabled' => (bool) $profile->job_notifications_enabled,
        ];
        if ($includePhoneVisibility) {
            $response['is_phone_visible'] = (bool) $profile->is_phone_visible;
        }
        if ($includePhoneNumber) {
            $phoneNumber = $profile->user?->phone_number;
            if (is_string($phoneNumber) && $phoneNumber !== '') {
                $response['phone_number'] = $phoneNumber;
            }
        }
        if ($includePrivateContact) {
            $user = $profile->user;
            $response['email'] = $user?->email;
            $response['phone_number'] = $user?->phone_number;
        }

        return $response;
    }

    private function commentResponse(CommunityComment $comment): array
    {
        $profile = $comment->profile;

        return [
            'id' => $comment->id,
            'post_id' => $comment->community_post_id,
            'parent_comment_id' => $comment->parent_comment_id,
            'content' => $comment->content,
            'author' => $profile ? $this->profileResponse($profile) : null,
            'replies_count' => (int) ($comment->replies_count ?? $comment->replies()->count()),
            'created_at' => $comment->created_at?->toIso8601String(),
        ];
    }

    private function requireProfile(Request $request): CommunityProfile
    {
        $profile = CommunityProfile::query()
            ->where('user_id', $request->user()->id)
            ->first();
        abort_if($profile === null, 409, 'Complete Community registration first.');

        return $profile;
    }

    private function authorizeModerator(Request $request): void
    {
        $moderatorIds = config('community.moderator_user_ids', []);
        abort_unless(in_array((int) $request->user()->id, $moderatorIds, true), 403);
    }

    private function mediaResponse(string $path): BinaryFileResponse
    {
        $disk = Storage::disk('local');
        abort_unless($disk->exists($path), 404);

        return response()->file($disk->path($path), [
            'Cache-Control' => 'private, max-age=3600',
            'X-Content-Type-Options' => 'nosniff',
        ]);
    }
}
