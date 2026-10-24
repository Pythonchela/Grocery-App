<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\ProductVariant;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * Set stock levels without touching anything else about a product.
 *
 * The product form replaces a product's whole variant list, which is the wrong
 * tool for "we received a delivery". This changes the stock number and nothing
 * else, for many variants at once, and applies all of it or none of it.
 */
class InventoryController extends Controller
{
    public function update(Request $request)
    {
        $validated = $request->validate([
            'items' => 'required|array|min:1|max:200',
            'items.*.variant_id' => 'required|uuid|distinct|exists:product_variants,id',
            'items.*.stock' => 'required|integer|min:0|max:1000000',
        ]);

        $user = $request->user();
        $stockById = collect($validated['items'])->pluck('stock', 'variant_id');

        $variants = ProductVariant::with('product:id,seller_id')
            ->whereIn('id', $stockById->keys())
            ->get();

        // All-or-nothing authorisation: one variant that is not theirs refuses the
        // whole request, so a partial write can never leave a stock count half
        // updated. The same 403 is used whether the variant belongs to someone
        // else or does not exist for them.
        if (! $user->isAdmin()) {
            $sellerId = $user->seller?->id;

            foreach ($variants as $variant) {
                if (! $sellerId || $variant->product?->seller_id !== $sellerId) {
                    return response()->json([
                        'status' => 'error',
                        'message' => 'Forbidden — one of these products belongs to another seller.',
                    ], 403);
                }
            }
        }

        DB::transaction(function () use ($variants, $stockById) {
            foreach ($variants as $variant) {
                $variant->update(['stock' => $stockById[$variant->id]]);
            }
        });

        return response()->json([
            'status' => 'success',
            'data' => $variants->map(fn (ProductVariant $v) => [
                'variant_id' => $v->id,
                'product_id' => $v->product_id,
                'stock' => (int) $v->stock,
            ])->values(),
        ]);
    }
}
