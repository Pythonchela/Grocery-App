<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The veg / non-veg mark food shoppers look for. NULL means "does not apply",
 * which is right for salt, soap and everything that is not food.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('products', function (Blueprint $t) {
            // 'veg' | 'non_veg' | 'egg'
            $t->string('diet', 10)->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('products', fn (Blueprint $t) => $t->dropColumn('diet'));
    }
};
