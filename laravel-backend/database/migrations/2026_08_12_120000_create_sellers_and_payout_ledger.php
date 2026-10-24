<?php

use App\Models\Seller;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Turns a single-vendor store into an actual marketplace.
 *
 * Every product now belongs to a seller, every sold line records which seller
 * earned it and what the platform took, and a ledger tracks what each seller is
 * owed. Existing catalog is backfilled to a "house" seller — the platform's own
 * inventory — so nothing that already exists becomes ambiguous or unsellable.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('sellers', function (Blueprint $table) {
            $table->uuid('id')->primary();
            // The account that operates this seller. Null for the house seller,
            // which is the platform itself and has no separate operator.
            $table->uuid('user_id')->nullable();
            $table->string('display_name');
            $table->string('slug')->unique();
            $table->string('legal_name')->nullable();
            $table->string('support_email')->nullable();
            $table->string('support_phone')->nullable();

            // Percent of each sale the platform keeps. Snapshotted onto every
            // order line at purchase time, so renegotiating it later never
            // rewrites what a past order was worth.
            $table->decimal('commission_rate', 5, 2)->default(10.00);

            $table->string('status')->default('PENDING'); // PENDING, ACTIVE, SUSPENDED
            $table->boolean('is_house')->default(false);

            // Running total of what this seller is owed. Reconstructable from
            // the ledger, kept here so the common read is one column.
            $table->decimal('payout_balance', 12, 2)->default(0);

            $table->timestamps();

            $table->foreign('user_id')->references('id')->on('users')->onDelete('set null');
            $table->index('status');
        });

        // The platform's own inventory. Created before the backfill below,
        // because every existing product has to land somewhere.
        $houseId = (string) \Illuminate\Support\Str::uuid7();
        DB::table('sellers')->insert([
            'id' => $houseId,
            'user_id' => null,
            'display_name' => config('app.name').' Retail',
            'slug' => 'house',
            'commission_rate' => 0,
            'status' => 'ACTIVE',
            'is_house' => true,
            'payout_balance' => 0,
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        Schema::table('products', function (Blueprint $table) {
            $table->uuid('seller_id')->nullable()->after('category_id');
        });

        DB::table('products')->whereNull('seller_id')->update(['seller_id' => $houseId]);

        Schema::table('products', function (Blueprint $table) {
            // Tightened to NOT NULL once every row has an owner. "Which seller"
            // having a null answer would force every downstream query — catalog
            // filters, payout reports, the ownership check on writes — to handle
            // a second shape, and the first one to forget is the one that
            // silently drops products out of a payout.
            $table->uuid('seller_id')->nullable(false)->change();
            $table->foreign('seller_id')->references('id')->on('sellers');
            $table->index('seller_id');
        });

        Schema::table('order_items', function (Blueprint $table) {
            // Snapshots. A seller can be re-rated or removed; what a line
            // earned whom is settled at the moment of sale and never moves.
            $table->uuid('seller_id')->nullable()->after('product_id');
            $table->decimal('commission_rate', 5, 2)->default(0)->after('discount_allocated');
            $table->decimal('commission_amount', 10, 2)->default(0)->after('commission_rate');
            $table->decimal('seller_earning', 10, 2)->default(0)->after('commission_amount');

            $table->index('seller_id');
        });

        Schema::create('seller_ledger_entries', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('seller_id');
            $table->uuid('order_id')->nullable();
            $table->uuid('order_item_id')->nullable();

            $table->string('type'); // SALE, REFUND, ADJUSTMENT

            // Gross is what the customer actually paid for the line, net of its
            // share of any discount — the same figure a refund is worth.
            $table->decimal('gross', 10, 2);
            $table->decimal('commission', 10, 2)->default(0);
            // Negative on a refund. The ledger is signed so the balance is just
            // its running sum.
            $table->decimal('net', 10, 2);
            $table->decimal('balance_after', 12, 2);

            $table->string('note')->nullable();
            $table->timestamps();

            $table->foreign('seller_id')->references('id')->on('sellers')->onDelete('cascade');
            $table->index(['seller_id', 'created_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('seller_ledger_entries');

        Schema::table('order_items', function (Blueprint $table) {
            $table->dropColumn(['seller_id', 'commission_rate', 'commission_amount', 'seller_earning']);
        });

        Schema::table('products', function (Blueprint $table) {
            $table->dropForeign(['seller_id']);
            $table->dropColumn('seller_id');
        });

        Schema::dropIfExists('sellers');
    }
};
