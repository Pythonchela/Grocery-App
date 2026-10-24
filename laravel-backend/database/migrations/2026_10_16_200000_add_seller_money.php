<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // What the platform deducts on a sale besides its commission. The rates are
        // admin settings (zero until set) and are snapshotted on the line, like the
        // commission rate, so changing them never rewrites history.
        Schema::table('order_items', function (Blueprint $table) {
            $table->decimal('gst_on_commission', 10, 2)->default(0);
            $table->decimal('tcs', 10, 2)->default(0);
            $table->decimal('tds', 10, 2)->default(0);
        });

        Schema::table('seller_ledger_entries', function (Blueprint $table) {
            $table->decimal('gst', 12, 2)->default(0);
            $table->decimal('tcs', 12, 2)->default(0);
            $table->decimal('tds', 12, 2)->default(0);
        });

        // A seller asks to be paid; staff pay it (recording the bank reference) or decline.
        Schema::create('payout_requests', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('seller_id')->constrained()->cascadeOnDelete();
            $table->decimal('amount', 12, 2);
            $table->string('status', 12)->default('REQUESTED')->index();
            $table->string('note', 300)->nullable();
            $table->string('decision_note', 300)->nullable();
            $table->string('reference', 120)->nullable();
            $table->uuid('ledger_entry_id')->nullable();
            $table->timestamp('requested_at')->nullable();
            $table->timestamp('decided_at')->nullable();
            $table->timestamps();
        });

        // New bank details waiting for staff to confirm. The account being paid
        // never changes on a seller's word alone.
        Schema::table('seller_kyc_profiles', function (Blueprint $table) {
            $table->text('pending_bank')->nullable();
            $table->timestamp('pending_bank_at')->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('seller_kyc_profiles', fn (Blueprint $table) => $table->dropColumn(['pending_bank', 'pending_bank_at']));
        Schema::dropIfExists('payout_requests');
        Schema::table('seller_ledger_entries', fn (Blueprint $table) => $table->dropColumn(['gst', 'tcs', 'tds']));
        Schema::table('order_items', fn (Blueprint $table) => $table->dropColumn(['gst_on_commission', 'tcs', 'tds']));
    }
};
