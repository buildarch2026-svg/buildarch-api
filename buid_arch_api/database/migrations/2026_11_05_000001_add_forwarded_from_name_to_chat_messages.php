<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('project_messages', function (Blueprint $table) {
            $table->string('forwarded_from_name')->nullable();
        });

        Schema::table('project_group_messages', function (Blueprint $table) {
            $table->string('forwarded_from_name')->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('project_group_messages', function (Blueprint $table) {
            $table->dropColumn('forwarded_from_name');
        });

        Schema::table('project_messages', function (Blueprint $table) {
            $table->dropColumn('forwarded_from_name');
        });
    }
};
