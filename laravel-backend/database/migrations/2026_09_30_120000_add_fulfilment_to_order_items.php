<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Fulfilment per item, not just per order.
 *
 * An order can hold lines from several sellers, and each of them packs and ships
 * their own parcel. A single `orders.status` cannot say "one seller has shipped,
 * another has not", so the state lives on the line, and the order's status is
 * rolled up from its lines (see App\Services\FulfilmentService).
 *
 * `courier` and `tracking_no` are what the *seller* handed the parcel to, so the
 * customer can follow each parcel of a split order separately.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('order_items', function (Blueprint $table) {
            // PENDING (not yet packed), PACKED, SHIPPED
            $table->string('fulfilment_status')->default('PENDING')->after('seller_earning');
            $table->timestamp('packed_at')->nullable()->after('fulfilment_status');
            $table->timestamp('shipped_at')->nullable()->after('packed_at');
            $table->string('courier')->nullable()->after('shipped_at');
            $table->string('tracking_no')->nullable()->after('courier');

            $table->index('fulfilment_status');
        });

        // Orders that were already moving before this existed: their lines have
        // to say so, or a seller's "to pack" list would fill up with parcels
        // that left weeks ago.
        DB::table('order_items')
            ->whereIn('order_id', DB::table('orders')->whereIn('status', ['SHIPPED', 'OUT_FOR_DELIVERY', 'DELIVERED'])->select('id'))
            ->update(['fulfilment_status' => 'SHIPPED']);

        DB::table('order_items')
            ->whereIn('order_id', DB::table('orders')->where('status', 'PACKED')->select('id'))
            ->update(['fulfilment_status' => 'PACKED']);
    }

    public function down(): void
    {
        Schema::table('order_items', function (Blueprint $table) {
            $table->dropIndex(['fulfilment_status']);
            $table->dropColumn(['fulfilment_status', 'packed_at', 'shipped_at', 'courier', 'tracking_no']);
        });
    }
};
