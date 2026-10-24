<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Two gaps that both let money move on the customer's word rather than ours.
 *
 * `order_items.discount_allocated` records each line's share of the order-level
 * discount at purchase time, so a partial return refunds what was actually paid
 * instead of the list price.
 *
 * `payment_intents` is the server-issued record a non-COD checkout must present.
 * Without it the only evidence an order was paid for was a transaction id the
 * client made up.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('order_items', function (Blueprint $table) {
            $table->decimal('discount_allocated', 10, 2)->default(0)->after('mrp');
        });

        Schema::create('payment_intents', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('user_id');
            $table->string('provider_intent_id')->unique();
            $table->string('provider')->default('mock');

            // Paise, not rupees: the amount is compared for exact equality
            // against the recomputed total, and float equality is not a thing
            // you want standing between a shopper and their order.
            $table->unsignedBigInteger('amount_paise');

            // The exact cart this quote was issued for. A fingerprint mismatch
            // at checkout means the basket changed after the price was quoted.
            $table->string('cart_fingerprint', 64);

            $table->string('status')->default('CREATED'); // CREATED, CONSUMED, EXPIRED
            $table->uuid('order_id')->nullable();
            $table->timestamp('expires_at');
            $table->timestamps();

            $table->foreign('user_id')->references('id')->on('users')->onDelete('cascade');
            $table->index(['user_id', 'status']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('payment_intents');

        Schema::table('order_items', function (Blueprint $table) {
            $table->dropColumn('discount_allocated');
        });
    }
};
