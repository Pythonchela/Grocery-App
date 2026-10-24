<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Seller;
use App\Support\StoreMode;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * Shops, for shoppers who choose a shop first and its items second.
 *
 * Public, and only ever shows what a shopper may see: active shops (and the
 * owner's own shop unless the store hides it), never commission, payout balance,
 * KYC or pickup details.
 */
class ShopController extends Controller
{
    private const DEFAULT_PER_PAGE = 20;
    private const MAX_PER_PAGE = 50;

    /** What the apps need to know about the kind of store this is. */
    public function config()
    {
        return response()->json(['status' => 'success', 'data' => StoreMode::publicConfig()]);
    }

    /**
     * ?search=  words in the shop's name or tagline
     * ?pincode= only shops that deliver there
     * ?category=slug  only shops selling something in that category
     * ?open=1   only shops taking orders right now
     *
     * Open shops come first, then the best rated, then by name: a shopper at
     * 9 p.m. wants the ones that will actually deliver.
     */
    public function index(Request $request)
    {
        $query = Seller::visibleToShoppers()
            // A shop with nothing on sale is not a shop yet.
            ->whereHas('products', fn ($q) => $q->where('status', 'ACTIVE'));

        if ($request->filled('search')) {
            $like = '%'.str_replace(['%', '_'], ['\%', '\_'], trim((string) $request->search)).'%';
            $query->where(fn ($q) => $q->where('display_name', 'like', $like)->orWhere('tagline', 'like', $like));
        }

        $shops = $query->get();

        if ($request->filled('pincode')) {
            $pin = (string) $request->pincode;
            $shops = $shops->filter(fn (Seller $s) => $s->servesPincode($pin));
        }

        $stats = $this->stats($shops->pluck('id')->all());

        // The category filters on offer: whatever these shops actually sell, so
        // the list suits groceries, clothing or food alike. Counted before the
        // chosen category narrows the list, so the other chips stay available.
        $facets = $this->categoryFacets($stats);

        if ($request->filled('category')) {
            $slug = (string) $request->category;
            $shops = $shops->filter(fn (Seller $s) => collect($stats['categories'][$s->id] ?? [])->contains(fn ($c) => $c->slug === $slug));
        }

        $rows = $shops->map(fn (Seller $s) => $this->card($s, $stats));

        if ($request->boolean('open')) {
            $rows = $rows->filter(fn (array $r) => $r['is_open']);
        }

        $rows = $rows->sort(fn (array $a, array $b) => [$b['is_open'], $b['rating'], $a['name']] <=> [$a['is_open'], $a['rating'], $b['name']])
            ->values();

        $perPage = max(1, min((int) $request->get('per_page', self::DEFAULT_PER_PAGE), self::MAX_PER_PAGE));
        $page = max(1, (int) $request->get('page', 1));

        return response()->json([
            'status' => 'success',
            'count' => $rows->count(),
            'data' => $rows->forPage($page, $perPage)->values(),
            'facets' => ['categories' => $facets],
            'meta' => [
                'current_page' => $page,
                'per_page' => $perPage,
                'last_page' => max(1, (int) ceil($rows->count() / $perPage)),
                'total' => $rows->count(),
            ],
        ]);
    }

    /** One shop's page: who they are, when they open, what they ask of an order. */
    public function show(string $shop)
    {
        $seller = Seller::visibleToShoppers()
            ->where(fn ($q) => Str::isUuid($shop) ? $q->where('id', $shop) : $q->where('slug', $shop))
            ->first();

        if (! $seller) {
            return response()->json(['status' => 'error', 'message' => 'Shop not found'], 404);
        }

        $card = $this->card($seller, $this->stats([$seller->id]));

        return response()->json(['status' => 'success', 'data' => $card + [
            'about' => $seller->about,
            'opening_hours' => $seller->opening_hours,
            'service_pincodes' => $seller->service_pincodes ?? [],
            'support_phone' => $seller->support_phone,
        ]]);
    }

    /**
     * Rating, product count and the categories each shop mostly sells, for many
     * shops in three queries instead of three per shop.
     *
     * @param  array<int, string>  $ids
     * @return array{rating: array, products: array, categories: array}
     */
    private function stats(array $ids): array
    {
        if ($ids === []) {
            return ['rating' => [], 'products' => [], 'categories' => []];
        }

        $rating = DB::table('reviews')
            ->join('products', 'products.id', '=', 'reviews.product_id')
            ->whereIn('products.seller_id', $ids)
            ->where('reviews.status', 'APPROVED')
            ->groupBy('products.seller_id')
            ->selectRaw('products.seller_id as seller_id, AVG(reviews.rating) as avg_rating, COUNT(*) as reviews')
            ->get()->keyBy('seller_id');

        $products = DB::table('products')
            ->whereIn('seller_id', $ids)->where('status', 'ACTIVE')
            ->groupBy('seller_id')
            ->selectRaw('seller_id, COUNT(*) as total')
            ->get()->keyBy('seller_id');

        $categories = DB::table('products')
            ->join('categories', 'categories.id', '=', 'products.category_id')
            ->whereIn('products.seller_id', $ids)->where('products.status', 'ACTIVE')
            ->groupBy('products.seller_id', 'categories.name', 'categories.slug')
            ->selectRaw('products.seller_id as seller_id, categories.name as name, categories.slug as slug, COUNT(*) as n')
            ->orderByDesc('n')
            ->get()->groupBy('seller_id');

        return ['rating' => $rating->all(), 'products' => $products->all(), 'categories' => $categories->all()];
    }

    /**
     * @param  array{categories: array}  $stats
     * @return list<array{slug: string, name: string, shops: int}> categories with how many shops sell in each
     */
    private function categoryFacets(array $stats): array
    {
        $counts = [];

        foreach ($stats['categories'] as $rows) {
            foreach ($rows as $row) {
                $counts[$row->slug] ??= ['slug' => $row->slug, 'name' => $row->name, 'shops' => 0];
                $counts[$row->slug]['shops']++;
            }
        }

        $facets = array_values($counts);
        usort($facets, fn (array $a, array $b) => [$b['shops'], $a['name']] <=> [$a['shops'], $b['name']]);

        return $facets;
    }

    private function card(Seller $s, array $stats): array
    {
        $rating = $stats['rating'][$s->id] ?? null;

        return [
            'id' => $s->id,
            'name' => $s->display_name,
            'slug' => $s->slug,
            'logo_url' => $s->logo_url,
            'banner_url' => $s->banner_url,
            'tagline' => $s->tagline,
            'is_house' => (bool) $s->is_house,
            'is_open' => $s->isOpenNow(),
            'closed_text' => $s->isOpenNow() ? null : $s->closedText(),
            'min_order_amount' => (float) $s->min_order_amount,
            'prep_minutes' => $s->prep_minutes,
            'rating' => $rating ? round((float) $rating->avg_rating, 1) : 0.0,
            'reviews_count' => $rating ? (int) $rating->reviews : 0,
            'product_count' => (int) ($stats['products'][$s->id]->total ?? 0),
            // What the shop mostly sells, for the line under its name.
            'categories' => collect($stats['categories'][$s->id] ?? [])->pluck('name')->take(3)->values()->all(),
        ];
    }
}
