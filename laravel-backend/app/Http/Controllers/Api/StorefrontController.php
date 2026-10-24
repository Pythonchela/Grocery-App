<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\HomepageSection;
use App\Models\Setting;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class StorefrontController extends Controller
{
    /** Section list driving the homepage. Public read. */
    public function index(Request $request)
    {
        $query = HomepageSection::orderBy('sort_order');

        // The storefront only wants visible sections; the admin builder wants
        // all of them so it can toggle visibility.
        if (! $request->boolean('all')) {
            $query->where('is_visible', true);
        }

        return response()->json([
            'status' => 'success',
            'data' => $query->with('category:id,name,slug')->get(),
        ]);
    }

    public function store(Request $request)
    {
        $validated = $this->validateSection($request);
        $validated['sort_order'] = $validated['sort_order'] ?? (HomepageSection::max('sort_order') + 1);

        return response()->json([
            'status' => 'success',
            'data' => HomepageSection::create($validated),
        ], 201);
    }

    public function update(Request $request, $id)
    {
        $section = HomepageSection::find($id);
        if (! $section) {
            return response()->json(['status' => 'error', 'message' => 'Section not found'], 404);
        }

        $section->update($this->validateSection($request, false));

        return response()->json(['status' => 'success', 'data' => $section]);
    }

    public function destroy($id)
    {
        $section = HomepageSection::find($id);
        if (! $section) {
            return response()->json(['status' => 'error', 'message' => 'Section not found'], 404);
        }

        $section->delete();

        return response()->json(['status' => 'success', 'message' => 'Section deleted']);
    }

    /** Persist a whole reordering in one call after a drag-and-drop. */
    public function reorder(Request $request)
    {
        $validated = $request->validate([
            'order' => 'required|array|min:1',
            'order.*' => 'required|uuid|exists:homepage_sections,id',
        ]);

        DB::transaction(function () use ($validated) {
            foreach ($validated['order'] as $index => $id) {
                HomepageSection::whereKey($id)->update(['sort_order' => $index]);
            }
        });

        return response()->json([
            'status' => 'success',
            'data' => HomepageSection::orderBy('sort_order')->get(),
        ]);
    }

    private function validateSection(Request $request, bool $creating = true): array
    {
        return $request->validate([
            'type' => ($creating ? 'required' : 'sometimes').'|in:HERO,CATEGORY_GRID,PRODUCT_ROW,BANNER,REELS,TRUST',
            'title' => 'nullable|string|max:255',
            'subtitle' => 'nullable|string|max:255',
            'source' => 'nullable|in:trending,new,personalized,category,deals',
            'category_id' => 'nullable|uuid|exists:categories,id',
            'image_url' => 'nullable|string',
            'link_url' => 'nullable|string',
            'sort_order' => 'nullable|integer|min:0',
            'is_visible' => 'nullable|boolean',
        ]);
    }

    // ── Platform settings ────────────────────────────────────────────────

    public function settings()
    {
        return response()->json([
            'status' => 'success',
            'data' => [
                'cod_enabled' => (bool) Setting::get('cod.enabled', true),
                'cod_blocked_pincodes' => (array) Setting::get('cod.blocked_pincodes', []),
                // The threshold pricing really applies (also set under Integrations > Shipping),
                // so the apps' "add X for free delivery" can never disagree with the bill.
                'free_shipping_threshold' => (float) Setting::get('delivery.free_above', config('delivery.free_above')),
                'loyalty_earn_per_100' => (int) Setting::get('loyalty.earn_per_100', 5),
                'loyalty_redeem_value' => (float) Setting::get('loyalty.redeem_value', 0.25),
                'loyalty_max_redeem_percent' => (int) Setting::get('loyalty.max_redeem_percent', 20),
                'referral_referrer_reward' => (float) Setting::get('referral.referrer_reward', 100),
                'referral_referee_reward' => (float) Setting::get('referral.referee_reward', 50),
                'store_legal_name' => (string) Setting::get('store.legal_name', ''),
                'store_address' => (string) Setting::get('store.address', ''),
                'store_gstin' => (string) Setting::get('store.gstin', ''),
            ],
        ]);
    }

    public function updateSettings(Request $request)
    {
        $validated = $request->validate([
            'cod_enabled' => 'nullable|boolean',
            'cod_blocked_pincodes' => 'nullable|array',
            'cod_blocked_pincodes.*' => 'string|size:6',
            'free_shipping_threshold' => 'nullable|numeric|min:0',
            'loyalty_earn_per_100' => 'nullable|integer|min:0|max:100',
            'loyalty_redeem_value' => 'nullable|numeric|min:0|max:100',
            'loyalty_max_redeem_percent' => 'nullable|integer|min:0|max:100',
            'referral_referrer_reward' => 'nullable|numeric|min:0',
            'referral_referee_reward' => 'nullable|numeric|min:0',
            'store_legal_name' => 'nullable|string|max:200',
            'store_address' => 'nullable|string|max:500',
            'store_gstin' => ['nullable', 'string', 'regex:/^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][A-Z0-9][Z][A-Z0-9]$/'],
        ]);

        $map = [
            'cod_enabled' => 'cod.enabled',
            'cod_blocked_pincodes' => 'cod.blocked_pincodes',
            'free_shipping_threshold' => 'delivery.free_above',
            'loyalty_earn_per_100' => 'loyalty.earn_per_100',
            'loyalty_redeem_value' => 'loyalty.redeem_value',
            'loyalty_max_redeem_percent' => 'loyalty.max_redeem_percent',
            'referral_referrer_reward' => 'referral.referrer_reward',
            'referral_referee_reward' => 'referral.referee_reward',
            'store_legal_name' => 'store.legal_name',
            'store_address' => 'store.address',
            'store_gstin' => 'store.gstin',
        ];

        foreach ($map as $field => $key) {
            if (array_key_exists($field, $validated)) {
                Setting::put($key, $validated[$field]);
            }
        }
        \App\Services\Audit::record($request->user(), 'settings.store_rules', ['Setting', 'store'], 'Changed store rules', ['fields' => array_keys($validated)]);

        return $this->settings();
    }
}
