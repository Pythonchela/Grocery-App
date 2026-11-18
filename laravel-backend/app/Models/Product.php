<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

#[Fillable([
    'title', 'slug', 'description', 'description_html', 'specifications', 'manufacturer', 'category_id', 'seller_id', 'brand', 'mrp', 'price',
    'images', 'status', 'is_new', 'tags', 'features', 'attributes', 'meta_title', 'meta_description',
    'rollover_image', 'authenticity_grade', 'local_store_available',
    'local_store_name', 'express_pincodes', 'hotspots',
    'spin_images', 'cod_available',
    // 'veg' | 'non_veg' | 'egg' | null: the mark food shoppers look for.
    'diet',
    // Shipping envelope. Drives carrier selection and what we get billed.
    'weight_grams', 'length_cm', 'width_cm', 'height_cm', 'requires_vehicle',
    // Optional Shoppertainment clip. A product is complete without either.
    'reel_video_url', 'reel_caption',
    // null = inherit the category's option template; an array = this product's own.
    'custom_options',
    // 'instant' | 'parcel' | 'heavy', and minutes to prepare; null = use the category's.
    'delivery_profile', 'prep_minutes',
])]
class Product extends Model
{
    use HasFactory, HasUuids;

    protected $appends = ['discount', 'stock_count', 'in_stock', 'rating', 'reviews_count', 'has_reel', 'option_groups', 'delivery_info'];

    protected function casts(): array
    {
        return [
            'images' => 'array',
            'tags' => 'array',
            'features' => 'array',
            'specifications' => 'array',
            'manufacturer' => 'array',
            'attributes' => 'array',
            'is_new' => 'boolean',
            'mrp' => 'decimal:2',
            'price' => 'decimal:2',
            'local_store_available' => 'boolean',
            'express_pincodes' => 'array',
            'hotspots' => 'array',
            'spin_images' => 'array',
            'cod_available' => 'boolean',
            'custom_options' => 'array',
        ];
    }

    public function category()
    {
        return $this->belongsTo(Category::class);
    }

    public function seller()
    {
        return $this->belongsTo(Seller::class);
    }

    /** Only what a seller with an active account is offering. */
    public function scopeFromActiveSellers($query)
    {
        return $query->whereHas('seller', fn ($q) => $q->visibleToShoppers());
    }

    public function variants()
    {
        // Ordered by id, not created_at: variants created in one transaction
        // share a timestamp, and UUIDv7 ids are time-sortable, so this is the
        // only stable way to keep the selector in its authored order.
        return $this->hasMany(ProductVariant::class)->orderBy('id');
    }

    public function orderItems()
    {
        return $this->hasMany(OrderItem::class);
    }

    public function reviews()
    {
        return $this->hasMany(Review::class);
    }

    public function approvedReviews()
    {
        return $this->reviews()->where('status', 'APPROVED');
    }

    /**
     * Restrict a query to what the public may see.
     *
     * Only the recommendation and reels endpoints used to do this, so drafts and
     * discontinued lines were listed, searchable and purchasable from the main
     * catalog endpoints.
     */
    public function scopePubliclyVisible($query)
    {
        return $query->where('status', 'ACTIVE');
    }

    /**
     * Load the aggregates the appended attributes need, in one query each
     * instead of one query per product.
     *
     * These six appends used to fire four queries apiece during serialization,
     * so listing 500 products cost ~2,000 round trips. The accessors below read
     * these aggregates when they're present and only fall back to querying when
     * a model was loaded without them.
     */
    public function scopeWithCardAggregates($query)
    {
        return $query
            ->withCount('approvedReviews')
            ->withAvg('approvedReviews', 'rating')
            ->withSum('variants', 'stock');
    }

    /** True when the connection has the tsvector/pg_trgm machinery the search migration builds. */
    protected static function hasFullTextSearch(): bool
    {
        return \Illuminate\Support\Facades\DB::connection()->getDriverName() === 'pgsql';
    }

    /**
     * Keyword match, in whichever dialect the connection speaks.
     *
     * `search_vector`, `word_similarity` and `ILIKE` are all Postgres-only, and
     * the migration that creates the first two is itself guarded by a driver
     * check — so on MySQL the unguarded version of this made every search a 500
     * despite the app advertising multi-database support.
     */
    public function scopeMatchingSearch($query, string $term)
    {
        $term = trim($term);

        if ($term === '') {
            return $query;
        }

        if (! static::hasFullTextSearch()) {
            return $query->where(function ($q) use ($term) {
                $q->where('title', 'like', '%'.$term.'%')
                    ->orWhere('brand', 'like', '%'.$term.'%');
            });
        }

        return $query->where(function ($q) use ($term) {
            // word_similarity compares the term against the best-matching word
            // in the title, so "anarkli" still hits "Anarkali" in a long title
            // where whole-string similarity() would score ~0.05.
            $q->whereRaw("search_vector @@ plainto_tsquery('english', ?)", [$term])
                ->orWhereRaw('word_similarity(?, title) > 0.5', [$term])
                ->orWhere('title', 'ILIKE', '%'.$term.'%')
                ->orWhere('brand', 'ILIKE', '%'.$term.'%');
        });
    }

    /** Relevance ordering where the index supports it, recency where it doesn't. */
    public function scopeOrderByRelevance($query, string $term)
    {
        if (! static::hasFullTextSearch()) {
            return $query->orderByDesc('created_at');
        }

        return $query->orderByRaw(
            "ts_rank(search_vector, plainto_tsquery('english', ?)) DESC, word_similarity(?, title) DESC",
            [trim($term), trim($term)],
        );
    }

    /**
     * Match a value inside the per-category `attributes` JSON, handling both
     * shapes the column stores: a scalar for single-select filter groups, and
     * an array for multi-select ones.
     */
    public function scopeWhereAttributeMatches($query, string $key, string $value)
    {
        if (static::hasFullTextSearch()) {
            return $query->where(function ($q) use ($key, $value) {
                $q->whereRaw('attributes::jsonb @> ?', [json_encode([$key => $value])])
                    ->orWhereRaw('attributes::jsonb @> ?', [json_encode([$key => [$value]])]);
            });
        }

        return $query->where(function ($q) use ($key, $value) {
            $q->where('attributes->'.$key, $value)
                ->orWhereJsonContains('attributes->'.$key, $value);
        });
    }

    /**
     * Whether an aggregate from withCardAggregates() is present on this model.
     *
     * `??` would be wrong here, and expensively so: a product with no approved
     * reviews has an avg of NULL, which `??` reads as "not loaded" and answers
     * with a query — putting the per-product round trip straight back for every
     * unreviewed product, which on a fresh catalog is most of them.
     */
    protected function hasAggregate(string $key): bool
    {
        return array_key_exists($key, $this->attributes);
    }

    /** Real aggregate rating computed from approved reviews — never randomised. */
    public function getRatingAttribute(): float
    {
        $avg = $this->hasAggregate('approved_reviews_avg_rating')
            ? $this->attributes['approved_reviews_avg_rating']
            : $this->approvedReviews()->avg('rating');

        return round((float) $avg, 1);
    }

    public function getReviewsCountAttribute(): int
    {
        return (int) ($this->hasAggregate('approved_reviews_count')
            ? $this->attributes['approved_reviews_count']
            : $this->approvedReviews()->count());
    }

    public function getStockCountAttribute(): int
    {
        // An already-loaded variants relation is the cheapest answer of all —
        // the product page and cart both have it in memory already.
        if ($this->relationLoaded('variants')) {
            return (int) $this->variants->sum('stock');
        }

        return (int) ($this->hasAggregate('variants_sum_stock')
            ? $this->attributes['variants_sum_stock']
            : $this->variants()->sum('stock'));
    }

    public function getInStockAttribute(): bool
    {
        return $this->stock_count > 0;
    }

    /** Whether this product opted into the Reels feed. Most will not. */
    public function getHasReelAttribute(): bool
    {
        return filled($this->reel_video_url);
    }

    /**
     * The option groups shoppers see: this product's own list, else its category's
     * template. A list that happens not to have loaded the category gets [] rather
     * than one query per product - the detail page and cart always load it.
     */
    public function getOptionGroupsAttribute(): array
    {
        if (! is_array($this->custom_options) && ! $this->relationLoaded('category')) {
            return [];
        }

        return \App\Services\Options\ProductOptions::groupsFor($this);
    }

    /**
     * How this item is delivered and how long it takes to get ready, from the
     * product or else its category. Empty on lists that haven't loaded the
     * category, rather than one query per product.
     *
     * @return array{profile: ?string, prep_minutes: int}
     */
    public function getDeliveryInfoAttribute(): array
    {
        if ($this->delivery_profile === null && $this->prep_minutes === null && ! $this->relationLoaded('category')) {
            return ['profile' => null, 'prep_minutes' => 0];
        }

        return [
            'profile' => \App\Services\Delivery\DeliveryProfile::profileOf($this),
            'prep_minutes' => \App\Services\Delivery\DeliveryProfile::prepMinutesOf($this),
        ];
    }

    public function getDiscountAttribute(): int
    {
        if ((float) $this->mrp <= 0) {
            return 0;
        }

        return (int) round((($this->mrp - $this->price) / $this->mrp) * 100);
    }
}
