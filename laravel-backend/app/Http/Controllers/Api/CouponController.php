<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Coupon;
use App\Models\Product;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

class CouponController extends Controller
{
    /**
     * Customer: preview a coupon against the current cart before checkout.
     *
     * Runs the same pricing code checkout runs, which is the point — when this
     * had its own arithmetic it quoted a whole-cart discount that checkout then
     * refused to honour on a product-targeted coupon.
     */
    public function preview(Request $request, \App\Services\Pricing\CartPricingService $pricing)
    {
        $validated = $request->validate([
            'code' => 'required|string',
            'items' => 'required|array|min:1',
            'items.*.product_id' => 'required|uuid|exists:products,id',
            'items.*.variant_id' => 'nullable|uuid',
            'items.*.quantity' => 'required|integer|min:1',
            // What the shopper picked: {group_key: [choice ids] | number}.
            'items.*.options' => 'nullable|array',
        ]);

        // Pricing failures (unknown code, cart doesn't qualify, item withdrawn)
        // surface as a 422 with the reason on `coupon_code`.
        $cart = $pricing->price($validated['items'], $request->user(), [
            'coupon_code' => $validated['code'],
        ]);

        return response()->json([
            'status' => 'success',
            'data' => [
                'code' => $cart->coupon->code,
                'description' => $cart->coupon->description,
                'discount' => $cart->couponDiscount,
                'subtotal' => $cart->subtotal,
            ],
        ]);
    }

    /**
     * Recompute cart totals server-side from live prices. Never trust a
     * client-sent subtotal — the discount is derived from this, not the payload.
     *
     * @return array{0: float, 1: array<string>, 2: array<string>}
     */
    public static function summariseCart(array $items): array
    {
        $productIds = array_values(array_unique(array_column($items, 'product_id')));
        $products = Product::with('variants')->whereIn('id', $productIds)->get()->keyBy('id');

        $subtotal = 0.0;
        foreach ($items as $item) {
            $product = $products->get($item['product_id']);
            if (! $product) {
                continue;
            }

            $variant = ! empty($item['variant_id'])
                ? $product->variants->firstWhere('id', $item['variant_id'])
                : $product->variants->first();

            $price = $variant ? (float) $variant->effective_price : (float) $product->price;
            $subtotal += $price * $item['quantity'];
        }

        $categoryIds = $products->pluck('category_id')->unique()->values()->all();

        return [round($subtotal, 2), $productIds, $categoryIds];
    }

    // ── Admin CRUD ───────────────────────────────────────────────────────

    public function index()
    {
        $coupons = Coupon::with('seller:id,display_name')->withCount('redemptions')->orderByDesc('created_at')->get();

        return response()->json(['status' => 'success', 'count' => $coupons->count(), 'data' => $coupons]);
    }

    public function store(Request $request)
    {
        $request->merge(['code' => strtoupper(trim((string) $request->input('code')))]);
        $validated = $request->validate($this->rules());
        $validated['code'] = strtoupper($validated['code']);

        $coupon = Coupon::create($validated);

        return response()->json(['status' => 'success', 'data' => $coupon], 201);
    }

    public function update(Request $request, $id)
    {
        $coupon = Coupon::find($id);

        if (! $coupon) {
            return response()->json(['status' => 'error', 'message' => 'Coupon not found'], 404);
        }

        if ($request->has('code')) {
            $request->merge(['code' => strtoupper(trim((string) $request->input('code')))]);
        }
        $validated = $request->validate($this->rules($coupon->id));

        if (isset($validated['code'])) {
            $validated['code'] = strtoupper($validated['code']);
        }

        $coupon->update($validated);

        return response()->json(['status' => 'success', 'data' => $coupon->fresh()]);
    }

    public function destroy($id)
    {
        $coupon = Coupon::find($id);

        if (! $coupon) {
            return response()->json(['status' => 'error', 'message' => 'Coupon not found'], 404);
        }

        $coupon->delete();

        return response()->json(['status' => 'success', 'message' => 'Coupon deleted']);
    }

    public function sellerIndex(Request $request)
    {
        $coupons = Coupon::withCount('redemptions')->where('seller_id', $request->user()->seller->id)
            ->orderByDesc('created_at')->get();

        return response()->json(['status' => 'success', 'count' => $coupons->count(), 'data' => $coupons]);
    }

    public function sellerStore(Request $request)
    {
        $request->merge(['code' => strtoupper(trim((string) $request->input('code')))]);
        $data = $request->validate($this->sellerRules());
        if ($data['type'] === 'PERCENT' && $data['value'] > 100) {
            throw ValidationException::withMessages(['value' => ['Percentage cannot exceed 100.']]);
        }
        $data['seller_id'] = $request->user()->seller->id;
        $data['target_type'] = 'ALL';

        return response()->json(['status' => 'success', 'data' => Coupon::create($data)], 201);
    }

    public function sellerUpdate(Request $request, string $id)
    {
        $coupon = Coupon::where('seller_id', $request->user()->seller->id)->findOrFail($id);
        if ($request->has('code')) {
            $request->merge(['code' => strtoupper(trim((string) $request->input('code')))]);
        }
        $data = $request->validate($this->sellerRules($coupon->id));
        if (($data['type'] ?? $coupon->type) === 'PERCENT' && ($data['value'] ?? $coupon->value) > 100) {
            throw ValidationException::withMessages(['value' => ['Percentage cannot exceed 100.']]);
        }
        $coupon->update($data);

        return response()->json(['status' => 'success', 'data' => $coupon->fresh()]);
    }

    public function sellerDestroy(Request $request, string $id)
    {
        $coupon = Coupon::where('seller_id', $request->user()->seller->id)->findOrFail($id);
        if ($coupon->used_count > 0 || $coupon->redemptions()->exists()) {
            $coupon->update(['is_active' => false]);
            return response()->json(['status' => 'success', 'message' => 'Coupon deactivated; redemption history retained']);
        }
        $coupon->delete();

        return response()->json(['status' => 'success', 'message' => 'Coupon deleted']);
    }

    private function sellerRules(?string $ignoreId = null): array
    {
        $rules = $this->rules($ignoreId);
        unset($rules['target_type'], $rules['target_ids']);
        $rules['value'] = [$ignoreId ? 'sometimes' : 'required', 'numeric', 'min:0.01', 'max:100000'];

        return $rules;
    }

    private function rules(?string $ignoreId = null): array
    {
        $codeRule = Rule::unique('coupons', 'code');
        if ($ignoreId) {
            $codeRule = $codeRule->ignore($ignoreId);
        }

        $required = $ignoreId ? 'sometimes' : 'required';

        return [
            'code' => [$required, 'string', 'max:40', $codeRule],
            'description' => 'nullable|string|max:255',
            'type' => "$required|in:FLAT,PERCENT",
            'value' => "$required|numeric|min:0",
            'min_order' => 'nullable|numeric|min:0',
            'max_discount' => 'nullable|numeric|min:0',
            'usage_limit' => 'nullable|integer|min:1',
            'per_user_limit' => 'nullable|integer|min:1',
            'target_type' => 'nullable|in:ALL,CATEGORY,PRODUCT',
            'target_ids' => 'nullable|array',
            'starts_at' => 'nullable|date',
            'expires_at' => 'nullable|date',
            'is_active' => 'nullable|boolean',
        ];
    }
}
