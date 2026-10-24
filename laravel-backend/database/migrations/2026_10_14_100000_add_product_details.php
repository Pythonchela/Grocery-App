<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('products', function (Blueprint $table) {
            // Formatted description (cleaned HTML). `description` stays as the
            // plain-text version of it, which search and simple clients read.
            $table->longText('description_html')->nullable()->after('description');
            // [{title, rows: [{label, value}]}] - the specification table.
            $table->json('specifications')->nullable()->after('features');
            // {generic_name, country_of_origin, manufacturer_name, ...}
            $table->json('manufacturer')->nullable()->after('specifications');
        });

        Schema::table('categories', function (Blueprint $table) {
            // [{title, labels: [...]}] - suggested specification rows for products in it.
            $table->json('spec_template')->nullable()->after('option_groups');
        });
    }

    public function down(): void
    {
        Schema::table('products', function (Blueprint $table) {
            $table->dropColumn(['description_html', 'specifications', 'manufacturer']);
        });
        Schema::table('categories', function (Blueprint $table) {
            $table->dropColumn('spec_template');
        });
    }
};
