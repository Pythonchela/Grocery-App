<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Where each seller's goods are collected from.
 *
 * Delivery used to assume one warehouse for everything, which made a restaurant
 * in Mumbai look as if it shipped from Bengaluru. A seller with no pickup address
 * still falls back to the platform's own (the house inventory ships from there),
 * so nothing existing changes until a seller fills theirs in.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('sellers', function (Blueprint $table) {
            $table->string('pickup_name', 120)->nullable();
            $table->string('pickup_phone', 20)->nullable();
            $table->string('pickup_line1', 200)->nullable();
            $table->string('pickup_city', 80)->nullable();
            $table->string('pickup_state', 80)->nullable();
            $table->string('pickup_pincode', 6)->nullable();
            $table->decimal('pickup_lat', 10, 7)->nullable();
            $table->decimal('pickup_lng', 10, 7)->nullable();

            // The name this pickup point is registered under in a courier's own
            // dashboard (Shiprocket and Delhivery book against a pre-registered
            // name, not an address).
            $table->string('pickup_code', 80)->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('sellers', function (Blueprint $table) {
            $table->dropColumn([
                'pickup_name', 'pickup_phone', 'pickup_line1', 'pickup_city',
                'pickup_state', 'pickup_pincode', 'pickup_lat', 'pickup_lng', 'pickup_code',
            ]);
        });
    }
};
