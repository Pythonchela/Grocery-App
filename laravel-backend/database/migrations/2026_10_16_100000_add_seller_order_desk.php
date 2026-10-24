<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('order_items', function (Blueprint $table) {
            // Whether the shop has taken the line on. Every line that existed
            // before this feature was, in effect, accepted — hence the default;
            // checkout writes PENDING for a shop that wants to confirm each order.
            $table->string('seller_response', 12)->default('ACCEPTED')->index();
            $table->timestamp('accept_by')->nullable();
            $table->timestamp('accepted_at')->nullable();
            $table->unsignedSmallInteger('prep_minutes')->nullable();
            $table->timestamp('ready_by')->nullable();

            $table->timestamp('rejected_at')->nullable();
            $table->string('rejection_reason', 24)->nullable();
            $table->string('rejection_note', 300)->nullable();
            $table->string('rejected_by', 10)->nullable();
        });

        Schema::table('sellers', function (Blueprint $table) {
            // true: orders are taken automatically (the behaviour every shop had).
            // false: the shop must accept each order before packing it.
            $table->boolean('auto_accept')->default(true);
            // "Back at 6pm": the shop is closed until then, with no need to remember to reopen.
            $table->timestamp('paused_until')->nullable();
        });

        Schema::table('products', function (Blueprint $table) {
            // An item switched off for the day comes back by itself.
            $table->timestamp('available_again_at')->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('order_items', function (Blueprint $table) {
            $table->dropIndex(['seller_response']);
            $table->dropColumn([
                'seller_response', 'accept_by', 'accepted_at', 'prep_minutes', 'ready_by',
                'rejected_at', 'rejection_reason', 'rejection_note', 'rejected_by',
            ]);
        });

        Schema::table('sellers', fn (Blueprint $table) => $table->dropColumn(['auto_accept', 'paused_until']));
        Schema::table('products', fn (Blueprint $table) => $table->dropColumn('available_again_at'));
    }
};
