<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('project_group_messages', function (Blueprint $table) {
            $table->string('attachment_path')->nullable()->change();
            $table->string('attachment_name')->nullable()->change();
            $table->unsignedBigInteger('attachment_size')->nullable()->change();
            $table->text('body')->nullable()->after('sender_user_id');
            $table->string('message_type')->default('voice')->after('body');
        });
    }

    public function down(): void
    {
        Schema::table('project_group_messages', function (Blueprint $table) {
            $table->dropColumn(['body', 'message_type']);
            $table->string('attachment_path')->nullable(false)->change();
            $table->string('attachment_name')->nullable(false)->change();
            $table->unsignedBigInteger('attachment_size')->nullable(false)->change();
        });
    }
};
