<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('orders', function (Blueprint $table) {
            // Why an order was cancelled as a code (reportable), next to the free-text reason.
            $table->string('cancellation_code', 24)->nullable()->index();
            // Who cancelled it: CUSTOMER, ADMIN, SELLER or SYSTEM.
            $table->string('cancelled_by', 10)->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('orders', function (Blueprint $table) {
            $table->dropIndex(['cancellation_code']);
            $table->dropColumn(['cancellation_code', 'cancelled_by']);
        });
    }
};
