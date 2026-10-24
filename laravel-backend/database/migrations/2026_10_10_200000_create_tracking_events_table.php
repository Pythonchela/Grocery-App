<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The shipment's own history - "Reached Mumbai hub", "Out for delivery" - kept
 * in one shape no matter which delivery partner reported it, whether by webhook
 * or by us polling their API.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('tracking_events', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('order_id')->constrained()->cascadeOnDelete();
            $table->string('carrier', 40)->nullable();
            $table->string('tracking_no', 80)->nullable();

            // Our vocabulary (TrackingStatus), and the partner's own words.
            $table->string('status', 30);
            $table->string('description', 255)->nullable();
            $table->string('location', 160)->nullable();
            $table->decimal('lat', 10, 7)->nullable();
            $table->decimal('lng', 10, 7)->nullable();
            $table->timestamp('occurred_at');

            // 'poll' | 'webhook' | 'system'. Tells you where a surprising event came from.
            $table->string('source', 12)->default('poll');
            $table->json('raw')->nullable();

            // Same scan reported twice (webhook then poll) must not appear twice.
            $table->string('fingerprint', 40);
            $table->timestamps();

            $table->unique(['order_id', 'fingerprint']);
            $table->index(['order_id', 'occurred_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('tracking_events');
    }
};
