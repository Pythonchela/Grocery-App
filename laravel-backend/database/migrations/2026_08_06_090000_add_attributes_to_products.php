<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Structured, per-category product attributes.
     *
     * Categories already carry a `filter_config` describing the filter groups
     * that make sense for that product type (a laptop filters by RAM and
     * processor; a saree by fabric and occasion). But products had nowhere to
     * store a value *against* those groups, so filtering fell back to guessing:
     * it string-matched the selected filter value against the product's free-text
     * tags and its variant colour/size. That silently mis-filters in both
     * directions — a "cotton" filter matches a product tagged "cotton-blend
     * lookalike", and misses one whose fabric is only stated in the description.
     *
     * `attributes` is a JSON object keyed by the category's own filter group ids
     * — {"fabric": "cotton", "occasion": ["festive", "party"]} — so a filter
     * group queries the exact field it was defined for. Scalars for single-value
     * groups (radio), arrays for multi-select (checkbox/chip).
     *
     * Nullable, and no rule anywhere implies a requirement: every existing
     * product stays valid and sellable with this never set, and the old
     * tag/variant matching is kept as a fallback for exactly those rows.
     */
    public function up(): void
    {
        Schema::table('products', function (Blueprint $table) {
            $table->json('attributes')->nullable()->after('features');
        });

        // Postgres can only index inside JSON with a GIN index; without one,
        // every attribute filter degrades to a full table scan once the catalog
        // grows. jsonb_path_ops is the smaller/faster variant and covers the
        // containment (@>) queries the filter actually issues.
        if (DB::getDriverName() === 'pgsql') {
            DB::statement('CREATE INDEX products_attributes_idx ON products USING GIN ((attributes::jsonb) jsonb_path_ops)');
        }
    }

    public function down(): void
    {
        if (DB::getDriverName() === 'pgsql') {
            DB::statement('DROP INDEX IF EXISTS products_attributes_idx');
        }

        Schema::table('products', function (Blueprint $table) {
            $table->dropColumn('attributes');
        });
    }
};
