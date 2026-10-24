<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The platform's own record of money in and money out.
 *
 * Until now the only trace of a payment was `orders.transaction_id`, and a
 * refund left no trace at all — the gateway's answer was thrown away. That made
 * three things impossible: refunding through the gateway that actually took the
 * money (the app assumed there was only ever one), knowing how much of a payment
 * was already refunded, and seeing a refund that the gateway had accepted but
 * not yet paid out.
 *
 * `provider` is a plain string on purpose. Adding a gateway is a new driver
 * class, never a schema change.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('payments', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('order_id')->nullable();
            $table->uuid('user_id');
            $table->uuid('payment_intent_id')->nullable();

            $table->string('provider');
            $table->string('provider_order_id')->nullable();
            $table->string('provider_payment_id');
            $table->string('method')->nullable();

            // Paise throughout: exact integers, no float equality.
            $table->unsignedBigInteger('amount_paise');
            $table->unsignedBigInteger('refunded_paise')->default(0);
            $table->string('currency', 3)->default('INR');

            // CAPTURED, PARTIALLY_REFUNDED, REFUNDED
            $table->string('status')->default('CAPTURED');
            $table->timestamp('captured_at')->nullable();
            $table->json('meta')->nullable();
            $table->timestamps();

            // A gateway payment id is unique within that gateway. This is also
            // what makes the checkout call and the webhook safe to race: whoever
            // arrives second finds the row and attaches to it.
            $table->unique(['provider', 'provider_payment_id']);
            $table->index('order_id');
            $table->index('payment_intent_id');
            $table->foreign('user_id')->references('id')->on('users')->onDelete('cascade');
        });

        Schema::create('refunds', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('payment_id')->nullable(); // null for wallet refunds
            $table->uuid('order_id')->nullable();
            $table->uuid('return_request_id')->nullable();

            // SOURCE goes back through the gateway; WALLET is store credit.
            $table->string('destination');
            $table->string('provider')->nullable();
            $table->string('provider_refund_id')->nullable();

            $table->unsignedBigInteger('amount_paise');
            // PENDING (gateway accepted, not yet paid out), PROCESSED, FAILED
            $table->string('status')->default('PENDING');
            $table->string('reason')->nullable();
            $table->string('failure_reason')->nullable();

            // Who asked, e.g. "return:<id>" or "cancel:<order>". Asking twice
            // returns the first answer instead of refunding twice.
            $table->string('reference');
            $table->timestamp('processed_at')->nullable();
            $table->timestamps();

            $table->unique(['reference', 'destination']);
            $table->index('order_id');
            $table->index('payment_id');
            $table->index(['provider', 'provider_refund_id']);
        });

        Schema::table('payment_intents', function (Blueprint $table) {
            // Set when a webhook learns the money arrived before the customer's
            // own checkout call did (app killed, connection dropped).
            $table->string('provider_payment_id')->nullable()->after('provider_intent_id');
            $table->timestamp('paid_at')->nullable()->after('expires_at');
        });
    }

    public function down(): void
    {
        Schema::table('payment_intents', function (Blueprint $table) {
            $table->dropColumn(['provider_payment_id', 'paid_at']);
        });

        Schema::dropIfExists('refunds');
        Schema::dropIfExists('payments');
    }
};
