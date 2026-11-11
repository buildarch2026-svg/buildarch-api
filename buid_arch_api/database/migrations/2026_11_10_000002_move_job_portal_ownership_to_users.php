<?php

use App\Models\JobSeekerProfile;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('community_profiles', function (Blueprint $table) {
            $table->decimal('latitude', 10, 7)->nullable();
            $table->decimal('longitude', 10, 7)->nullable();
            $table->string('trade', 120)->nullable();
            $table->json('skills')->nullable();
            $table->unsignedSmallInteger('experience_years')->nullable();
            $table->string('preferred_location', 255)->nullable();
            $table->decimal('preferred_latitude', 10, 7)->nullable();
            $table->decimal('preferred_longitude', 10, 7)->nullable();
            $table->json('preferred_categories')->nullable();
            $table->unsignedTinyInteger('preferred_radius_km')->default(25);
            $table->boolean('job_notifications_enabled')->default(false);
        });

        Schema::table('construction_jobs', function (Blueprint $table) {
            $table->foreignId('employer_id')->nullable()->constrained('users')->cascadeOnDelete();
            $table->unsignedBigInteger('employer_profile_id')->nullable()->change();
        });

        Schema::table('job_applications', function (Blueprint $table) {
            $table->foreignId('applicant_id')->nullable()->constrained('users')->cascadeOnDelete();
            $table->unsignedBigInteger('job_seeker_profile_id')->nullable()->change();
            $table->string('resume_path')->nullable()->change();
            $table->string('resume_name')->nullable()->change();
            $table->unique(
                ['construction_job_id', 'applicant_id'],
                'job_application_unique_applicant_job',
            );
        });

        Schema::table('saved_construction_jobs', function (Blueprint $table) {
            $table->foreignId('user_id')->nullable()->constrained()->cascadeOnDelete();
            $table->unsignedBigInteger('job_seeker_profile_id')->nullable()->change();
            $table->unique(
                ['construction_job_id', 'user_id'],
                'saved_construction_job_unique_user',
            );
        });

        DB::statement(
            'UPDATE construction_jobs SET employer_id = '
            .'(SELECT user_id FROM employer_profiles WHERE employer_profiles.id = construction_jobs.employer_profile_id) '
            .'WHERE employer_id IS NULL AND employer_profile_id IS NOT NULL',
        );
        DB::statement(
            'UPDATE job_applications SET applicant_id = '
            .'(SELECT user_id FROM job_seeker_profiles WHERE job_seeker_profiles.id = job_applications.job_seeker_profile_id) '
            .'WHERE applicant_id IS NULL AND job_seeker_profile_id IS NOT NULL',
        );
        DB::statement(
            'UPDATE saved_construction_jobs SET user_id = '
            .'(SELECT user_id FROM job_seeker_profiles WHERE job_seeker_profiles.id = saved_construction_jobs.job_seeker_profile_id) '
            .'WHERE user_id IS NULL AND job_seeker_profile_id IS NOT NULL',
        );

        JobSeekerProfile::query()->with('user.communityProfile')->chunkById(100, function ($seekers): void {
            foreach ($seekers as $seeker) {
                $profile = $seeker->user?->communityProfile;
                if ($profile === null) {
                    continue;
                }

                $attributes = [];
                foreach ([
                    'trade' => $seeker->profession,
                    'bio' => $seeker->bio,
                    'profile_image_path' => $seeker->profile_image_path,
                    'location' => $seeker->current_location,
                    'latitude' => $seeker->current_latitude,
                    'longitude' => $seeker->current_longitude,
                    'skills' => $seeker->skills,
                    'experience_years' => $seeker->experience_years,
                    'preferred_location' => $seeker->preferred_location,
                    'preferred_latitude' => $seeker->preferred_latitude,
                    'preferred_longitude' => $seeker->preferred_longitude,
                    'preferred_categories' => $seeker->preferred_categories,
                    'preferred_radius_km' => $seeker->preferred_radius_km,
                    'job_notifications_enabled' => $seeker->notifications_enabled,
                ] as $field => $value) {
                    if ($value !== null && $profile->{$field} === null) {
                        $attributes[$field] = $value;
                    }
                }
                if ($attributes !== []) {
                    $profile->forceFill($attributes)->save();
                }
            }
        });
    }

    public function down(): void
    {
        throw new RuntimeException(
            'This migration preserves existing job and applicant data. '
            .'Restore a backup before reversing the ownership migration.',
        );
    }
};
