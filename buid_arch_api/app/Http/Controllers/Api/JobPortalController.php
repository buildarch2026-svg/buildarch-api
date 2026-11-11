<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Jobs\MatchConstructionJobSeekers;
use App\Models\CommunityProfile;
use App\Models\ConstructionJob;
use App\Models\EmployerProfile;
use App\Models\JobApplication;
use App\Models\JobNotification;
use App\Models\JobPortalCategory;
use App\Models\JobReport;
use App\Models\JobSeekerProfile;
use App\Models\SavedConstructionJob;
use App\Models\User;
use App\Notifications\JobPortalNotification;
use App\Services\FirebasePushService;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\QueryException;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Pagination\LengthAwarePaginator;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;
use Symfony\Component\HttpFoundation\BinaryFileResponse;

class JobPortalController extends Controller
{
    private const EMPLOYER_TYPES = [
        'Construction Company',
        'Contractor',
        'Architecture Firm',
        'Interior Design Firm',
        'Recruitment Agency',
        'Individual Employer',
        'Other',
    ];

    private const EMPLOYMENT_TYPES = [
        'Full Time',
        'Part Time',
        'Contract',
        'Temporary',
        'Daily Wage',
    ];

    private const SALARY_TYPES = ['Hourly', 'Daily', 'Weekly', 'Monthly', 'Fixed', 'Negotiable'];

    private const APPLICATION_STATUSES = [
        'applied',
        'under_review',
        'shortlisted',
        'interview_scheduled',
        'selected',
        'rejected',
        'withdrawn',
    ];

    public function __construct(
        private readonly FirebasePushService $firebasePushService,
    ) {}

    public function categories(): JsonResponse
    {
        return response()->json([
            'categories' => JobPortalCategory::query()
                ->where('is_active', true)
                ->orderBy('name')
                ->get(['id', 'slug', 'name']),
        ]);
    }

    public function dashboard(Request $request): JsonResponse
    {
        $user = $request->user();
        $profile = CommunityProfile::query()->where('user_id', $user->id)->first();
        $jobs = $this->publishedJobs()
            ->with([
                'category:id,slug,name',
                'employer:id,user_id,company_name,company_logo_path,location_name',
                'poster.communityProfile',
            ])
            ->latest('construction_jobs.created_at')
            ->limit(5)
            ->get();

        return response()->json([
            'jobs' => $jobs->map(fn (ConstructionJob $job) => $this->jobResponse(
                $job,
                $user,
            )),
            'community_profile' => $profile ? $this->communityJobProfileResponse($profile) : null,
            'my_jobs_count' => ConstructionJob::query()
                ->where('employer_id', $user->id)
                ->whereIn('status', ['published', 'paused'])
                ->count(),
            'my_applications_count' => JobApplication::query()
                ->where('applicant_id', $user->id)->count(),
            'saved_jobs_count' => SavedConstructionJob::query()
                ->where('user_id', $user->id)->count(),
        ]);
    }

    public function employerProfile(Request $request): JsonResponse
    {
        $profile = EmployerProfile::query()->where('user_id', $request->user()->id)->first();

        return response()->json([
            'profile' => $profile ? $this->employerResponse($profile) : null,
        ]);
    }

    public function saveEmployerProfile(Request $request): JsonResponse
    {
        $this->requireCommunityMember($request);
        $validated = $request->validate([
            'company_name' => ['required', 'string', 'max:160'],
            'employer_name' => ['required', 'string', 'max:120'],
            'email' => ['required', 'email', 'max:254'],
            'phone_number' => ['required', 'string', 'max:40'],
            'company_description' => ['required', 'string', 'max:10000'],
            'website' => ['nullable', 'url', 'max:2048'],
            'location_name' => ['required', 'string', 'max:255'],
            'latitude' => ['nullable', 'numeric', 'between:-90,90'],
            'longitude' => ['nullable', 'numeric', 'between:-180,180'],
            'employer_type' => ['required', Rule::in(self::EMPLOYER_TYPES)],
            'company_logo' => ['nullable', 'image', 'mimes:jpg,jpeg,png,webp', 'max:5120'],
        ]);
        if (($request->filled('latitude')) !== ($request->filled('longitude'))) {
            return $this->validationError('latitude', 'Provide both coordinates or neither.');
        }

        $user = $request->user();
        $profile = EmployerProfile::query()->firstOrNew(['user_id' => $user->id]);
        $path = $request->file('company_logo')?->store('job-portal/employers', 'local');
        if ($request->hasFile('company_logo') && $path === false) {
            return response()->json(['message' => 'The company logo could not be saved.'], 500);
        }
        unset($validated['company_logo']);
        $profile->fill([
            ...$validated,
            'company_logo_path' => $path ?? $profile->company_logo_path,
        ])->save();

        return response()->json(['profile' => $this->employerResponse($profile->fresh())], $profile->wasRecentlyCreated ? 201 : 200);
    }

    public function companyLogo(Request $request): BinaryFileResponse
    {
        $profile = EmployerProfile::query()
            ->where('id', $request->route('profile'))
            ->firstOrFail();
        abort_if($profile->company_logo_path === null, 404);

        return $this->privateDownload($profile->company_logo_path);
    }

    public function seekerImage(Request $request): BinaryFileResponse
    {
        $profile = JobSeekerProfile::query()
            ->where('id', $request->route('profile'))
            ->firstOrFail();
        abort_if($profile->profile_image_path === null, 404);

        return $this->privateDownload($profile->profile_image_path);
    }

    public function seekerProfile(Request $request): JsonResponse
    {
        $profile = JobSeekerProfile::query()->where('user_id', $request->user()->id)->first();

        return response()->json([
            'profile' => $profile ? $this->seekerResponse($profile) : null,
        ]);
    }

    public function saveSeekerProfile(Request $request): JsonResponse
    {
        $this->requireCommunityMember($request);
        foreach (['preferred_categories', 'preferred_employment_types'] as $field) {
            if ($request->input($field) === '[]') {
                $request->merge([$field => []]);
            }
        }
        $validated = $request->validate([
            'full_name' => ['required', 'string', 'max:120'],
            'email' => ['required', 'email', 'max:254'],
            'phone_number' => ['required', 'string', 'max:40'],
            'current_location' => ['nullable', 'string', 'max:255'],
            'current_latitude' => ['nullable', 'numeric', 'between:-90,90'],
            'current_longitude' => ['nullable', 'numeric', 'between:-180,180'],
            'preferred_location' => ['nullable', 'string', 'max:255'],
            'preferred_latitude' => ['nullable', 'numeric', 'between:-90,90'],
            'preferred_longitude' => ['nullable', 'numeric', 'between:-180,180'],
            'preferred_categories' => ['nullable', 'array', 'max:20'],
            'preferred_categories.*' => [
                'integer',
                Rule::exists('job_portal_categories', 'id')->where('is_active', true),
            ],
            'preferred_employment_types' => ['nullable', 'array', 'max:5'],
            'preferred_employment_types.*' => ['string', Rule::in(self::EMPLOYMENT_TYPES)],
            'preferred_radius_km' => ['sometimes', 'integer', Rule::in([5, 10, 25, 50, 100])],
            'expected_salary' => ['nullable', 'numeric', 'min:0', 'max:9999999999.99'],
            'available_from' => ['nullable', 'date'],
            'notifications_enabled' => ['sometimes', 'boolean'],
            'profession' => ['nullable', 'string', 'max:120'],
            'skills' => ['nullable', 'array', 'max:50'],
            'skills.*' => ['string', 'max:80'],
            'experience_years' => ['nullable', 'integer', 'between:0,80'],
            'education' => ['nullable', 'string', 'max:255'],
            'bio' => ['nullable', 'string', 'max:10000'],
            'profile_image' => ['nullable', 'image', 'mimes:jpg,jpeg,png,webp', 'max:5120'],
            'resume' => ['nullable', 'file', 'mimes:pdf,doc,docx', 'max:10240'],
        ]);
        foreach ([
            ['current_latitude', 'current_longitude'],
            ['preferred_latitude', 'preferred_longitude'],
        ] as [$latitude, $longitude]) {
            if ($request->filled($latitude) !== $request->filled($longitude)) {
                return $this->validationError($latitude, 'Provide both coordinates or neither.');
            }
        }
        if ($request->boolean('notifications_enabled')) {
            if (($validated['preferred_categories'] ?? $profile->preferred_categories ?? []) === []) {
                return $this->validationError(
                    'preferred_categories',
                    'Choose at least one preferred job category for nearby alerts.',
                );
            }
            if (($validated['preferred_latitude'] ?? $profile->preferred_latitude) === null
                || ($validated['preferred_longitude'] ?? $profile->preferred_longitude) === null) {
                return $this->validationError(
                    'preferred_location',
                    'Choose a preferred location to enable nearby alerts.',
                );
            }
        }

        $profile = JobSeekerProfile::query()->firstOrNew([
            'user_id' => $request->user()->id,
        ]);
        $attributes = $validated;
        unset($attributes['profile_image'], $attributes['resume']);
        if ($request->hasFile('profile_image')) {
            $path = $request->file('profile_image')->store('job-portal/seeker-images', 'local');
            if ($path === false) {
                return response()->json(['message' => 'The profile image could not be saved.'], 500);
            }
            $this->deleteStoredFile($profile->profile_image_path);
            $attributes['profile_image_path'] = $path;
        }
        if ($request->hasFile('resume')) {
            $resume = $request->file('resume');
            $path = $resume->store('job-portal/resumes', 'local');
            if ($path === false) {
                return response()->json(['message' => 'The resume could not be saved.'], 500);
            }
            $this->deleteStoredFile($profile->resume_path);
            $attributes['resume_path'] = $path;
            $attributes['resume_name'] = $resume->getClientOriginalName();
        }
        $profile->fill($attributes)->save();

        return response()->json(['profile' => $this->seekerResponse($profile->fresh())], $profile->wasRecentlyCreated ? 201 : 200);
    }

    public function uploadResume(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'resume' => ['required', 'file', 'mimes:pdf,doc,docx', 'max:10240'],
        ]);
        $profile = $this->requireSeeker($request);
        $file = $validated['resume'];
        $path = $file->store('job-portal/resumes', 'local');
        if ($path === false) {
            return response()->json(['message' => 'The resume could not be saved.'], 500);
        }
        $this->deleteStoredFile($profile->resume_path);
        $profile->update([
            'resume_path' => $path,
            'resume_name' => $file->getClientOriginalName(),
        ]);

        return response()->json(['profile' => $this->seekerResponse($profile->fresh())]);
    }

    public function jobs(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'q' => ['nullable', 'string', 'max:120'],
            'category' => ['nullable', 'string', 'max:100'],
            'employment_type' => ['nullable', Rule::in(self::EMPLOYMENT_TYPES)],
            'min_salary' => ['nullable', 'numeric', 'min:0'],
            'max_salary' => ['nullable', 'numeric', 'min:0'],
            'experience' => ['nullable', 'string', 'max:120'],
            'location' => ['nullable', 'string', 'max:160'],
            'latitude' => ['nullable', 'numeric', 'between:-90,90'],
            'longitude' => ['nullable', 'numeric', 'between:-180,180'],
            'distance_km' => ['nullable', Rule::in([5, 10, 25, 50, 100])],
            'sort' => ['nullable', Rule::in(['latest', 'nearest', 'salary_desc'])],
            'page' => ['nullable', 'integer', 'min:1'],
        ]);
        if ($request->filled('latitude') !== $request->filled('longitude')) {
            return $this->validationError('latitude', 'Provide both coordinates or neither.');
        }

        if (isset($validated['distance_km']) && ! isset($validated['latitude'])) {
            return $this->validationError('latitude', 'Choose a location to filter by distance.');
        }
        if (($validated['sort'] ?? null) === 'nearest' && ! isset($validated['latitude'])) {
            return $this->validationError('latitude', 'Choose a location to sort by distance.');
        }
        if (isset($validated['min_salary'], $validated['max_salary']) &&
            $validated['min_salary'] > $validated['max_salary']) {
            return $this->validationError('max_salary', 'Maximum salary must be at least the minimum salary.');
        }

        $query = $this->publishedJobs()
            ->with([
                'category:id,slug,name',
                'employer:id,company_name,company_logo_path,location_name',
                'poster.communityProfile',
            ]);
        if (! empty($validated['q'])) {
            $term = '%'.mb_strtolower($validated['q']).'%';
            $query->where(function (Builder $builder) use ($term) {
                $builder->whereRaw('LOWER(construction_jobs.title) LIKE ?', [$term])
                    ->orWhereRaw('LOWER(construction_jobs.description) LIKE ?', [$term])
                    ->orWhereRaw('LOWER(CAST(construction_jobs.skills AS CHAR)) LIKE ?', [$term])
                    ->orWhereHas('employer', fn (Builder $employer) => $employer
                        ->whereRaw('LOWER(company_name) LIKE ?', [$term]))
                    ->orWhereHas('poster.communityProfile', fn (Builder $profile) => $profile
                        ->whereRaw('LOWER(display_name) LIKE ?', [$term]));
            });
        }
        if (! empty($validated['category'])) {
            $query->whereHas('category', fn (Builder $builder) => $builder
                ->where('slug', $validated['category'])
                ->orWhere('id', $validated['category']));
        }
        if (! empty($validated['employment_type'])) {
            $query->where('employment_type', $validated['employment_type']);
        }
        if (isset($validated['min_salary'])) {
            $query->where(function (Builder $builder) use ($validated) {
                $builder->whereNull('max_salary')
                    ->orWhere('max_salary', '>=', $validated['min_salary']);
            });
        }
        if (isset($validated['max_salary'])) {
            $query->where(function (Builder $builder) use ($validated) {
                $builder->whereNull('min_salary')
                    ->orWhere('min_salary', '<=', $validated['max_salary']);
            });
        }
        if (! empty($validated['experience'])) {
            $query->where('experience_required', 'like', '%'.$validated['experience'].'%');
        }
        if (! empty($validated['location'])) {
            $term = '%'.mb_strtolower($validated['location']).'%';
            $query->where(function (Builder $builder) use ($term) {
                $builder->whereRaw('LOWER(construction_jobs.location_name) LIKE ?', [$term])
                    ->orWhereHas('employer', fn (Builder $employer) => $employer
                        ->whereRaw('LOWER(location_name) LIKE ?', [$term]))
                    ->orWhereHas('poster.communityProfile', fn (Builder $profile) => $profile
                        ->whereRaw('LOWER(location) LIKE ?', [$term]));
            });
        }

        $latitude = $validated['latitude'] ?? null;
        $longitude = $validated['longitude'] ?? null;
        $sort = $validated['sort'] ?? ($latitude === null ? 'latest' : 'nearest');
        $calculateDistanceInPhp = false;
        if ($latitude !== null && $longitude !== null) {
            $radius = isset($validated['distance_km'])
                ? (float) $validated['distance_km']
                : null;
            if ($radius !== null) {
                $latDelta = $radius / 110.574;
                $lonDelta = $radius / max(111.320 * cos(deg2rad($latitude)), 0.01);
                $query->whereBetween('latitude', [
                    max(-90, $latitude - $latDelta),
                    min(90, $latitude + $latDelta),
                ])->whereBetween('longitude', [
                    max(-180, $longitude - $lonDelta),
                    min(180, $longitude + $lonDelta),
                ]);
            }
            if (DB::connection()->getDriverName() === 'sqlite') {
                $calculateDistanceInPhp = true;
                $query->select('construction_jobs.*');
            } else {
                $distanceExpression = '(6371 * 2 * ASIN(SQRT('
                    .'POWER(SIN(RADIANS(latitude - ?) / 2), 2) + '
                    .'COS(RADIANS(?)) * COS(RADIANS(latitude)) * '
                    .'POWER(SIN(RADIANS(longitude - ?) / 2), 2)'
                    .'))) ';
                $query->select('construction_jobs.*')
                    ->selectRaw("$distanceExpression AS distance_km", [
                        $latitude,
                        $latitude,
                        $longitude,
                    ]);
                if ($radius !== null) {
                    $query->having('distance_km', '<=', $radius);
                }
                if ($sort === 'nearest') {
                    $query->orderBy('distance_km');
                } elseif ($sort === 'salary_desc') {
                    $query->orderByRaw('COALESCE(max_salary, min_salary) IS NULL')
                        ->orderByRaw('COALESCE(max_salary, min_salary) DESC');
                }
                $query->orderByDesc('construction_jobs.created_at');
            }
        } else {
            if ($sort === 'salary_desc') {
                $query->orderByRaw('COALESCE(max_salary, min_salary) IS NULL')
                    ->orderByRaw('COALESCE(max_salary, min_salary) DESC');
            }
            $query->latest('construction_jobs.created_at');
        }

        $viewer = $request->user();

        if ($calculateDistanceInPhp) {
            $items = $query->get()
                ->map(function (ConstructionJob $job) use ($latitude, $longitude) {
                    $job->setAttribute('distance_km', $this->distanceInKilometers(
                        $latitude,
                        $longitude,
                        $job->latitude,
                        $job->longitude,
                    ));

                    return $job;
                })
                ->filter(fn (ConstructionJob $job) => ! isset($radius) ||
                    $job->distance_km <= $radius)
                ->sortBy($sort === 'nearest'
                    ? [['distance_km', 'asc'], ['created_at', 'desc']]
                    : ($sort === 'salary_desc'
                        ? [['max_salary', 'desc'], ['created_at', 'desc']]
                        : [['created_at', 'desc']]))
                ->values();
            $pageNumber = max(1, (int) $request->input('page', 1));
            $jobs = new LengthAwarePaginator(
                $items->forPage($pageNumber, 20)->values(),
                $items->count(),
                20,
                $pageNumber,
                ['path' => $request->url(), 'query' => $request->query()],
            );
        } else {
            $jobs = $query->paginate(20);
        }

        return response()->json([
            'jobs' => $jobs->through(fn (ConstructionJob $job) => $this->jobResponse(
                $job,
                $viewer,
            )),
            'categories' => JobPortalCategory::query()
                ->where('is_active', true)
                ->orderBy('name')
                ->get(['id', 'slug', 'name']),
        ]);
    }

    public function jobNotifications(Request $request): JsonResponse
    {
        $notifications = JobNotification::query()
            ->where('user_id', $request->user()->id)
            ->with(['job.category:id,slug,name'])
            ->latest()
            ->paginate(20)
            ->through(fn (JobNotification $notification) => [
                'id' => $notification->id,
                'notification_type' => $notification->notification_type,
                'sent_at' => $notification->sent_at?->toIso8601String(),
                'read_at' => $notification->read_at?->toIso8601String(),
                'job' => $notification->job
                    ? $this->jobResponse($notification->job, null)
                    : null,
            ]);

        return response()->json(['notifications' => $notifications]);
    }

    public function markJobNotificationRead(
        Request $request,
        JobNotification $notification,
    ): JsonResponse {
        abort_unless($notification->user_id === $request->user()->id, 404);
        $notification->update(['read_at' => $notification->read_at ?? now()]);

        return response()->json([
            'id' => $notification->id,
            'read_at' => $notification->read_at?->toIso8601String(),
        ]);
    }

    public function showJob(Request $request, ConstructionJob $job): JsonResponse
    {
        $isOwner = $this->jobOwnerId($job) === (int) $request->user()->id;
        $hasApplication = JobApplication::query()
            ->where('construction_job_id', $job->id)
            ->where('applicant_id', $request->user()->id)
            ->exists();
        abort_unless($job->status === 'published' || $isOwner || $hasApplication, 404);
        $job->load([
            'category:id,slug,name',
            'employer:id,user_id,company_name,company_logo_path,location_name,company_description,website,employer_type,phone_number,email',
            'employer.user.communityProfile',
            'poster.communityProfile',
        ]);

        return response()->json(['job' => $this->jobResponse($job, $request->user(), true)]);
    }

    public function myJobs(Request $request): JsonResponse
    {
        $this->requireCommunityMember($request);
        $jobs = ConstructionJob::query()
            ->where(function (Builder $builder) use ($request): void {
                $builder->where('employer_id', $request->user()->id)
                    ->orWhereHas('employer', fn (Builder $employer) => $employer
                        ->where('user_id', $request->user()->id));
            })
            ->with(['category:id,slug,name'])
            ->with('poster.communityProfile')
            ->withCount('applications')
            ->latest()
            ->paginate(20)
            ->through(fn (ConstructionJob $job) => $this->jobResponse($job, $request->user(), true));

        return response()->json(['jobs' => $jobs]);
    }

    public function createJob(Request $request): JsonResponse
    {
        $this->requireCommunityMember($request);
        $validated = $this->validateJob($request);
        $job = ConstructionJob::query()->create([
            'employer_id' => $request->user()->id,
            ...$validated,
            'job_portal_category_id' => $validated['category_id'],
            'status' => $validated['status'] ?? 'draft',
        ]);
        if ($job->status === 'published') {
            MatchConstructionJobSeekers::dispatch($job->id)->afterCommit();
        }
        $job->load([
            'category:id,slug,name',
            'employer:id,user_id,company_name,company_logo_path,location_name,company_description,website,employer_type,phone_number,email',
            'employer.user.communityProfile',
            'poster.communityProfile',
        ]);

        return response()->json(['job' => $this->jobResponse($job, $request->user(), true)], 201);
    }

    public function updateJob(Request $request, ConstructionJob $job): JsonResponse
    {
        $this->requireCommunityMember($request);
        abort_unless($this->jobOwnerId($job) === (int) $request->user()->id, 403);
        $validated = $this->validateJob($request, true, $job);
        if (isset($validated['category_id'])) {
            $validated['job_portal_category_id'] = $validated['category_id'];
            unset($validated['category_id']);
        }
        $job->update($validated);
        if ($job->wasChanged('status') && $job->status === 'published') {
            MatchConstructionJobSeekers::dispatch($job->id)->afterCommit();
        }
        $job->load([
            'category:id,slug,name',
            'employer:id,user_id,company_name,company_logo_path,location_name,company_description,website,employer_type,phone_number,email',
            'employer.user.communityProfile',
            'poster.communityProfile',
        ]);

        return response()->json(['job' => $this->jobResponse($job, $request->user(), true)]);
    }

    public function updateJobStatus(Request $request, ConstructionJob $job): JsonResponse
    {
        $this->requireCommunityMember($request);
        abort_unless($this->jobOwnerId($job) === (int) $request->user()->id, 403);
        $validated = $request->validate([
            'status' => ['required', Rule::in(['published', 'paused', 'closed', 'filled'])],
        ]);
        $job->update(['status' => $validated['status']]);
        if ($job->wasChanged('status') && $job->status === 'published') {
            MatchConstructionJobSeekers::dispatch($job->id)->afterCommit();
        }

        return response()->json(['job' => ['id' => $job->id, 'status' => $job->status]]);
    }

    public function deleteJob(Request $request, ConstructionJob $job): JsonResponse
    {
        $this->requireCommunityMember($request);
        abort_unless($this->jobOwnerId($job) === (int) $request->user()->id, 403);
        $job->delete();

        return response()->json(['message' => 'The job posting was removed.']);
    }

    public function saveJob(Request $request, ConstructionJob $job): JsonResponse
    {
        abort_unless($job->status === 'published', 404);
        $this->requireCommunityMember($request);
        SavedConstructionJob::query()->firstOrCreate([
            'construction_job_id' => $job->id,
            'user_id' => $request->user()->id,
        ]);

        return response()->json(['saved' => true]);
    }

    public function unsaveJob(Request $request, ConstructionJob $job): JsonResponse
    {
        $this->requireCommunityMember($request);
        SavedConstructionJob::query()
            ->where('construction_job_id', $job->id)
            ->where('user_id', $request->user()->id)
            ->delete();

        return response()->json(['saved' => false]);
    }

    public function savedJobs(Request $request): JsonResponse
    {
        $this->requireCommunityMember($request);
        $jobs = $this->publishedJobs()
            ->whereHas('savedBy', fn (Builder $builder) => $builder
                ->where('user_id', $request->user()->id))
            ->with([
                'category:id,slug,name',
                'employer:id,company_name,company_logo_path,location_name',
                'poster.communityProfile',
            ])
            ->latest('construction_jobs.created_at')
            ->paginate(20)
            ->through(fn (ConstructionJob $job) => $this->jobResponse($job, $request->user()));

        return response()->json(['jobs' => $jobs]);
    }

    public function apply(Request $request, ConstructionJob $job): JsonResponse
    {
        $profile = $this->requireCommunityMember($request);
        abort_unless($job->status === 'published', 409, 'This vacancy is not accepting applications.');
        abort_if($job->application_deadline?->isPast(), 409, 'The application deadline has passed.');
        abort_if(
            $this->jobOwnerId($job) === (int) $request->user()->id,
            403,
            'You cannot apply to your own job.',
        );
        abort_if(
            JobApplication::query()
                ->where('construction_job_id', $job->id)
                ->where('applicant_id', $request->user()->id)
                ->exists(),
            409,
            'You have already applied for this vacancy.',
        );
        $validated = $request->validate([
            'cover_letter' => ['nullable', 'string', 'max:10000'],
            'resume' => ['nullable', 'file', 'mimes:pdf,doc,docx', 'max:10240'],
        ]);
        $resumePath = null;
        $resumeName = null;
        if ($request->hasFile('resume')) {
            $file = $validated['resume'];
            $resumePath = $file->store('job-portal/application-resumes', 'local');
            if ($resumePath === false) {
                return response()->json(['message' => 'The resume could not be saved.'], 500);
            }
            $resumeName = $file->getClientOriginalName();
        }
        try {
            $application = DB::transaction(fn () => JobApplication::query()->create([
                'construction_job_id' => $job->id,
                'applicant_id' => $request->user()->id,
                'resume_path' => $resumePath,
                'resume_name' => $resumeName,
                'cover_letter' => $validated['cover_letter'] ?? null,
                'status' => 'pending',
                'applied_at' => now(),
            ]));
        } catch (QueryException $exception) {
            $this->deleteStoredFile($resumePath);
            if ($exception->getCode() === '23000') {
                abort(409, 'You have already applied for this vacancy.');
            }
            throw $exception;
        }
        $job->loadMissing('employer.user');
        $this->notify(
            $job->poster,
            event: 'job_application_received',
            title: 'New job application',
            message: "{$profile->display_name} applied for {$job->title}.",
            job: $job,
            application: $application,
        );

        return response()->json([
            'application' => $this->applicationResponse($application->load('job.category', 'job.employer')),
        ], 201);
    }

    public function myApplications(Request $request): JsonResponse
    {
        $this->requireCommunityMember($request);
        $applications = $request->user()->jobApplications()
            ->with(['job.category:id,slug,name', 'job.employer:id,company_name,location_name,company_logo_path'])
            ->latest('applied_at')
            ->paginate(20)
            ->through(fn (JobApplication $application) => $this->applicationResponse($application));

        return response()->json(['applications' => $applications]);
    }

    public function employerApplications(Request $request, ConstructionJob $job): JsonResponse
    {
        $this->requireCommunityMember($request);
        abort_unless($this->jobOwnerId($job) === (int) $request->user()->id, 403);
        $applications = $job->applications()
            ->with(['applicant.communityProfile'])
            ->latest('applied_at')
            ->paginate(20)
            ->through(fn (JobApplication $application) => $this->employerApplicationResponse($application));

        return response()->json(['applications' => $applications]);
    }

    public function updateApplication(Request $request, JobApplication $application): JsonResponse
    {
        $this->requireCommunityMember($request);
        $application->loadMissing('job.employer');
        abort_unless(
            $this->jobOwnerId($application->job) === (int) $request->user()->id,
            403,
        );
        $validated = $request->validate([
            'status' => ['required', Rule::in([
                'pending',
                'accepted',
                'viewed',
                'contacted',
                'under_review',
                'shortlisted',
                'interview_scheduled',
                'selected',
                'rejected',
            ])],
            'interview_at' => ['nullable', 'date', 'after:now'],
            'employer_note' => ['nullable', 'string', 'max:5000'],
        ]);
        if ($validated['status'] === 'interview_scheduled' && empty($validated['interview_at'])) {
            return $this->validationError('interview_at', 'Set the interview date and time.');
        }
        $application->update([
            'status' => $validated['status'],
            'interview_at' => $validated['status'] === 'interview_scheduled'
                ? $validated['interview_at']
                : null,
            'employer_note' => $validated['employer_note'] ?? $application->employer_note,
        ]);
        $application->load('job');
        $applicant = $application->applicant()->firstOrFail();
        $labels = [
            'viewed' => 'viewed',
            'contacted' => 'contacted',
            'under_review' => 'under review',
            'shortlisted' => 'shortlisted',
            'interview_scheduled' => 'scheduled for an interview',
            'pending' => 'marked as pending',
            'selected' => 'selected',
            'accepted' => 'accepted',
            'rejected' => 'not selected',
        ];
        $this->notify(
            $applicant,
            event: 'job_application_'.$validated['status'],
            title: 'Application update',
            message: "Your application for {$application->job->title} was {$labels[$validated['status']]}.",
            job: $application->job,
            application: $application,
        );

        return response()->json([
            'application' => $this->employerApplicationResponse(
                $application->load('applicant.communityProfile'),
            ),
        ]);
    }

    public function withdrawApplication(Request $request, JobApplication $application): JsonResponse
    {
        $profile = $this->requireCommunityMember($request);
        abort_unless((int) $application->applicant_id === (int) $request->user()->id, 403);
        abort_if(in_array($application->status, ['accepted', 'selected', 'rejected', 'withdrawn'], true), 409);
        $application->update(['status' => 'withdrawn']);
        $application->load('job.poster');
        $this->notify(
            $application->job->poster,
            event: 'job_application_withdrawn',
            title: 'Application withdrawn',
            message: "{$profile->display_name} withdrew an application for {$application->job->title}.",
            job: $application->job,
            application: $application,
        );

        return response()->json([
            'application' => [
                'id' => $application->id,
                'status' => $this->publicApplicationStatus($application->status),
            ],
        ]);
    }

    public function downloadResume(Request $request, JobApplication $application): BinaryFileResponse
    {
        $application->loadMissing('job.poster');
        $userId = $request->user()->id;
        abort_unless(
            $this->jobOwnerId($application->job) === (int) $userId ||
            (int) $application->applicant_id === (int) $userId,
            403,
        );

        abort_if($application->resume_path === null, 404);

        return $this->privateDownload($application->resume_path, $application->resume_name);
    }

    public function reportJob(Request $request, ConstructionJob $job): JsonResponse
    {
        $validated = $request->validate([
            'reason' => ['required', Rule::in(['spam', 'fraud', 'misleading', 'inappropriate', 'other'])],
            'details' => ['nullable', 'string', 'max:500'],
        ]);
        JobReport::query()->firstOrCreate(
            [
                'user_id' => $request->user()->id,
                'construction_job_id' => $job->id,
            ],
            [
                'reason' => $validated['reason'],
                'details' => $validated['details'] ?? null,
            ],
        );

        return response()->json(['message' => 'The job was reported for review.'], 201);
    }

    public function moderationReports(Request $request): JsonResponse
    {
        $this->authorizeModerator($request);
        $reports = JobReport::query()
            ->with(['job:id,title,status', 'reporter:id,name'])
            ->latest()
            ->paginate(20)
            ->through(fn (JobReport $report) => [
                'id' => $report->id,
                'reason' => $report->reason,
                'details' => $report->details,
                'status' => $report->status,
                'created_at' => $report->created_at?->toIso8601String(),
                'job' => $report->job ? [
                    'id' => $report->job->id,
                    'title' => $report->job->title,
                    'status' => $report->job->status,
                ] : null,
                'reporter' => $report->reporter ? [
                    'id' => $report->reporter->id,
                    'name' => $report->reporter->name,
                ] : null,
            ]);

        return response()->json(['reports' => $reports]);
    }

    public function updateJobReport(Request $request, JobReport $report): JsonResponse
    {
        $this->authorizeModerator($request);
        $validated = $request->validate([
            'status' => ['required', Rule::in(['reviewed', 'dismissed', 'action_taken'])],
        ]);
        $report->update(['status' => $validated['status']]);

        return response()->json(['report' => [
            'id' => $report->id,
            'status' => $report->status,
        ]]);
    }

    private function validateJob(
        Request $request,
        bool $partial = false,
        ?ConstructionJob $job = null,
    ): array {
        $required = $partial ? 'sometimes' : 'required';
        $validated = $request->validate([
            'category_id' => [$required, 'integer', Rule::exists('job_portal_categories', 'id')->where('is_active', true)],
            'other_category_description' => ['nullable', 'string', 'max:160'],
            'title' => [$required, 'string', 'max:160'],
            'description' => [$required, 'string', 'max:20000'],
            'employment_type' => [$required, Rule::in(self::EMPLOYMENT_TYPES)],
            'experience_required' => ['nullable', 'string', 'max:120'],
            'min_salary' => ['nullable', 'numeric', 'min:0', 'max:9999999999.99'],
            'max_salary' => ['nullable', 'numeric', 'min:0', 'max:9999999999.99'],
            'salary_type' => ['nullable', Rule::in(self::SALARY_TYPES)],
            'qualifications' => ['nullable', 'array', 'max:50'],
            'qualifications.*' => ['string', 'max:255'],
            'skills' => ['nullable', 'array', 'max:50'],
            'skills.*' => ['string', 'max:80'],
            'vacancies' => [$required, 'integer', 'between:1,10000'],
            'location_name' => [$required, 'string', 'max:255'],
            'latitude' => [$partial ? 'nullable' : 'required', 'numeric', 'between:-90,90'],
            'longitude' => [$partial ? 'nullable' : 'required', 'numeric', 'between:-180,180'],
            'application_deadline' => ['nullable', 'date', 'after:today'],
            'work_start_date' => ['nullable', 'date', 'after_or_equal:today'],
            'contact_preference' => [$partial ? 'sometimes' : 'required', Rule::in(['phone', 'email', 'both'])],
            'additional_instructions' => ['nullable', 'string', 'max:5000'],
            'contact_email' => ['nullable', 'email', 'max:254'],
            'contact_phone' => ['nullable', 'string', 'max:40'],
            'status' => [$partial ? 'sometimes' : 'nullable', Rule::in(['draft', 'published'])],
        ]);
        if ($request->filled('latitude') xor $request->filled('longitude')) {
            throw ValidationException::withMessages([
                'latitude' => 'Provide both coordinates or neither.',
            ]);
        }
        if (isset($validated['min_salary'], $validated['max_salary']) &&
            $validated['min_salary'] > $validated['max_salary']) {
            throw ValidationException::withMessages([
                'max_salary' => 'Maximum salary must be at least the minimum salary.',
            ]);
        }
        $categoryId = $validated['category_id'] ?? $job?->job_portal_category_id;
        $otherCategoryDescription = array_key_exists('other_category_description', $validated)
            ? $validated['other_category_description']
            : $job?->other_category_description;
        if ($categoryId !== null) {
            $category = JobPortalCategory::query()->find($categoryId);
            if ($category?->slug === 'other-construction-jobs'
                && trim((string) $otherCategoryDescription) === '') {
                throw ValidationException::withMessages([
                    'other_category_description' => 'Describe the construction job category.',
                ]);
            }
        }
        if (isset($validated['application_deadline'])) {
            $validated['application_deadline'] = Carbon::parse($validated['application_deadline'])
                ->endOfDay();
        }

        return $validated;
    }

    private function publishedJobs(): Builder
    {
        return ConstructionJob::query()
            ->where('status', 'published')
            ->where(function (Builder $builder) {
                $builder->whereNull('application_deadline')
                    ->orWhere('application_deadline', '>=', now());
            });
    }

    private function jobResponse(
        ConstructionJob $job,
        ?User $viewer,
        bool $details = false,
    ): array {
        $job->loadMissing(['poster.communityProfile', 'employer.user.communityProfile']);
        $poster = $job->poster;
        $profile = $poster?->communityProfile;
        $legacyEmployer = $job->employer;
        $distance = $job->getAttribute('distance_km');
        $response = [
            'id' => $job->id,
            'title' => $job->title,
            'description' => $details ? $job->description : null,
            'employment_type' => $job->employment_type,
            'other_category_description' => $job->other_category_description,
            'contact_preference' => $job->contact_preference,
            'additional_instructions' => $details ? $job->additional_instructions : null,
            'work_start_date' => $job->work_start_date?->toDateString(),
            'experience_required' => $job->experience_required,
            'min_salary' => $job->min_salary,
            'max_salary' => $job->max_salary,
            'salary_type' => $job->salary_type,
            'qualifications' => $job->qualifications ?? [],
            'skills' => $job->skills ?? [],
            'vacancies' => $job->vacancies,
            'location_name' => $job->location_name,
            'latitude' => $details ? $job->latitude : null,
            'longitude' => $details ? $job->longitude : null,
            'distance_km' => $distance === null ? null : round((float) $distance, 1),
            'application_deadline' => $job->application_deadline?->toIso8601String(),
            'status' => $job->status,
            'created_at' => $job->created_at?->toIso8601String(),
            'category' => $job->category ? [
                'id' => $job->category->id,
                'slug' => $job->category->slug,
                'name' => $job->category->name,
            ] : null,
            'company' => $poster !== null ? [
                'id' => $legacyEmployer?->id ?? $poster->id,
                'user_id' => $poster->id,
                'community_profile_id' => $profile?->id,
                'name' => $legacyEmployer?->company_name ?? $profile?->display_name ?? $poster->name,
                'logo_url' => $legacyEmployer?->company_logo_path
                    ? route('jobs.employer-logo', ['profile' => $legacyEmployer->id])
                    : ($profile?->profile_image_path
                        ? url("/api/community/media/profiles/{$profile->id}")
                        : null),
                'location' => $legacyEmployer?->location_name ?? $profile?->location,
                ...($details ? [
                    'employer_type' => $legacyEmployer?->employer_type ?? $profile?->trade,
                ] : []),
                ...($details ? [
                    'description' => $legacyEmployer?->company_description ?? $profile?->bio,
                    'website' => $legacyEmployer?->website,
                ] : []),
            ] : null,
            'is_saved' => $viewer !== null && $job->savedBy()
                ->where('user_id', $viewer->id)
                ->exists(),
            'application_status' => $viewer === null ? null : $this->publicApplicationStatus($job->applications()
                ->where('applicant_id', $viewer->id)
                ->value('status')),
        ];
        if ($details) {
            $response['contact'] = [
                'email' => in_array($job->contact_preference, ['email', 'both'], true)
                    ? $job->contact_email
                    : null,
                'phone_number' => null,
            ];
            $response['applications_count'] = $job->getAttribute('applications_count');
        }

        return $response;
    }

    private function publicApplicationStatus(?string $status): ?string
    {
        return match ($status) {
            'applied' => 'pending',
            'selected' => 'accepted',
            default => $status,
        };
    }

    private function employerResponse(EmployerProfile $profile): array
    {
        return [
            'id' => $profile->id,
            'company_name' => $profile->company_name,
            'employer_name' => $profile->employer_name,
            'email' => $profile->email,
            'phone_number' => $profile->phone_number,
            'company_logo_url' => $profile->company_logo_path
                ? route('jobs.employer-logo', ['profile' => $profile->id])
                : null,
            'company_description' => $profile->company_description,
            'website' => $profile->website,
            'location_name' => $profile->location_name,
            'latitude' => $profile->latitude,
            'longitude' => $profile->longitude,
            'employer_type' => $profile->employer_type,
        ];
    }

    private function seekerResponse(JobSeekerProfile $profile): array
    {
        return [
            'id' => $profile->id,
            'full_name' => $profile->full_name,
            'email' => $profile->email,
            'phone_number' => $profile->phone_number,
            'profile_image_url' => $profile->profile_image_path
                ? route('jobs.seeker-image', ['profile' => $profile->id])
                : null,
            'current_location' => $profile->current_location,
            'current_latitude' => $profile->current_latitude,
            'current_longitude' => $profile->current_longitude,
            'preferred_location' => $profile->preferred_location,
            'preferred_latitude' => $profile->preferred_latitude,
            'preferred_longitude' => $profile->preferred_longitude,
            'preferred_categories' => $profile->preferred_categories ?? [],
            'preferred_employment_types' => $profile->preferred_employment_types ?? [],
            'preferred_radius_km' => $profile->preferred_radius_km,
            'expected_salary' => $profile->expected_salary,
            'available_from' => $profile->available_from?->toDateString(),
            'notifications_enabled' => (bool) $profile->notifications_enabled,
            'profession' => $profile->profession ?? 'Community member',
            'skills' => $profile->skills ?? [],
            'experience_years' => $profile->experience_years,
            'education' => $profile->education,
            'has_resume' => $profile->resume_path !== null,
            'resume_name' => $profile->resume_name,
            'bio' => $profile->bio,
        ];
    }

    private function applicationResponse(JobApplication $application): array
    {
        return [
            'id' => $application->id,
            'status' => $this->publicApplicationStatus($application->status),
            'cover_letter' => $application->cover_letter,
            'applied_at' => $application->applied_at?->toIso8601String(),
            'interview_at' => $application->interview_at?->toIso8601String(),
            'employer_note' => $application->employer_note,
            'resume_name' => $application->resume_name,
            'job' => $application->job ? $this->jobResponse($application->job, null, true) : null,
        ];
    }

    private function employerApplicationResponse(JobApplication $application): array
    {
        $application->loadMissing([
            'jobSeeker.user.communityProfile',
            'applicant.communityProfile',
        ]);
        $profile = $application->applicant?->communityProfile;
        $legacy = $application->jobSeeker;

        return [
            'id' => $application->id,
            'status' => $this->publicApplicationStatus($application->status),
            'cover_letter' => $application->cover_letter,
            'applied_at' => $application->applied_at?->toIso8601String(),
            'interview_at' => $application->interview_at?->toIso8601String(),
            'employer_note' => $application->employer_note,
            'resume_name' => $application->resume_name,
            'resume_url' => $application->resume_path === null
                ? null
                : route('jobs.application-resume', ['application' => $application->id]),
            'candidate' => [
                'id' => $profile?->id ?? $legacy?->id,
                'user_id' => $application->applicant_id ?? $legacy?->user_id,
                'community_profile_id' => $profile?->id
                    ?? $legacy?->user?->communityProfile?->id,
                'full_name' => $profile?->display_name ?? $legacy?->full_name,
                'email' => null,
                'phone_number' => null,
                'profile_image_url' => $profile?->profile_image_path
                    ? url("/api/community/media/profiles/{$profile->id}")
                    : ($legacy?->profile_image_path
                        ? route('jobs.seeker-image', ['profile' => $legacy->id])
                        : null),
                'current_location' => $profile?->location ?? $legacy?->current_location,
                'profession' => $profile?->trade ?? $legacy?->profession,
                'skills' => $profile?->skills ?? $legacy?->skills ?? [],
                'experience_years' => $profile?->experience_years ?? $legacy?->experience_years,
                'education' => $legacy?->education,
                'bio' => $profile?->bio ?? $legacy?->bio,
            ],
        ];
    }

    private function communityJobProfileResponse(CommunityProfile $profile): array
    {
        $user = $profile->user;

        return [
            'id' => $profile->id,
            'user_id' => $profile->user_id,
            'display_name' => $profile->display_name,
            'posts_count' => $profile->posts()->count(),
            'email' => $user?->email,
            'phone_number' => $user?->phone_number,
            'profile_image_url' => $profile->profile_image_path
                ? url("/api/community/media/profiles/{$profile->id}")
                : null,
            'profession' => $profile->profession === 'Other'
                ? ($profile->other_profession ?: 'Community member')
                : ($profile->profession ?? 'Community member'),
            'profession_type' => $profile->profession,
            'other_profession' => $profile->other_profession,
            'trade' => $profile->trade,
            'skills' => $profile->skills ?? [],
            'experience_years' => $profile->experience_years,
            'bio' => $profile->bio,
            'location' => $profile->location,
            'latitude' => $profile->latitude,
            'longitude' => $profile->longitude,
            'preferred_categories' => $profile->preferred_categories ?? [],
            'preferred_location' => $profile->preferred_location,
            'preferred_latitude' => $profile->preferred_latitude,
            'preferred_longitude' => $profile->preferred_longitude,
            'preferred_radius_km' => $profile->preferred_radius_km ?? 25,
            'job_notifications_enabled' => (bool) $profile->job_notifications_enabled,
        ];
    }

    private function requireEmployer(Request $request): EmployerProfile
    {
        $this->requireCommunityMember($request);
        $profile = EmployerProfile::query()
            ->where('user_id', $request->user()->id)
            ->first();
        abort_if($profile === null, 409, 'Complete your Employer profile first.');

        return $profile;
    }

    private function requireSeeker(Request $request): JobSeekerProfile
    {
        $this->requireCommunityMember($request);
        $profile = JobSeekerProfile::query()
            ->where('user_id', $request->user()->id)
            ->first();
        abort_if($profile === null, 409, 'Complete your Job Seeker profile first.');

        return $profile;
    }

    private function jobOwnerId(ConstructionJob $job): int
    {
        return (int) ($job->employer_id ?? $job->employer?->user_id ?? 0);
    }

    private function requireCommunityMember(Request $request): CommunityProfile
    {
        $profile = CommunityProfile::query()
            ->where('user_id', $request->user()->id)
            ->first();
        abort_if($profile === null, 409, 'Complete Community registration first.');

        return $profile;
    }

    private function authorizeModerator(Request $request): void
    {
        abort_unless(
            in_array(
                (int) $request->user()->id,
                config('job_portal.moderator_user_ids', []),
                true,
            ),
            403,
        );
    }

    private function privateDownload(string $path, ?string $name = null): BinaryFileResponse
    {
        $disk = Storage::disk('local');
        abort_unless($disk->exists($path), 404);
        $response = response()->download(
            $disk->path($path),
            $name ?? basename($path),
            ['Cache-Control' => 'private, no-store'],
        );
        $response->headers->set('X-Content-Type-Options', 'nosniff');

        return $response;
    }

    private function deleteStoredFile(?string $path): void
    {
        if ($path !== null && Storage::disk('local')->exists($path)) {
            Storage::disk('local')->delete($path);
        }
    }

    private function validationError(string $field, string $message): JsonResponse
    {
        return response()->json([
            'message' => $message,
            'errors' => [$field => [$message]],
        ], 422);
    }

    private function distanceInKilometers(
        float $latitude,
        float $longitude,
        ?float $jobLatitude,
        ?float $jobLongitude,
    ): float {
        if ($jobLatitude === null || $jobLongitude === null) {
            return INF;
        }
        $latitudeDelta = deg2rad($jobLatitude - $latitude);
        $longitudeDelta = deg2rad($jobLongitude - $longitude);
        $a = sin($latitudeDelta / 2) ** 2
            + cos(deg2rad($latitude))
            * cos(deg2rad($jobLatitude))
            * sin($longitudeDelta / 2) ** 2;

        return 6371 * 2 * asin(sqrt(min(1, $a)));
    }

    private function notify(
        User $user,
        string $event,
        string $title,
        string $message,
        ConstructionJob $job,
        ?JobApplication $application = null,
    ): void {
        $notification = new JobPortalNotification(
            event: $event,
            title: $title,
            message: $message,
            jobId: $job->id,
            jobTitle: $job->title,
            applicationId: $application?->id,
        );
        $user->notify($notification);
        $this->firebasePushService->queue($user, $notification->toPushPayload());
    }
}
