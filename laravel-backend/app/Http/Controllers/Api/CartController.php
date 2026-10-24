<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\Pricing\CartPricingService;
use Illuminate\Http\Request;

/**
 * Current prices and availability for whatever is in someone's cart.
 *
 * The cart lives in the browser's localStorage and holds a snapshot of each
 * product taken at the moment it was added — including its price. That snapshot
 * goes stale the first time a price changes or an item sells out, and the
 * shopper carried on seeing the old number right up until checkout re-priced
 * everything underneath them. This is what the cart reconciles against.
 */
class CartController extends Controller
{
    public function price(Request $request, CartPricingService $pricing)
    {
        $validated = $request->validate([
            'items' => 'required|array|min:1|max:100',
            'items.*.product_id' => 'required|uuid',
            'items.*.variant_id' => 'nullable|uuid',
            'items.*.quantity' => 'required|integer|min:1',
            // What the shopper picked: {group_key: [choice ids] | number}.
            'items.*.options' => 'nullable|array',
        ]);

        return response()->json([
            'status' => 'success',
            'data' => ['items' => $pricing->inspect($validated['items'])],
        ]);
    }
}
