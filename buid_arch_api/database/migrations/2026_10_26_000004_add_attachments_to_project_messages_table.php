<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('project_messages', function (Blueprint $table) {
            $table->string('message_type')->default('text')->after('body');
            $table->string('attachment_path')->nullable()->unique()->after('message_type');
            $table->string('attachment_name')->nullable()->after('attachment_path');
            $table->string('attachment_mime_type')->nullable()->after('attachment_name');
            $table->unsignedBigInteger('attachment_size')->nullable()->after('attachment_mime_type');
        });

        Schema::table('project_messages', function (Blueprint $table) {
            $table->text('body')->nullable()->change();
        });
    }

    public function down(): void
    {
        Schema::table('project_messages', function (Blueprint $table) {
            $table->dropUnique(['attachment_path']);
            $table->dropColumn([
                'message_type',
                'attachment_path',
                'attachment_name',
                'attachment_mime_type',
                'attachment_size',
            ]);
            $table->text('body')->nullable(false)->change();
        });
    }
};
