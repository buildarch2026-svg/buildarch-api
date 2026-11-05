<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('project_messages', function (Blueprint $table) {
            $table->foreignId('reply_to_message_id')
                ->nullable()
                ->constrained('project_messages')
                ->nullOnDelete();
            $table->timestamp('edited_at')->nullable();
            $table->timestamp('deleted_at')->nullable();
            $table->decimal('location_latitude', 10, 7)->nullable();
            $table->decimal('location_longitude', 10, 7)->nullable();
            $table->string('location_address')->nullable();
        });

        Schema::table('project_group_messages', function (Blueprint $table) {
            $table->foreignId('reply_to_message_id')
                ->nullable()
                ->constrained('project_group_messages')
                ->nullOnDelete();
            $table->timestamp('edited_at')->nullable();
            $table->timestamp('deleted_at')->nullable();
            $table->decimal('location_latitude', 10, 7)->nullable();
            $table->decimal('location_longitude', 10, 7)->nullable();
            $table->string('location_address')->nullable();
        });

        Schema::create('project_chat_reads', function (Blueprint $table) {
            $table->id();
            $table->foreignId('project_id')->constrained()->cascadeOnDelete();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->string('conversation_type', 16);
            $table->unsignedBigInteger('conversation_id');
            $table->unsignedBigInteger('last_read_message_id')->default(0);
            $table->timestamps();
            $table->unique([
                'project_id',
                'user_id',
                'conversation_type',
                'conversation_id',
            ], 'project_chat_reads_unique');
            $table->index(['user_id', 'project_id', 'conversation_type']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('project_chat_reads');

        Schema::table('project_group_messages', function (Blueprint $table) {
            $table->dropForeign(['reply_to_message_id']);
            $table->dropColumn([
                'reply_to_message_id',
                'edited_at',
                'deleted_at',
                'location_latitude',
                'location_longitude',
                'location_address',
            ]);
        });

        Schema::table('project_messages', function (Blueprint $table) {
            $table->dropForeign(['reply_to_message_id']);
            $table->dropColumn([
                'reply_to_message_id',
                'edited_at',
                'deleted_at',
                'location_latitude',
                'location_longitude',
                'location_address',
            ]);
        });
    }
};
