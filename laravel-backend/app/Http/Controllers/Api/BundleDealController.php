<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\BundleDeal;
use App\Models\Product;
use Illuminate\Http\Request;

/**
 * Two-product bundle deals.
 *
 * The public list is what the apps show ("Buy together and save"); the admin
 * methods are what staff use to create them. The discount itself is applied at
 * pricing time by {@see \App\Services\Pricing\BundleDiscounts}, never from
 * anything on this page, so what is shown here is a promise the cart keeps.
 */
class BundleDealController extends Controller
{
    private const PRODUCT_RELATIONS = ['category', 'variants'];

    /** Public: live bundles, optionally only those featuring one product. */
    public function index(Request $request)
    {
        $validated = $request->validate(['product_id' => 'nullable|uuid']);

        $query = BundleDeal::live()
            ->with([
                'primaryProduct' => fn ($q) => $q->with(self::PRODUCT_RELATIONS),
                'secondaryProduct' => fn ($q) => $q->with(self::PRODUCT_RELATIONS),
            ])
            ->latest();

        if (! empty($validated['product_id'])) {
            $id = $validated['product_id'];
            $query->where(fn ($q) => $q->where('primary_product_id', $id)->orWhere('secondary_product_id', $id));
        }

        $deals = $query->get()
            ->filter(fn (BundleDeal $d) => $d->primaryProduct?->status === 'ACTIVE'
                && $d->secondaryProduct?->status === 'ACTIVE')
            ->map(fn (BundleDeal $d) => $this->present($d))
            ->values();

        return response()->json(['status' => 'success', 'count' => $deals->count(), 'data' => $deals]);
    }

    // ── Admin CRUD ───────────────────────────────────────────────────────

    public function adminIndex()
    {
        $deals = BundleDeal::with([
            'primaryProduct:id,title,price',
            'secondaryProduct:id,title,price',
        ])->latest()->get();

        return response()->json(['status' => 'success', 'data' => $deals]);
    }

    public function store(Request $request)
    {
        $deal = BundleDeal::create($this->validated($request));

        return response()->json(['status' => 'success', 'data' => $deal->load('primaryProduct:id,title,price', 'secondaryProduct:id,title,price')], 201);
    }

    public function update(Request $request, string $id)
    {
        $deal = BundleDeal::find($id);
        if (! $deal) {
            return response()->json(['status' => 'error', 'message' => 'Bundle not found'], 404);
        }

        $deal->update($this->validated($request, false));

        return response()->json(['status' => 'success', 'data' => $deal->fresh()->load('primaryProduct:id,title,price', 'secondaryProduct:id,title,price')]);
    }

    public function destroy(string $id)
    {
        $deal = BundleDeal::find($id);
        if (! $deal) {
            return response()->json(['status' => 'error', 'message' => 'Bundle not found'], 404);
        }

        $deal->delete();

        return response()->json(['status' => 'success', 'message' => 'Bundle deleted']);
    }

    // ── Internals ────────────────────────────────────────────────────────

    /** @return array<string, mixed> */
    private function validated(Request $request, bool $creating = true): array
    {
        $required = $creating ? 'required' : 'sometimes';

        $data = $request->validate([
            'name' => "{$required}|string|max:255",
            'description' => 'nullable|string|max:1000',
            'primary_product_id' => "{$required}|uuid|exists:products,id",
            'secondary_product_id' => "{$required}|uuid|exists:products,id",
            'bundle_price' => "{$required}|numeric|gt:0|max:9999999",
            'is_active' => 'nullable|boolean',
            'expires_at' => 'nullable|date',
        ]);

        // A bundle of a product with itself would discount a single item.
        $existing = $creating ? null : BundleDeal::find($request->route('id'));
        $primary = $data['primary_product_id'] ?? $existing?->primary_product_id;
        $secondary = $data['secondary_product_id'] ?? $existing?->secondary_product_id;
        if ($primary !== null && $primary === $secondary) {
            abort(response()->json([
                'status' => 'error',
                'message' => 'A bundle needs two different products.',
                'errors' => ['secondary_product_id' => ['Choose a different second product.']],
            ], 422));
        }

        return $data;
    }

    /** @return array<string, mixed> */
    private function present(BundleDeal $deal): array
    {
        /** @var Product $a */
        $a = $deal->primaryProduct;
        /** @var Product $b */
        $b = $deal->secondaryProduct;

        $compareAt = round((float) $a->price + (float) $b->price, 2);
        $price = (float) $deal->bundle_price;

        return [
            'id' => $deal->id,
            'name' => $deal->name,
            'description' => $deal->description,
            'bundle_price' => $price,
            'compare_at_price' => $compareAt,
            'savings' => max(0, round($compareAt - $price, 2)),
            'expires_at' => $deal->expires_at,
            'products' => [$a, $b],
        ];
    }
}
