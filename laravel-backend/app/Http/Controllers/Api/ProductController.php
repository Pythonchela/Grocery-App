<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Product;
use App\Models\ProductView;
use App\Models\SearchQuery;
use Illuminate\Http\Request;
use App\Services\Options\ProductOptions;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;
use App\Support\HtmlSanitizer;
use App\Support\ProductDetails;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

class ProductController extends Controller
{
    private const VARIANT_RULES = [
        'variants' => 'nullable|array',
        // Present for a variant the form loaded, absent for one just added.
        // It's how syncVariants() tells an edit from an insert, which is what
        // keeps order history attached to the variant it was placed against.
        'variants.*.id' => 'nullable|uuid',
        'variants.*.color' => 'nullable|string',
        'variants.*.size' => 'nullable|string',
        'variants.*.color_hex' => ['nullable', 'string', 'regex:/^#[0-9A-Fa-f]{6}$/'],
        'variants.*.sku' => 'nullable|string',
        'variants.*.stock' => 'nullable|integer|min:0',
        'variants.*.price' => 'nullable|numeric|min:0',
        'variants.*.mrp' => 'nullable|numeric|min:0',
        'variants.*.cost_price' => 'nullable|numeric|min:0',
        // A colour's own pictures; the product's gallery is used when empty.
        'variants.*.images' => 'nullable|array|max:12',
        'variants.*.images.*' => 'string|max:1000',
    ];

    private const PRESENTATION_RULES = [
        'rollover_image' => 'nullable|string',
        'authenticity_grade' => 'nullable|string',
        'local_store_available' => 'nullable|boolean',
        'local_store_name' => 'nullable|string',
        'express_pincodes' => 'nullable|array',
        'hotspots' => 'nullable|array',
        'spin_images' => 'nullable|array',
        'cod_available' => 'nullable|boolean',
        'diet' => 'nullable|in:veg,non_veg,egg',
        // Shoppertainment is opt-in per product. Nullable with no other rule
        // implying a requirement — a product is complete and sellable with
        // neither of these ever set.
        'reel_video_url' => 'nullable|string|max:1000',
        'reel_caption' => 'nullable|string|max:160',
        // null = use the category's option template; an array = this product's own.
        'custom_options' => 'nullable|array',
        'delivery_profile' => 'nullable|in:instant,parcel,heavy',
        'prep_minutes' => 'nullable|integer|min:0|max:1440',
        // What it weighs and how big it is packed. Couriers price on these, so a
        // product without them is quoted (and billed) on a guess.
        'weight_grams' => 'nullable|integer|min:1|max:200000',
        'length_cm' => 'nullable|integer|min:1|max:500',
        'width_cm' => 'nullable|integer|min:1|max:500',
        'height_cm' => 'nullable|integer|min:1|max:500',
        'requires_vehicle' => 'nullable|boolean',
    ];

    /**
     * Page size when the caller doesn't ask, and the ceiling when it does.
     *
     * The homepage, category and search pages each fetch once server-side and
     * filter/sort the result entirely in the browser — they have no further
     * fetch as the shopper narrows down, so they explicitly request
     * `per_page=100` to get the full catalog in that one call. Lowering this
     * ceiling silently truncates all three; raising it is fine, but a value
     * below what a real catalog needs reintroduces the unbounded-payload
     * problem this pagination exists to prevent.
     */
    private const DEFAULT_PER_PAGE = 48;

    private const MAX_PER_PAGE = 100;

    public function index(Request $request)
    {
        $isStaff = optional($request->user())->isAdmin();

        $query = Product::query()
            // Explicit columns: the sellers table carries commission_rate and
            // payout_balance, and neither belongs in a public catalog response.
            ->with(['category', 'variants', 'seller:id,display_name,slug,status'])
            // Ratings, review counts and stock totals as three aggregate
            // subqueries instead of four queries per product during
            // serialization.
            ->withCardAggregates();

        // Drafts and discontinued lines are not shopping results — but they are
        // exactly what the admin catalog screen exists to manage, so staff see
        // everything and may filter by status explicitly.
        if ($isStaff) {
            if ($request->filled('status')) {
                $query->where('status', $request->status);
            }
        } else {
            // A suspended seller's whole catalog leaves the storefront at once.
            $query->publiclyVisible()->fromActiveSellers();
        }

        // One shop's items: ?seller=<slug or id>.
        if ($request->filled('seller')) {
            $shop = (string) $request->seller;
            $query->whereHas('seller', fn ($q) => Str::isUuid($shop) ? $q->where('id', $shop) : $q->where('slug', $shop));
        }

        if ($request->filled('category') && $request->category !== 'all') {
            $query->whereHas('category', fn ($q) => $q->where('slug', $request->category));
        }

        if ($request->filled('search')) {
            $query->matchingSearch($request->search);
        }

        if ($request->filled('min_price')) {
            $query->where('price', '>=', (float) $request->min_price);
        }
        if ($request->filled('max_price')) {
            $query->where('price', '<=', (float) $request->max_price);
        }
        if ($request->filled('brand')) {
            $query->where('brand', $request->brand);
        }
        if ($request->boolean('is_new')) {
            $query->where('is_new', true);
        }
        if ($request->boolean('in_stock')) {
            $query->whereHas('variants', fn ($q) => $q->where('stock', '>', 0));
        }

        // Per-category attribute filters, keyed by the category's own
        // filter_config group ids: ?attr[fabric]=cotton&attr[occasion][]=festive
        //
        // Several values for one group are OR'd (fabric = cotton OR linen);
        // separate groups are AND'd (cotton AND festive), which is what a
        // shopper ticking boxes actually expects.
        foreach ((array) $request->input('attr', []) as $key => $values) {
            // Group ids come from the category's own config, but this is still
            // request input — reject anything that isn't a plain key rather than
            // interpolating it into the JSON path.
            if (! is_string($key) || ! preg_match('/^[A-Za-z0-9_-]{1,64}$/', $key)) {
                continue;
            }

            $values = array_values(array_filter(
                is_array($values) ? $values : [$values],
                fn ($v) => is_scalar($v) && $v !== ''
            ));
            if ($values === []) {
                continue;
            }

            $query->where(function ($q) use ($key, $values) {
                foreach ($values as $value) {
                    $q->orWhere(fn ($inner) => $inner->whereAttributeMatches($key, (string) $value));
                }
            });
        }

        // Rating filtering runs as a correlated subquery rather than in PHP.
        // Filtering after hydration meant the whole catalog had to be loaded
        // before a single row could be excluded.
        if ($request->filled('min_rating')) {
            $query->whereRaw(
                '(select coalesce(avg(rating), 0) from reviews where reviews.product_id = products.id and reviews.status = ?) >= ?',
                ['APPROVED', (float) $request->min_rating],
            );
        }

        $sort = $request->get('sort', 'newest');

        // With a search term and no explicit sort, rank by text relevance.
        if ($request->filled('search') && $request->get('sort') === null) {
            $query->orderByRelevance($request->search);
        } else {
            match ($sort) {
                'price_asc' => $query->orderBy('price'),
                'price_desc' => $query->orderByDesc('price'),
                'oldest' => $query->orderBy('created_at'),
                // Both of these are aggregate aliases from withCardAggregates(),
                // so they sort in SQL over the whole result set — the old
                // in-PHP sort could only order the page it had already loaded.
                'rating' => $query->orderByDesc('approved_reviews_avg_rating'),
                'popularity' => $query->orderByDesc('approved_reviews_count'),
                default => $query->orderByDesc('created_at'),
            };
        }

        $perPage = min((int) $request->get('per_page', self::DEFAULT_PER_PAGE), self::MAX_PER_PAGE);
        $products = $query->paginate(max(1, $perPage))->withQueryString();

        // Log the query so the admin search report (top queries / zero-result
        // inventory gaps) has real data to aggregate.
        if ($request->filled('search')) {
            $this->logSearch($request, $products->total());
        }

        return response()->json([
            'status' => 'success',
            // Still the total number of matches, so existing callers reading
            // `count` keep the meaning they had before pagination.
            'count' => $products->total(),
            'facets' => $this->facets(),
            // The formatted description, specification table and manufacturer
            // panel belong to one product's page; a list does not carry them.
            'data' => collect($products->items())->each->makeHidden(['description_html', 'specifications', 'manufacturer'])->all(),
            'meta' => [
                'current_page' => $products->currentPage(),
                'per_page' => $products->perPage(),
                'last_page' => $products->lastPage(),
                'total' => $products->total(),
            ],
        ]);
    }

    private function logSearch(Request $request, int $resultCount): void
    {
        try {
            $raw = trim($request->search);
            SearchQuery::create([
                'query' => $raw,
                'normalised_query' => mb_strtolower(preg_replace('/\s+/', ' ', $raw)),
                'result_count' => $resultCount,
                'user_id' => optional($request->user())->id,
            ]);
        } catch (\Throwable $e) {
            // Analytics must never break the search response.
            Log::warning('Search logging failed: '.$e->getMessage());
        }
    }

    /**
     * Filter bounds for the storefront's filter panel.
     *
     * Three full-table aggregates that change only when the catalog does, and
     * were previously recomputed on every single product request. Cached
     * briefly — a price bound that lags a few minutes is invisible to a shopper;
     * three table scans per page view are not.
     */
    private function facets(): array
    {
        return \Illuminate\Support\Facades\Cache::remember('products.facets', now()->addMinutes(10), fn () => [
            'price_min' => (float) (Product::publiclyVisible()->min('price') ?? 0),
            'price_max' => (float) (Product::publiclyVisible()->max('price') ?? 0),
            'brands' => Product::publiclyVisible()
                ->whereNotNull('brand')
                ->distinct()
                ->orderBy('brand')
                ->pluck('brand')->all(),
        ]);
    }

    /**
     * A draft may be saved half-finished (a name and a category are enough), but a
     * product shoppers can buy needs a real price. Without this a seller who saves
     * early and publishes later could put a ₹0 listing live.
     */
    private function guardLive(array $validated, ?Product $existing): void
    {
        $status = $validated['status'] ?? $existing?->status ?? 'ACTIVE';

        if ($status !== 'ACTIVE') {
            return;
        }

        $price = (float) ($validated['price'] ?? $existing?->price ?? 0);
        $mrp = (float) ($validated['mrp'] ?? $existing?->mrp ?? 0);

        if ($price <= 0 || $mrp <= 0) {
            throw ValidationException::withMessages([
                'price' => ['A live product needs a selling price and an MRP above zero. Keep it as a draft until then.'],
            ]);
        }
    }

    /**
     * The seller a write is allowed to act on behalf of.
     *
     * A seller is pinned to their own account regardless of what the payload
     * says — otherwise `seller_id` in a request body is a one-field takeover of
     * someone else's shop. Staff may name any seller, and default to the house
     * account when they don't.
     */
    private function resolveSellerId(Request $request): string
    {
        $user = $request->user();

        if (! $user->isAdmin()) {
            return $user->seller->id;
        }

        if ($request->filled('seller_id')) {
            return $request->validate(['seller_id' => 'uuid|exists:sellers,id'])['seller_id'];
        }

        return \App\Models\Seller::house()->id;
    }

    /**
     * SKU rules for each submitted variant.
     *
     * A SKU is unique across the whole catalogue (it is a database constraint),
     * so a duplicate used to surface as a 500. It is now a field error on that
     * variant. A variant being edited is excluded from its own check, and two
     * rows in the same submission may not share one either.
     */
    private function skuRules(Request $request): array
    {
        $rules = [];

        foreach ((array) $request->input('variants', []) as $i => $row) {
            $rules["variants.{$i}.sku"] = [
                'nullable', 'string', 'max:80', 'distinct',
                Rule::unique('product_variants', 'sku')->ignore($row['id'] ?? null),
            ];
        }

        return $rules;
    }

    /** Store a product's own option list in canonical form (null stays "inherit"). */
    /**
     * The "all details" content in its stored form: the description cleaned to
     * safe markup (with the plain-text version kept alongside for search and
     * simple clients), and the specification table and manufacturer panel tidied.
     *
     * A client that only knows plain text (the seller app) sends `description`
     * alone. If that differs from what is stored, it replaces the formatted
     * version; sending back the same text it was given changes nothing, so a
     * plain-text edit of some other field never strips the formatting.
     */
    private function withCleanDetails(array $validated, ?Product $existing = null): array
    {
        if (array_key_exists('description_html', $validated)) {
            $html = HtmlSanitizer::clean($validated['description_html']);
            $validated['description_html'] = $html;

            if ($html !== null) {
                $validated['description'] = HtmlSanitizer::toText($html);
            }
        } elseif ($existing && $existing->description_html !== null && array_key_exists('description', $validated)
            && trim((string) $validated['description']) !== trim((string) $existing->description)) {
            $validated['description_html'] = null;
        }

        if (array_key_exists('specifications', $validated)) {
            $validated['specifications'] = ProductDetails::specifications($validated['specifications']);
        }

        if (array_key_exists('manufacturer', $validated)) {
            $validated['manufacturer'] = ProductDetails::manufacturer($validated['manufacturer']);
        }

        return $validated;
    }

    private function withCleanOptions(array $validated): array
    {
        if (isset($validated['custom_options'])) {
            $validated['custom_options'] = ProductOptions::normalize($validated['custom_options'], true, 'custom_options');
        }

        return $validated;
    }

    /** "brass-lamp", then "brass-lamp-x7k2" if that is taken. */
    private function uniqueSlug(string $title): string
    {
        $base = Str::slug($title) ?: 'product';
        $slug = $base;

        while (Product::where('slug', $slug)->exists()) {
            $slug = $base.'-'.Str::lower(Str::random(4));
        }

        return $slug;
    }

    /** 403s unless this actor may write to this particular product. */
    private function authorizeProductWrite(Request $request, Product $product): ?\Illuminate\Http\JsonResponse
    {
        $user = $request->user();

        if ($user->isAdmin()) {
            return null;
        }

        if ($product->seller_id && $product->seller_id === $user->seller?->id) {
            return null;
        }

        // Same 403 whether the product belongs to another seller or doesn't
        // exist for them — a distinguishable response is a way to enumerate
        // other sellers' catalogs.
        return response()->json([
            'status' => 'error',
            'message' => 'Forbidden — this product belongs to another seller.',
        ], 403);
    }

    public function store(Request $request)
    {
        $validated = $request->validate([
            'title' => 'required|string|max:255',
            'slug' => 'nullable|string|unique:products,slug',
            'description' => 'nullable|string',
            'category_id' => 'required|uuid|exists:categories,id',
            'brand' => 'nullable|string',
            'mrp' => 'required|numeric|min:0',
            'price' => 'required|numeric|min:0',
            'images' => 'nullable|array',
            'status' => 'nullable|in:DRAFT,ACTIVE,OUT_OF_STOCK,DISCONTINUED',
            'is_new' => 'nullable|boolean',
            'tags' => 'nullable|array',
            'features' => 'nullable|array',
            'attributes' => 'nullable|array',
            'features.*' => 'string|max:500',
            ...self::VARIANT_RULES,
            ...self::PRESENTATION_RULES,
            ...ProductDetails::rules(),
            ...$this->skuRules($request),
        ]);

        // Derived slugs must be unique too. Only a slug the caller supplies goes
        // through the `unique` rule above, so two products called "Brass Lamp"
        // used to collide on the database constraint and answer 500 — an easy
        // thing for a seller listing similar goods to hit.
        $this->guardLive($validated, null);

        $validated['slug'] = $validated['slug'] ?? $this->uniqueSlug($validated['title']);
        $validated['seller_id'] = $this->resolveSellerId($request);
        $validated = $this->withCleanOptions($validated);
        $validated = $this->withCleanDetails($validated);
        $variants = $validated['variants'] ?? [['color' => 'Standard', 'size' => 'Free Size', 'stock' => 10]];
        unset($validated['variants']);

        $product = Product::create($validated);
        $product->variants()->createMany($variants);

        return response()->json(['status' => 'success', 'data' => $product->load(['category', 'variants', 'seller'])], 201);
    }

    public function show(Request $request, $id)
    {
        $product = Product::with([
            'category', 'variants', 'approvedReviews',
            'seller:id,display_name,slug,status,is_house,logo_url',
        ])
            ->withCardAggregates()
            ->find($id);

        if (! $product) {
            return response()->json(['status' => 'error', 'message' => 'Product not found'], 404);
        }

        // A draft or discontinued product is only visible to staff. Same 404 as
        // a missing one — whether an unreleased line exists isn't public.
        if ($product->status !== 'ACTIVE' && ! optional($request->user())->isAdmin()) {
            return response()->json(['status' => 'error', 'message' => 'Product not found'], 404);
        }

        // A suspended shop, or the owner's own shop in a vendors-only store,
        // is not on show either.
        if (! optional($request->user())->isAdmin() && ! $product->seller?->isVisibleToShoppers()) {
            return response()->json(['status' => 'error', 'message' => 'Product not found'], 404);
        }

        $this->recordView($request, $product->id);

        return response()->json(['status' => 'success', 'data' => $product]);
    }

    /**
     * Feeds the Trending engine and personalised recommendations.
     *
     * Deduplicated per viewer per product per hour. Writing a row on every
     * request meant a crawler could both inflate "trending" and grow the table
     * without bound — the signal is "someone looked at this", and the tenth
     * refresh in a minute is not ten more people.
     */
    private function recordView(Request $request, string $productId): void
    {
        $userId = optional($request->user())->id;
        $key = 'pv:'.$productId.':'.($userId ?? 'ip:'.$request->ip());

        try {
            // add() is atomic and returns false when the key already exists, so
            // concurrent requests can't both slip a row through.
            if (! \Illuminate\Support\Facades\Cache::add($key, 1, now()->addHour())) {
                return;
            }

            ProductView::create(['product_id' => $productId, 'user_id' => $userId]);
        } catch (\Throwable $e) {
            Log::warning('View tracking failed: '.$e->getMessage());
        }
    }

    public function update(Request $request, $id)
    {
        $product = Product::find($id);

        if (! $product) {
            return response()->json(['status' => 'error', 'message' => 'Product not found'], 404);
        }

        if ($denied = $this->authorizeProductWrite($request, $product)) {
            return $denied;
        }

        $validated = $request->validate([
            'title' => 'sometimes|string|max:255',
            'slug' => ['sometimes', 'string', Rule::unique('products', 'slug')->ignore($product->id)],
            'description' => 'nullable|string',
            'category_id' => 'sometimes|uuid|exists:categories,id',
            'brand' => 'nullable|string',
            'mrp' => 'sometimes|numeric|min:0',
            'price' => 'sometimes|numeric|min:0',
            'images' => 'nullable|array',
            'status' => 'nullable|in:DRAFT,ACTIVE,OUT_OF_STOCK,DISCONTINUED',
            'is_new' => 'nullable|boolean',
            'tags' => 'nullable|array',
            'features' => 'nullable|array',
            'attributes' => 'nullable|array',
            'features.*' => 'string|max:500',
            ...self::VARIANT_RULES,
            ...self::PRESENTATION_RULES,
            ...ProductDetails::rules(),
            ...$this->skuRules($request),
        ]);

        $this->guardLive($validated, $product);

        $validated = $this->withCleanOptions($validated);
        $validated = $this->withCleanDetails($validated, $product);
        $variants = $validated['variants'] ?? null;
        unset($validated['variants']);

        DB::transaction(function () use ($product, $validated, $variants) {
            $product->update($validated);

            if ($variants !== null) {
                $this->syncVariants($product, $variants);
            }
        });

        return response()->json(['status' => 'success', 'data' => $product->load(['category', 'variants'])]);
    }

    /**
     * Reconcile the submitted variant list against what's stored, matching on
     * id so existing rows keep their identity.
     *
     * The admin form submits the full list every time, and this used to be
     * implemented as delete-all-then-recreate. Because `order_items.variant_id`
     * is ON DELETE SET NULL, a routine stock edit silently detached every past
     * order of that product from the variant it was for — which broke return
     * restocking and left invoices unable to say which size was sold.
     */
    private function syncVariants(Product $product, array $submitted): void
    {
        $existing = $product->variants()->get()->keyBy('id');
        $keptIds = [];

        foreach ($submitted as $row) {
            $id = $row['id'] ?? null;

            if ($id && $current = $existing->get($id)) {
                $current->update($row);
                $keptIds[] = $current->id;

                continue;
            }

            $keptIds[] = $product->variants()->create($row)->id;
        }

        // Whatever the admin actually removed. Variants that were never sold
        // are deleted outright; ones with order history are kept at zero stock
        // so the orders that reference them stay intact and auditable.
        $removed = $existing->keys()->diff($keptIds);

        foreach ($removed as $variantId) {
            $variant = $existing->get($variantId);

            if ($variant->orderItems()->exists()) {
                $variant->update(['stock' => 0]);

                continue;
            }

            $variant->delete();
        }
    }

    public function destroy(Request $request, $id)
    {
        $product = Product::find($id);

        if (! $product) {
            return response()->json(['status' => 'error', 'message' => 'Product not found'], 404);
        }

        if ($denied = $this->authorizeProductWrite($request, $product)) {
            return $denied;
        }

        // `order_items.product_id` is a restricting foreign key, so deleting a
        // product anyone has ever bought raised a raw SQL error. Discontinuing
        // is what's actually meant here — it hides the product everywhere the
        // storefront looks while leaving order history readable.
        if ($product->orderItems()->exists()) {
            return response()->json([
                'status' => 'error',
                'message' => 'This product has been ordered before, so it cannot be deleted. Set its status to DISCONTINUED to remove it from the store.',
            ], 422);
        }

        DB::transaction(function () use ($product) {
            $product->variants()->delete();
            $product->delete();
        });

        return response()->json(['status' => 'success', 'message' => 'Product deleted successfully']);
    }
}
