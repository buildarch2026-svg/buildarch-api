<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('project_transactions', function (Blueprint $table) {
            $table->string('payee_vpa')->nullable()->after('payee_type');
            $table->string('attempt_id')->nullable()->unique()->after('provider_reference');
            $table->text('qr_payload')->nullable()->after('attempt_id');
        });
    }

    public function down(): void
    {
        Schema::table('project_transactions', function (Blueprint $table) {
            $table->dropUnique(['attempt_id']);
            $table->dropColumn(['payee_vpa', 'attempt_id', 'qr_payload']);
        });
    }
};
