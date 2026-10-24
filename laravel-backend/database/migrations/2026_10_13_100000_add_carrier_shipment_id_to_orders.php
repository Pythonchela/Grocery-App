<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('orders', function (Blueprint $table) {
            // The carrier's own id for the shipment it created for this order.
            // Booking is several calls (create, assign courier, pickup, label);
            // remembering this after the first lets a retry carry on from where
            // it stopped instead of creating a second shipment and paying twice.
            $table->string('carrier_shipment_id', 80)->nullable()->after('tracking_no');
        });
    }

    public function down(): void
    {
        Schema::table('orders', function (Blueprint $table) {
            $table->dropColumn('carrier_shipment_id');
        });
    }
};
