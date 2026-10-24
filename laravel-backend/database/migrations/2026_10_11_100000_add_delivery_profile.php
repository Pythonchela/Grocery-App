<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * How an item travels, and how long it takes to get ready.
 *
 * A pizza must never be offered "Standard delivery, 3 days", and a sofa must
 * never be offered a rider. Until now the only inputs were weight and distance,
 * which can't tell the two apart. A category sets the default; a product can
 * override it. NULL means "work it out from weight and distance", as before.
 */
return new class extends Migration
{
    public function up(): void
    {
        foreach (['categories', 'products'] as $table) {
            Schema::table($table, function (Blueprint $t) {
                // 'instant' | 'parcel' | 'heavy'
                $t->string('delivery_profile', 12)->nullable();
                // Minutes to prepare or pack before a courier can take it.
                $t->unsignedSmallInteger('prep_minutes')->nullable();
            });
        }
    }

    public function down(): void
    {
        foreach (['categories', 'products'] as $table) {
            Schema::table($table, fn (Blueprint $t) => $t->dropColumn(['delivery_profile', 'prep_minutes']));
        }
    }
};
