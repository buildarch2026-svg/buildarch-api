<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    private const CATEGORIES = [
        'tile-worker' => 'Tile Worker',
        'welder' => 'Welder',
        'hvac-technician' => 'HVAC Technician',
        'heavy-equipment-operator' => 'Heavy Equipment Operator',
    ];

    public function up(): void
    {
        Schema::table('job_seeker_profiles', function (Blueprint $table) {
            $table->json('preferred_categories')->nullable();
            $table->json('preferred_employment_types')->nullable();
            $table->unsignedTinyInteger('preferred_radius_km')->default(25);
            $table->decimal('expected_salary', 12, 2)->nullable();
            $table->date('available_from')->nullable();
            $table->boolean('notifications_enabled')->default(false);
        });

        Schema::table('construction_jobs', function (Blueprint $table) {
            $table->string('other_category_description', 160)->nullable();
            $table->string('contact_preference', 12)->default('both');
            $table->text('additional_instructions')->nullable();
            $table->date('work_start_date')->nullable();
        });

        Schema::create('job_notifications', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->foreignId('construction_job_id')->constrained()->cascadeOnDelete();
            $table->string('notification_type', 40);
            $table->timestamp('sent_at')->nullable();
            $table->timestamp('read_at')->nullable();
            $table->timestamps();
            $table->unique(
                ['user_id', 'construction_job_id', 'notification_type'],
                'job_notifications_unique_delivery',
            );
            $table->index(['user_id', 'read_at', 'created_at']);
        });

        foreach (self::CATEGORIES as $slug => $name) {
            DB::table('job_portal_categories')->updateOrInsert(
                ['slug' => $slug],
                [
                    'name' => $name,
                    'is_active' => true,
                    'created_at' => now(),
                    'updated_at' => now(),
                ],
            );
        }
        DB::table('job_portal_categories')
            ->where('slug', 'other')
            ->update(['slug' => 'other-construction-jobs', 'name' => 'Other Construction Jobs']);
    }

    public function down(): void
    {
        DB::table('job_portal_categories')
            ->whereIn('slug', array_keys(self::CATEGORIES))
            ->delete();
        DB::table('job_portal_categories')
            ->where('slug', 'other-construction-jobs')
            ->update(['slug' => 'other', 'name' => 'Other']);

        Schema::dropIfExists('job_notifications');
        Schema::table('construction_jobs', function (Blueprint $table) {
            $table->dropColumn([
                'other_category_description',
                'contact_preference',
                'additional_instructions',
                'work_start_date',
            ]);
        });
        Schema::table('job_seeker_profiles', function (Blueprint $table) {
            $table->dropColumn([
                'preferred_categories',
                'preferred_employment_types',
                'preferred_radius_km',
                'expected_salary',
                'available_from',
                'notifications_enabled',
            ]);
        });
    }
};
