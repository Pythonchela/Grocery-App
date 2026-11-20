<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * What shoppers choose between for products in a category: what the two choices are called
 * (Size and Colour for clothes and shoes, Storage and Colour for phones, Pack and Flavour
 * for food) and the values to offer, so adding a product is picking from a short list
 * instead of typing every size again.
 *
 * Nullable and additive: a category with nothing set behaves exactly as before.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('categories', function (Blueprint $table) {
            $table->json('variant_setup')->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('categories', fn (Blueprint $t) => $t->dropColumn('variant_setup'));
    }
};
