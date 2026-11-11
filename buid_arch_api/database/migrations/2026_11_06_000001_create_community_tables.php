<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    private const CATEGORIES = [
        'general-discussion' => 'General Discussion',
        'construction' => 'Construction',
        'architecture-design' => 'Architecture & Design',
        'interior-design' => 'Interior Design',
        'materials-products' => 'Materials & Products',
        'budget-cost' => 'Budget & Cost',
        'questions-doubts' => 'Questions & Doubts',
        'tips-experiences' => 'Tips & Experiences',
    ];

    public function up(): void
    {
        Schema::create('community_categories', function (Blueprint $table) {
            $table->id();
            $table->string('slug')->unique();
            $table->string('name')->unique();
            $table->timestamps();
        });

        foreach (self::CATEGORIES as $slug => $name) {
            DB::table('community_categories')->insert([
                'slug' => $slug,
                'name' => $name,
                'created_at' => now(),
                'updated_at' => now(),
            ]);
        }

        Schema::create('community_profiles', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->unique()->constrained()->cascadeOnDelete();
            $table->string('display_name', 80);
            $table->string('profession', 40);
            $table->string('other_profession', 80)->nullable();
            $table->string('bio', 500)->nullable();
            $table->string('profile_image_path')->nullable();
            $table->timestamp('guidelines_accepted_at');
            $table->timestamps();
        });

        Schema::create('community_posts', function (Blueprint $table) {
            $table->id();
            $table->foreignId('community_profile_id')->constrained()->cascadeOnDelete();
            $table->foreignId('community_category_id')->nullable()->constrained()->nullOnDelete();
            $table->text('content');
            $table->string('image_path')->nullable();
            $table->string('status', 20)->default('published')->index();
            $table->timestamps();
            $table->softDeletes();
            $table->index(['status', 'created_at']);
        });

        Schema::create('community_comments', function (Blueprint $table) {
            $table->id();
            $table->foreignId('community_post_id')->constrained()->cascadeOnDelete();
            $table->foreignId('community_profile_id')->constrained()->cascadeOnDelete();
            $table->foreignId('parent_comment_id')->nullable()
                ->constrained('community_comments')->nullOnDelete();
            $table->text('content');
            $table->timestamps();
            $table->softDeletes();
            $table->index(['community_post_id', 'created_at']);
        });

        Schema::create('community_likes', function (Blueprint $table) {
            $table->id();
            $table->foreignId('community_post_id')->constrained()->cascadeOnDelete();
            $table->foreignId('community_profile_id')->constrained()->cascadeOnDelete();
            $table->timestamps();
            $table->unique(['community_post_id', 'community_profile_id']);
        });

        Schema::create('community_reports', function (Blueprint $table) {
            $table->id();
            $table->foreignId('reporter_profile_id')
                ->constrained('community_profiles')->cascadeOnDelete();
            $table->string('target_type', 20);
            $table->unsignedBigInteger('target_id');
            $table->string('reason', 40);
            $table->string('details', 500)->nullable();
            $table->string('status', 20)->default('open')->index();
            $table->foreignId('reviewed_by_user_id')->nullable()
                ->constrained('users')->nullOnDelete();
            $table->timestamp('reviewed_at')->nullable();
            $table->timestamps();
            $table->unique(
                ['reporter_profile_id', 'target_type', 'target_id'],
                'community_reports_reporter_target_unique',
            );
            $table->index(['target_type', 'target_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('community_reports');
        Schema::dropIfExists('community_likes');
        Schema::dropIfExists('community_comments');
        Schema::dropIfExists('community_posts');
        Schema::dropIfExists('community_profiles');
        Schema::dropIfExists('community_categories');
    }
};
