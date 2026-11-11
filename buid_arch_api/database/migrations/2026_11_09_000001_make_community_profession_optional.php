<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('community_profiles', function (Blueprint $table) {
            $table->string('profession', 40)->nullable()->change();
            $table->string('location')->nullable();
        });
    }

    public function down(): void
    {
        DB::table('community_profiles')
            ->whereNull('profession')
            ->update(['profession' => 'Other']);

        Schema::table('community_profiles', function (Blueprint $table) {
            $table->dropColumn('location');
            $table->string('profession', 40)->nullable(false)->change();
        });
    }
};
