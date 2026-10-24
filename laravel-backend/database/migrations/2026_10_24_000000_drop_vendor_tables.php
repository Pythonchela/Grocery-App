<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\Schema;

/**
 * This is a single-business installation: nobody applies to sell, nobody is paid
 * out, nobody asks for a category. The tables that only that needed go.
 *
 * `sellers` stays: it holds the store's own record (profile, pickup address),
 * which stock and orders are tied to.
 */
return new class extends Migration
{
    public function up(): void
    {
        foreach (['payout_requests', 'seller_ledger_entries', 'seller_documents', 'seller_kyc_profiles', 'category_requests'] as $table) {
            Schema::dropIfExists($table);
        }
    }

    public function down(): void
    {
        // Not restorable: the data was vendors' and there are none.
    }
};
