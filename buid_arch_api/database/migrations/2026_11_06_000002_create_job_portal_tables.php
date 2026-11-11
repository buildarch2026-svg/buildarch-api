<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    private const CATEGORIES = [
        'civil-engineer' => 'Civil Engineer',
        'architect' => 'Architect',
        'interior-designer' => 'Interior Designer',
        'site-engineer' => 'Site Engineer',
        'site-supervisor' => 'Site Supervisor',
        'project-manager' => 'Project Manager',
        'quantity-surveyor' => 'Quantity Surveyor',
        'structural-engineer' => 'Structural Engineer',
        'electrician' => 'Electrician',
        'plumber' => 'Plumber',
        'carpenter' => 'Carpenter',
        'mason' => 'Mason',
        'painter' => 'Painter',
        'construction-labour' => 'Construction Labour',
        'safety-officer' => 'Safety Officer',
        'other' => 'Other',
    ];

    public function up(): void
    {
        Schema::create('job_portal_categories', function (Blueprint $table) {
            $table->id();
            $table->string('slug')->unique();
            $table->string('name')->unique();
            $table->boolean('is_active')->default(true)->index();
            $table->timestamps();
        });

        foreach (self::CATEGORIES as $slug => $name) {
            DB::table('job_portal_categories')->insert([
                'slug' => $slug,
                'name' => $name,
                'created_at' => now(),
                'updated_at' => now(),
            ]);
        }

        Schema::create('employer_profiles', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->unique()->constrained()->cascadeOnDelete();
            $table->string('company_name', 160);
            $table->string('employer_name', 120);
            $table->string('email', 254);
            $table->string('phone_number', 40);
            $table->string('company_logo_path')->nullable();
            $table->text('company_description');
            $table->string('website', 2048)->nullable();
            $table->string('location_name', 255);
            $table->decimal('latitude', 10, 7)->nullable();
            $table->decimal('longitude', 10, 7)->nullable();
            $table->string('employer_type', 40);
            $table->timestamps();
            $table->index(['latitude', 'longitude']);
        });

        Schema::create('job_seeker_profiles', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->unique()->constrained()->cascadeOnDelete();
            $table->string('full_name', 120);
            $table->string('email', 254);
            $table->string('phone_number', 40);
            $table->string('profile_image_path')->nullable();
            $table->string('current_location', 255)->nullable();
            $table->decimal('current_latitude', 10, 7)->nullable();
            $table->decimal('current_longitude', 10, 7)->nullable();
            $table->string('preferred_location', 255)->nullable();
            $table->decimal('preferred_latitude', 10, 7)->nullable();
            $table->decimal('preferred_longitude', 10, 7)->nullable();
            $table->string('profession', 120)->nullable();
            $table->json('skills')->nullable();
            $table->unsignedSmallInteger('experience_years')->nullable();
            $table->string('education', 255)->nullable();
            $table->string('resume_path')->nullable();
            $table->string('resume_name')->nullable();
            $table->text('bio')->nullable();
            $table->timestamps();
            $table->index(['current_latitude', 'current_longitude']);
            $table->index(['preferred_latitude', 'preferred_longitude']);
        });

        Schema::create('construction_jobs', function (Blueprint $table) {
            $table->id();
            $table->foreignId('employer_profile_id')->constrained()->cascadeOnDelete();
            $table->foreignId('job_portal_category_id')->constrained()->restrictOnDelete();
            $table->string('title', 160);
            $table->text('description');
            $table->string('employment_type', 24);
            $table->string('experience_required', 120)->nullable();
            $table->decimal('min_salary', 12, 2)->nullable();
            $table->decimal('max_salary', 12, 2)->nullable();
            $table->string('salary_type', 12)->nullable();
            $table->json('qualifications')->nullable();
            $table->json('skills')->nullable();
            $table->unsignedSmallInteger('vacancies')->default(1);
            $table->string('location_name', 255);
            $table->decimal('latitude', 10, 7)->nullable();
            $table->decimal('longitude', 10, 7)->nullable();
            $table->timestamp('application_deadline')->nullable();
            $table->string('contact_email', 254)->nullable();
            $table->string('contact_phone', 40)->nullable();
            $table->string('status', 16)->default('draft');
            $table->timestamps();
            $table->softDeletes();
            $table->index(['status', 'created_at']);
            $table->index(['job_portal_category_id', 'status', 'created_at'], 'jobs_category_status_created_idx');
            $table->index(['latitude', 'longitude']);
            $table->index('application_deadline');
            $table->index(['employer_profile_id', 'status']);
        });

        Schema::create('job_applications', function (Blueprint $table) {
            $table->id();
            $table->foreignId('construction_job_id')->constrained()->cascadeOnDelete();
            $table->foreignId('job_seeker_profile_id')->constrained()->cascadeOnDelete();
            $table->string('resume_path');
            $table->string('resume_name');
            $table->text('cover_letter')->nullable();
            $table->string('status', 32)->default('applied');
            $table->timestamp('applied_at');
            $table->timestamp('interview_at')->nullable();
            $table->text('employer_note')->nullable();
            $table->timestamps();
            $table->unique(
                ['construction_job_id', 'job_seeker_profile_id'],
                'job_application_unique_seeker_job',
            );
            $table->index(['construction_job_id', 'status', 'applied_at'], 'job_applications_job_status_applied_idx');
            $table->index(['job_seeker_profile_id', 'applied_at']);
        });

        Schema::create('saved_construction_jobs', function (Blueprint $table) {
            $table->id();
            $table->foreignId('construction_job_id')->constrained()->cascadeOnDelete();
            $table->foreignId('job_seeker_profile_id')->constrained()->cascadeOnDelete();
            $table->timestamps();
            $table->unique(
                ['construction_job_id', 'job_seeker_profile_id'],
                'saved_construction_job_unique',
            );
        });

        Schema::create('job_reports', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->foreignId('construction_job_id')->constrained()->cascadeOnDelete();
            $table->string('reason', 40);
            $table->string('details', 500)->nullable();
            $table->string('status', 20)->default('open')->index();
            $table->timestamps();
            $table->unique(['user_id', 'construction_job_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('job_reports');
        Schema::dropIfExists('saved_construction_jobs');
        Schema::dropIfExists('job_applications');
        Schema::dropIfExists('construction_jobs');
        Schema::dropIfExists('job_seeker_profiles');
        Schema::dropIfExists('employer_profiles');
        Schema::dropIfExists('job_portal_categories');
    }
};
