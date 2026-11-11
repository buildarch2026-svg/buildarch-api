<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('community_profiles', function (Blueprint $table) {
            $table->boolean('is_phone_visible')->default(false);
        });
    }

    public function down(): void
    {
        Schema::table('community_profiles', function (Blueprint $table) {
            $table->dropColumn('is_phone_visible');
        });
    }
};
