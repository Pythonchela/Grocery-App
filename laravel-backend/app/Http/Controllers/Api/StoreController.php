<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Seller;
use App\Services\Audit;
use App\Services\Delivery\ShipmentBooker;
use App\Support\StoreMode;
use Illuminate\Http\Request;

/**
 * The store itself: what the apps need to know about it (public), and the
 * profile the owner keeps (staff).
 *
 * This is a single-business installation, so there is exactly one shop: the
 * owner's own. It is kept as a record in the `sellers` table (the "house" row)
 * because stock, orders and delivery pickup are all tied to it, but nothing here
 * or in the apps presents it as one of several shops.
 */
class StoreController extends Controller
{
    /** What the apps need to know, as the public config endpoint returns it. */
    public function config()
    {
        return response()->json(['status' => 'success', 'data' => StoreMode::publicConfig()]);
    }

    /** The store's own profile: opening hours, pickup address, minimum order, delivery area. */
    public function show()
    {
        return response()->json(['status' => 'success', 'data' => $this->payload(Seller::house())]);
    }

    public function update(Request $request)
    {
        $validated = $request->validate([
            'display_name' => 'sometimes|string|max:120',
            'legal_name' => 'nullable|string|max:200',
            'support_email' => 'nullable|email|max:150',
            'support_phone' => 'nullable|string|max:20',
            // "Back in 90 minutes": sets a timed pause. 0 reopens the shop now.
            'pause_minutes' => 'nullable|integer|min:0|max:10080',
        ] + Seller::pickupRules() + Seller::shopRules());

        $store = Seller::house();

        if (array_key_exists('pause_minutes', $validated)) {
            $minutes = (int) $validated['pause_minutes'];
            $validated['paused_until'] = $minutes > 0 ? now()->addMinutes($minutes) : null;
            if ($minutes === 0) {
                $validated['accepting_orders'] = true;
            }
        }
        unset($validated['pause_minutes']);

        $store->update(Seller::cleanShopFields($validated));

        Audit::record($request->user(), 'store.profile_changed', $store, 'Changed the store profile', array_keys($validated));

        return response()->json(['status' => 'success', 'data' => $this->payload($store->fresh())]);
    }

    private function payload(Seller $store): array
    {
        return [
            'id' => $store->id,
            'display_name' => $store->display_name,
            'slug' => $store->slug,
            'legal_name' => $store->legal_name,
            'support_email' => $store->support_email,
            'support_phone' => $store->support_phone,
            'status' => $store->status,
            'product_count' => $store->products()->count(),
            // Whether "ship" books the courier itself or asks for a courier and tracking number.
            'auto_book' => ShipmentBooker::automatic(),
        ] + $store->pickupFields() + $store->shopFields();
    }
}
