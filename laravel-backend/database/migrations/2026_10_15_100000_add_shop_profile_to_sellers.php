<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('sellers', function (Blueprint $table) {
            // How a shop presents itself to shoppers browsing shops.
            $table->string('logo_url', 2048)->nullable();
            $table->string('banner_url', 2048)->nullable();
            $table->string('tagline', 120)->nullable();
            $table->text('about')->nullable();

            // {"mon": {"open": "09:00", "close": "21:00"}, "tue": null, ...}.
            // A day set to null (or left out) is closed; no hours at all means
            // always open, which is what every shop was before this existed.
            $table->json('opening_hours')->nullable();

            // The shop's own "pause orders" switch, on top of its hours.
            $table->boolean('accepting_orders')->default(true);

            // Smallest basket the shop will deliver; 0 means no minimum.
            $table->decimal('min_order_amount', 10, 2)->default(0);

            // PIN codes the shop delivers to; empty means "wherever a courier can go".
            $table->json('service_pincodes')->nullable();

            // Typical minutes to get an order ready, shown on the shop card.
            $table->unsignedSmallInteger('prep_minutes')->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('sellers', function (Blueprint $table) {
            $table->dropColumn([
                'logo_url', 'banner_url', 'tagline', 'about', 'opening_hours',
                'accepting_orders', 'min_order_amount', 'service_pincodes', 'prep_minutes',
            ]);
        });
    }
};
