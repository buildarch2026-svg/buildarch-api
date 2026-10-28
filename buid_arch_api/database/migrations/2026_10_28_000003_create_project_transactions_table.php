<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('project_transactions', function (Blueprint $table) {
            $table->id();
            $table->foreignId('project_id')->constrained()->cascadeOnDelete();
            $table->foreignId('payer_user_id')->constrained('users')->cascadeOnDelete();
            $table->string('payee_name');
            $table->string('payee_type')->default('shop');
            $table->decimal('amount', 12, 2);
            $table->string('currency', 3)->default('INR');
            $table->string('status')->default('completed');
            $table->string('payment_method')->default('manual');
            $table->string('payment_type')->default('manual');
            $table->text('description')->nullable();
            $table->string('category')->nullable();
            $table->string('provider_reference')->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('project_transactions');
    }
};
