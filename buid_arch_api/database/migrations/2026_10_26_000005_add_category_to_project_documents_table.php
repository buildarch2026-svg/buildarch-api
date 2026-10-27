<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('project_documents', function (Blueprint $table) {
            $table->string('category')->default('general')->after('size');
        });

        DB::table('project_documents')
            ->join('project_members', function ($join) {
                $join->on('project_members.project_id', '=', 'project_documents.project_id')
                    ->on('project_members.user_id', '=', 'project_documents.uploaded_by_user_id');
            })
            ->where('project_members.role', 'designer')
            ->update(['project_documents.category' => 'drawings']);
    }

    public function down(): void
    {
        Schema::table('project_documents', function (Blueprint $table) {
            $table->dropColumn('category');
        });
    }
};
