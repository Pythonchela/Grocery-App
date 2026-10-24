<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('support_tickets', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('number', 20)->unique();
            // Who raised it: a shopper or a seller (seller_id set when it is raised for a shop).
            $table->foreignUuid('user_id')->constrained()->cascadeOnDelete();
            $table->uuid('seller_id')->nullable()->index();
            $table->uuid('order_id')->nullable()->index();
            $table->string('category', 24);
            $table->string('subject', 160);
            $table->string('status', 24)->default('OPEN')->index();
            $table->string('priority', 10)->default('NORMAL');
            $table->uuid('assigned_to')->nullable()->index();
            $table->timestamp('last_message_at')->nullable();
            // When the team first answered, and when it was due to. Both are read by the SLA flags.
            $table->timestamp('first_response_at')->nullable();
            $table->timestamp('sla_due_at')->nullable()->index();
            $table->timestamp('resolved_at')->nullable();
            $table->unsignedTinyInteger('rating')->nullable();
            $table->string('rating_note', 300)->nullable();
            $table->timestamps();
        });

        Schema::create('support_messages', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('ticket_id')->constrained('support_tickets')->cascadeOnDelete();
            $table->foreignUuid('user_id')->constrained()->cascadeOnDelete();
            // REQUESTER (the shopper or seller) or STAFF.
            $table->string('author', 10);
            $table->text('body');
            // A note between staff, never shown to the person who raised the ticket.
            $table->boolean('is_internal')->default(false);
            $table->timestamps();
            $table->index(['ticket_id', 'created_at']);
        });

        // Who did what to money, access and customers' orders. Append-only.
        Schema::create('audit_logs', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('actor_id')->nullable()->index();
            $table->string('actor_role', 20)->nullable();
            $table->string('action', 60)->index();
            $table->string('subject_type', 40)->nullable();
            $table->string('subject_id', 64)->nullable();
            $table->string('summary', 300);
            $table->json('meta')->nullable();
            $table->string('ip', 45)->nullable();
            $table->timestamp('created_at')->useCurrent()->index();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('audit_logs');
        Schema::dropIfExists('support_messages');
        Schema::dropIfExists('support_tickets');
    }
};
