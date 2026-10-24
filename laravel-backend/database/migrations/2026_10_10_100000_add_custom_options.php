<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Custom selection options (portion, add-ons, colour swatches, quantity...).
 *
 *  - categories.option_groups: the template every product in the category starts from.
 *  - products.custom_options:  null = use the category's template; an array (even
 *                              an empty one) = this product's own list.
 *  - product_variants.color_hex: a swatch colour for the variant's colour name.
 *  - order_items.selected_options: what the shopper picked, frozen at purchase.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('categories', function (Blueprint $table) {
            $table->json('option_groups')->nullable();
        });

        Schema::table('products', function (Blueprint $table) {
            $table->json('custom_options')->nullable();
        });

        Schema::table('product_variants', function (Blueprint $table) {
            $table->string('color_hex', 9)->nullable()->after('color');
        });

        Schema::table('order_items', function (Blueprint $table) {
            $table->json('selected_options')->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('order_items', fn (Blueprint $t) => $t->dropColumn('selected_options'));
        Schema::table('product_variants', fn (Blueprint $t) => $t->dropColumn('color_hex'));
        Schema::table('products', fn (Blueprint $t) => $t->dropColumn('custom_options'));
        Schema::table('categories', fn (Blueprint $t) => $t->dropColumn('option_groups'));
    }
};
