<?php

namespace Tests\Feature;

use App\Jobs\MatchConstructionJobSeekers;
use App\Models\CommunityProfile;
use App\Models\ConstructionJob;
use App\Models\EmployerProfile;
use App\Models\JobApplication;
use App\Models\JobPortalCategory;
use App\Models\JobSeekerProfile;
use App\Models\User;
use App\Services\FirebasePushService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class JobPortalApiTest extends TestCase
{
    use RefreshDatabase;

    protected function defineEnvironment($app): void
    {
        $app['config']->set('database.default', 'sqlite');
        $app['config']->set('database.connections.sqlite.database', ':memory:');
    }

    public function test_legacy_profile_registration_endpoints_are_disabled(): void
    {
        $this->getJson('/api/jobs')->assertUnauthorized();

        $user = User::factory()->create(['role' => 'homeowner']);
        $this->createCommunityProfile($user);
        $this->actingAs($user, 'sanctum');

        $this->getJson('/api/jobs/employer-profile')->assertNotFound();
        $this->postJson('/api/jobs/employer-profile', $this->employerData())
            ->assertNotFound();
        $this->getJson('/api/jobs/job-seeker-profile')->assertNotFound();
        $this->postJson('/api/jobs/job-seeker-profile', $this->seekerData())
            ->assertNotFound();

        $this->assertSame('homeowner', $user->fresh()->role);
        $this->assertDatabaseMissing('employer_profiles', ['user_id' => $user->id]);
        $this->assertDatabaseMissing('job_seeker_profiles', ['user_id' => $user->id]);
    }

    public function test_employer_can_publish_and_manage_a_job_but_another_user_cannot(): void
    {
        $employer = User::factory()->create();
        $this->createCommunityProfile($employer);
        $this->actingAs($employer, 'sanctum');

        $otherUser = User::factory()->create();
        $job = $this->postJson('/api/jobs', [
            ...$this->jobData(),
            'employer_id' => $otherUser->id,
        ])
            ->assertCreated()
            ->assertJsonPath('job.status', 'published')
            ->json('job');

        $otherUser = User::factory()->create();
        $this->createCommunityProfile($otherUser);
        $this->actingAs($otherUser, 'sanctum')
            ->patchJson("/api/jobs/{$job['id']}", ['title' => 'Unauthorized edit'])
            ->assertForbidden();

        $this->patchJson("/api/jobs/{$job['id']}", ['title' => 'Unauthorized edit'])
            ->assertForbidden();

        $this->getJson('/api/jobs')
            ->assertOk()
            ->assertJsonPath('jobs.data.0.title', 'Site Architect');
        $this->actingAs($employer, 'sanctum');
        $this->putJson("/api/jobs/{$job['id']}/status", ['status' => 'closed'])
            ->assertOk()
            ->assertJsonPath('job.status', 'closed');
        $this->getJson("/api/jobs/{$job['id']}")
            ->assertOk()
            ->assertJsonPath('job.status', 'closed');
    }

    public function test_community_members_can_post_apply_and_manage_applications_without_separate_profiles(): void
    {
        $poster = User::factory()->create();
        $this->createCommunityProfile($poster);
        $this->actingAs($poster, 'sanctum');

        $job = $this->postJson('/api/jobs', $this->jobData())
            ->assertCreated()
            ->json('job');
        $this->assertDatabaseHas('construction_jobs', [
            'id' => $job['id'],
            'employer_id' => $poster->id,
            'employer_profile_id' => null,
        ]);
        $this->assertDatabaseMissing('employer_profiles', ['user_id' => $poster->id]);

        $applicant = User::factory()->create();
        $this->createCommunityProfile($applicant);
        $this->actingAs($applicant, 'sanctum')
            ->postJson("/api/jobs/{$job['id']}/applications", [
                'cover_letter' => 'I have relevant site experience.',
                'applicant_id' => $poster->id,
            ])
            ->assertCreated()
            ->assertJsonPath('application.status', 'pending');

        $application = JobApplication::query()->firstOrFail();
        $this->assertSame($applicant->id, $application->applicant_id);
        $this->assertNull($application->job_seeker_profile_id);
        $this->assertDatabaseMissing('job_seeker_profiles', ['user_id' => $applicant->id]);

        $this->actingAs($poster, 'sanctum')
            ->getJson("/api/jobs/{$job['id']}/applications")
            ->assertOk()
            ->assertJsonPath(
                'applications.data.0.candidate.community_profile_id',
                $applicant->communityProfile->id,
            );
        $this->patchJson("/api/jobs/applications/{$application->id}", [
            'status' => 'shortlisted',
        ])->assertOk()
            ->assertJsonPath('application.status', 'shortlisted');
        $this->patchJson("/api/jobs/applications/{$application->id}", [
            'status' => 'accepted',
        ])->assertOk()
            ->assertJsonPath('application.status', 'accepted');

        $this->actingAs($applicant, 'sanctum')
            ->getJson('/api/jobs/applications')
            ->assertOk()
            ->assertJsonPath('applications.data.0.status', 'accepted');
    }

    public function test_community_profile_stores_shared_job_preferences_and_private_account_contact(): void
    {
        $categoryId = JobPortalCategory::query()
            ->where('slug', 'electrician')
            ->value('id');
        $user = User::factory()->create([
            'email' => 'member@example.test',
            'phone_number' => '+1 555 0110',
        ]);
        $this->createCommunityProfile($user);

        $this->actingAs($user, 'sanctum')
            ->patchJson('/api/community/profile', [
                'display_name' => 'Community Member',
                'location' => 'Kakkanad',
                'latitude' => 10.016,
                'longitude' => 76.341,
                'trade' => 'Electrician',
                'skills' => ['Wiring', 'Safety'],
                'experience_years' => 4,
                'preferred_categories' => [$categoryId],
                'preferred_radius_km' => 50,
                'job_notifications_enabled' => true,
            ])
            ->assertOk()
            ->assertJsonPath('profile.display_name', 'Community Member')
            ->assertJsonPath('profile.trade', 'Electrician')
            ->assertJsonPath('profile.skills.0', 'Wiring')
            ->assertJsonPath('profile.preferred_categories.0', $categoryId)
            ->assertJsonPath('profile.preferred_radius_km', 50)
            ->assertJsonPath('profile.job_notifications_enabled', true)
            ->assertJsonPath('profile.email', 'member@example.test')
            ->assertJsonPath('profile.phone_number', '+1 555 0110');

        $this->assertSame('Community Member', $user->fresh()->name);
        $this->assertSame('Kakkanad', $user->fresh()->location);
    }

    public function test_job_dashboard_accepts_community_profiles_without_a_selected_profession(): void
    {
        $user = User::factory()->create();
        $this->createCommunityProfile($user);

        $this->actingAs($user, 'sanctum')
            ->getJson('/api/jobs/dashboard')
            ->assertOk()
            ->assertJsonPath('community_profile.profession', 'Community member')
            ->assertJsonPath('community_profile.display_name', $user->name);
    }

    public function test_invalid_coordinates_and_salary_ranges_are_rejected(): void
    {
        $employer = User::factory()->create();
        $this->createCommunityProfile($employer);
        $this->actingAs($employer, 'sanctum');

        $this->postJson('/api/jobs', [
            ...$this->jobData(),
            'longitude' => null,
        ])->assertUnprocessable()
            ->assertJsonValidationErrors('longitude');

        $this->postJson('/api/jobs', [
            ...$this->jobData(),
            'min_salary' => 5000,
            'max_salary' => 3000,
        ])->assertUnprocessable()
            ->assertJsonValidationErrors('max_salary');
    }

    public function test_other_construction_jobs_require_a_description_and_expiry_covers_the_selected_day(): void
    {
        $employer = User::factory()->create();
        $this->createCommunityProfile($employer);
        $this->actingAs($employer, 'sanctum');

        $otherCategoryId = JobPortalCategory::query()
            ->where('slug', 'other-construction-jobs')
            ->value('id');
        $deadline = now()->addDays(2)->startOfDay();
        $jobData = [
            ...$this->jobData(),
            'category_id' => $otherCategoryId,
            'application_deadline' => $deadline->toDateString(),
        ];

        $this->postJson('/api/jobs', $jobData)
            ->assertUnprocessable()
            ->assertJsonValidationErrors('other_category_description');

        $job = $this->postJson('/api/jobs', [
            ...$jobData,
            'other_category_description' => 'Construction site safety coordinator',
        ])->assertCreated()
            ->json('job');

        $this->assertDatabaseHas('construction_jobs', [
            'id' => $job['id'],
            'application_deadline' => $deadline->endOfDay()->format('Y-m-d H:i:s'),
        ]);
        $this->patchJson("/api/jobs/{$job['id']}", [
            'other_category_description' => '',
        ])->assertUnprocessable()
            ->assertJsonValidationErrors('other_category_description');
    }

    public function test_nearby_job_search_returns_the_matching_jobs_in_distance_order(): void
    {
        $employer = User::factory()->create();
        $this->createCommunityProfile($employer);
        $this->actingAs($employer, 'sanctum');
        $nearby = $this->postJson('/api/jobs', $this->jobData())
            ->assertCreated()
            ->json('job.id');
        $this->postJson('/api/jobs', [
            ...$this->jobData(),
            'title' => 'Remote Architect',
            'latitude' => 42.0,
            'longitude' => -89.64,
        ])->assertCreated();

        $seeker = User::factory()->create();
        $this->actingAs($seeker, 'sanctum')
            ->getJson('/api/jobs?latitude=39.78&longitude=-89.64&distance_km=5')
            ->assertOk()
            ->assertJsonPath('jobs.data.0.id', $nearby)
            ->assertJsonCount(1, 'jobs.data');
    }

    public function test_job_search_save_and_application_enforce_ownership_and_resume_access(): void
    {
        $employer = User::factory()->create();
        $this->createCommunityProfile($employer);
        $this->actingAs($employer, 'sanctum');
        $job = $this->postJson('/api/jobs', $this->jobData())
            ->assertCreated()
            ->json('job');

        $seeker = User::factory()->create(['role' => 'designer']);
        $this->createCommunityProfile($seeker);
        $this->actingAs($seeker, 'sanctum');
        $this->putJson("/api/jobs/{$job['id']}/saved")->assertOk()
            ->assertJsonPath('saved', true);
        $this->getJson('/api/jobs/saved')->assertOk()
            ->assertJsonPath('jobs.data.0.id', $job['id']);
        $this->postJson("/api/jobs/{$job['id']}/applications", [
            'cover_letter' => 'I have relevant experience.',
        ])->assertCreated()
            ->assertJsonPath('application.status', 'pending');

        $application = JobApplication::query()->firstOrFail();
        $this->assertNull($application->resume_path);

        $this->postJson("/api/jobs/{$job['id']}/applications", [])
            ->assertConflict();
        $this->getJson("/api/jobs/applications/{$application->id}/resume")
            ->assertNotFound();

        $anotherSeeker = User::factory()->create();
        $this->actingAs($anotherSeeker, 'sanctum')
            ->getJson("/api/jobs/applications/{$application->id}/resume")
            ->assertForbidden();

        $this->actingAs($employer, 'sanctum')
            ->getJson("/api/jobs/{$job['id']}/applications")
            ->assertOk()
            ->assertJsonPath('applications.data.0.candidate.user_id', $seeker->id)
            ->assertJsonPath(
                'applications.data.0.candidate.community_profile_id',
                $seeker->communityProfile->id,
            );
        $this->actingAs($anotherSeeker, 'sanctum')
            ->getJson("/api/jobs/{$job['id']}/applications")
            ->assertStatus(409);
    }

    public function test_job_posters_and_applicants_use_mutual_contact_actions_without_phone_leaks(): void
    {
        $employer = User::factory()->create(['phone_number' => '+919876543210']);
        $this->createCommunityProfile($employer);
        $this->actingAs($employer, 'sanctum')
            ->patchJson('/api/community/profile', ['is_phone_visible' => true])
            ->assertOk();
        $job = $this->postJson('/api/jobs', [
            ...$this->jobData(),
            'contact_preference' => 'phone',
            'contact_phone' => '+919999000000',
            'status' => 'published',
        ])->assertCreated()
            ->json('job');

        $seeker = User::factory()->create(['phone_number' => '+919876500000']);
        $this->createCommunityProfile($seeker);
        $this->actingAs($seeker, 'sanctum')
            ->patchJson('/api/community/profile', ['is_phone_visible' => true])
            ->assertOk();
        $seekerProfile = JobSeekerProfile::query()->create([
            'user_id' => $seeker->id,
            ...$this->seekerData(),
        ]);

        JobApplication::query()->create([
            'construction_job_id' => $job['id'],
            'job_seeker_profile_id' => $seekerProfile->id,
            'resume_path' => 'private/resume.pdf',
            'resume_name' => 'resume.pdf',
            'status' => 'applied',
            'applied_at' => now(),
        ]);

        $this->actingAs($seeker, 'sanctum')
            ->getJson("/api/jobs/{$job['id']}")
            ->assertOk()
            ->assertJsonPath('job.company.user_id', $employer->id)
            ->assertJsonPath('job.contact.phone_number', null)
            ->assertJsonMissing(['+919876543210', '+919999000000']);

        $this->actingAs($employer, 'sanctum')
            ->getJson("/api/jobs/{$job['id']}/applications")
            ->assertOk()
            ->assertJsonPath('applications.data.0.candidate.user_id', $seeker->id)
            ->assertJsonPath(
                'applications.data.0.candidate.community_profile_id',
                $seeker->communityProfile->id,
            )
            ->assertJsonPath('applications.data.0.candidate.phone_number', null)
            ->assertJsonMissing(['+919876500000']);
    }

    public function test_job_reports_are_deduplicated_and_only_moderators_can_resolve_them(): void
    {
        $employer = User::factory()->create();
        $this->createCommunityProfile($employer);
        $this->actingAs($employer, 'sanctum');
        $job = $this->postJson('/api/jobs', $this->jobData())
            ->assertCreated()
            ->json('job');

        $reporter = User::factory()->create();
        $this->actingAs($reporter, 'sanctum')
            ->postJson("/api/jobs/{$job['id']}/reports", [
                'reason' => 'misleading',
                'details' => 'The listing contains incorrect information.',
            ])->assertCreated();
        $this->actingAs($reporter, 'sanctum')
            ->postJson("/api/jobs/{$job['id']}/reports", [
                'reason' => 'fraud',
            ])->assertCreated();
        $this->assertDatabaseCount('job_reports', 1);
        $this->getJson('/api/jobs/moderation/reports')->assertForbidden();

        config(['job_portal.moderator_user_ids' => [$reporter->id]]);
        $this->getJson('/api/jobs/moderation/reports')
            ->assertOk()
            ->assertJsonPath('reports.data.0.reason', 'misleading');
        $this->putJson('/api/jobs/moderation/reports/1', [
            'status' => 'action_taken',
        ])->assertOk()
            ->assertJsonPath('report.status', 'action_taken');
    }

    public function test_nearby_notifications_match_category_radius_preferences_and_are_deduplicated(): void
    {
        $category = JobPortalCategory::query()
            ->where('slug', 'electrician')
            ->firstOrFail();
        $employer = User::factory()->create();
        $employerProfile = EmployerProfile::query()->create([
            'user_id' => $employer->id,
            ...$this->employerData(),
        ]);
        CommunityProfile::query()->create([
            'user_id' => $employer->id,
            'display_name' => 'Employer',
            'guidelines_accepted_at' => now(),
        ]);
        $job = ConstructionJob::query()->create([
            'employer_profile_id' => $employerProfile->id,
            'job_portal_category_id' => $category->id,
            'title' => 'Electrician needed',
            'description' => 'Residential wiring project.',
            'employment_type' => 'Daily Wage',
            'vacancies' => 2,
            'location_name' => 'Kakkanad',
            'latitude' => 10.016,
            'longitude' => 76.341,
            'contact_preference' => 'phone',
            'status' => 'published',
        ]);

        $matchingSeeker = $this->createJobNotificationSeeker(
            categoryId: $category->id,
            latitude: 10.02,
            longitude: 76.34,
            radius: 10,
        );
        $this->createJobNotificationSeeker(
            categoryId: JobPortalCategory::query()->where('slug', 'painter')->value('id'),
            latitude: 10.02,
            longitude: 76.34,
            radius: 10,
        );
        $this->createJobNotificationSeeker(
            categoryId: $category->id,
            latitude: 11,
            longitude: 76.34,
            radius: 5,
        );

        $push = \Mockery::mock(FirebasePushService::class);
        $push->shouldReceive('queue')->once()
            ->withArgs(fn (User $user, array $payload) => $user->id === $matchingSeeker->id
                && $payload['data']['job_id'] === (string) $job->id
                && $payload['data']['job_category'] === 'Electrician'
                && $payload['data']['job_location'] === 'Kakkanad'
                && $payload['data']['notification_type'] === 'nearby_construction_job');

        $matcher = new MatchConstructionJobSeekers($job->id);
        $matcher->handle($push);
        $matcher->handle($push);

        $this->assertDatabaseCount('job_notifications', 1);
        $this->assertDatabaseHas('job_notifications', [
            'user_id' => $matchingSeeker->id,
            'construction_job_id' => $job->id,
            'notification_type' => 'nearby_construction_job',
        ]);
    }

    private function createJobNotificationSeeker(
        int $categoryId,
        float $latitude,
        float $longitude,
        int $radius,
    ): User {
        $user = User::factory()->create();
        CommunityProfile::query()->create([
            'user_id' => $user->id,
            'display_name' => 'Job seeker',
            'guidelines_accepted_at' => now(),
            'preferred_categories' => [$categoryId],
            'preferred_latitude' => $latitude,
            'preferred_longitude' => $longitude,
            'preferred_radius_km' => $radius,
            'job_notifications_enabled' => true,
        ]);

        return $user;
    }

    private function employerData(): array
    {
        return [
            'company_name' => 'Build Arch Works',
            'employer_name' => 'Hiring Manager',
            'email' => 'jobs@example.test',
            'phone_number' => '+1 555 0100',
            'company_description' => 'Construction and design services.',
            'location_name' => 'Springfield',
            'employer_type' => 'Construction Company',
        ];
    }

    private function createCommunityProfile(User $user): void
    {
        CommunityProfile::query()->create([
            'user_id' => $user->id,
            'display_name' => $user->name,
            'guidelines_accepted_at' => now(),
        ]);
    }

    private function seekerData(): array
    {
        return [
            'full_name' => 'Test Seeker',
            'email' => 'seeker@example.test',
            'phone_number' => '+1 555 0101',
            'profession' => 'Architect',
            'skills' => ['Planning', 'Design'],
        ];
    }

    private function jobData(): array
    {
        return [
            'category_id' => JobPortalCategory::query()->where('slug', 'architect')->value('id'),
            'title' => 'Site Architect',
            'description' => 'Coordinate architectural work at the construction site.',
            'employment_type' => 'Full Time',
            'experience_required' => '3 years',
            'min_salary' => 3000,
            'max_salary' => 6000,
            'salary_type' => 'Monthly',
            'qualifications' => ['Architecture degree'],
            'skills' => ['Planning'],
            'vacancies' => 1,
            'location_name' => 'Springfield',
            'latitude' => 39.78,
            'longitude' => -89.64,
            'contact_preference' => 'both',
            'contact_email' => 'jobs@example.test',
            'status' => 'published',
        ];
    }
}
