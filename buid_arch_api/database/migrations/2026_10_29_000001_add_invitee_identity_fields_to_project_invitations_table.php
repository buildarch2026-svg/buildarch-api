<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (! Schema::hasColumn('project_invitations', 'invitee_name')) {
            Schema::table('project_invitations', function (Blueprint $table) {
                $table->string('invitee_name')->nullable()->after('role');
            });
        }

        if (! Schema::hasColumn('project_invitations', 'invitee_designation')) {
            Schema::table('project_invitations', function (Blueprint $table) {
                $table->string('invitee_designation')->nullable()->after('invitee_name');
            });
        }

        if (Schema::hasColumn('project_invitations', 'role') && Schema::getColumnType('project_invitations', 'role') !== 'string') {
            Schema::table('project_invitations', function (Blueprint $table) {
                $table->string('role')->nullable()->change();
            });
        }
    }

    public function down(): void
    {
        if (Schema::hasColumn('project_invitations', 'invitee_name')) {
            Schema::table('project_invitations', function (Blueprint $table) {
                $table->dropColumn('invitee_name');
            });
        }

        if (Schema::hasColumn('project_invitations', 'invitee_designation')) {
            Schema::table('project_invitations', function (Blueprint $table) {
                $table->dropColumn('invitee_designation');
            });
        }
    }
};
