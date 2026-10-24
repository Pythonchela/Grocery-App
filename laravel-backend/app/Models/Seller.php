<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

/**
 * A merchant selling on the platform.
 *
 * `is_house` marks the platform's own inventory. It exists so that "who sells
 * this" always has an answer — a nullable seller_id would mean every query
 * downstream has to handle two shapes, and the first one to forget is the one
 * that silently drops the platform's own products out of a payout report.
 */
#[Fillable([
    'user_id', 'display_name', 'slug', 'legal_name',
    'support_email', 'support_phone', 'commission_rate', 'status',
    // Where this seller's goods are collected from (see PickupLocation).
    'pickup_name', 'pickup_phone', 'pickup_line1', 'pickup_city', 'pickup_state',
    'pickup_pincode', 'pickup_lat', 'pickup_lng', 'pickup_code',
    // How the shop shows to shoppers browsing shops, and when it takes orders.
    'logo_url', 'banner_url', 'tagline', 'about', 'opening_hours', 'accepting_orders',
    'min_order_amount', 'service_pincodes', 'prep_minutes',
    // Order desk: confirm each order by hand, and a timed pause ("back at 6pm").
    'auto_accept', 'paused_until',
])]
class Seller extends Model
{
    use HasFactory, HasUuids;

    protected function casts(): array
    {
        return [
            'commission_rate' => 'decimal:2',
            'payout_balance' => 'decimal:2',
            'is_house' => 'boolean',
            'opening_hours' => 'array',
            'service_pincodes' => 'array',
            'accepting_orders' => 'boolean',
            'auto_accept' => 'boolean',
            'paused_until' => 'datetime',
            'min_order_amount' => 'decimal:2',
        ];
    }

    // ── The shop, as a shopper meets it ─────────────────────────────────

    public const DAYS = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];

    /** Validation for the shop's own presentation and ordering rules. */
    public static function shopRules(): array
    {
        $time = ['nullable', 'regex:/^([01][0-9]|2[0-3]):[0-5][0-9]$/'];

        return [
            'logo_url' => 'nullable|string|max:2048',
            'banner_url' => 'nullable|string|max:2048',
            'tagline' => 'nullable|string|max:120',
            'about' => 'nullable|string|max:2000',
            'opening_hours' => 'nullable|array',
            'opening_hours.*' => 'nullable|array',
            'opening_hours.*.open' => $time,
            'opening_hours.*.close' => $time,
            'accepting_orders' => 'nullable|boolean',
            'auto_accept' => 'nullable|boolean',
            'paused_until' => 'nullable|date',
            'min_order_amount' => 'nullable|numeric|min:0|max:1000000',
            'service_pincodes' => 'nullable|array|max:500',
            'service_pincodes.*' => ['string', 'regex:/^[1-9][0-9]{5}$/'],
            'prep_minutes' => 'nullable|integer|min:0|max:1440',
        ];
    }

    /**
     * The submitted shop fields in stored form: hours kept only for real days
     * with both times (a day with neither is closed), PIN codes de-duplicated.
     */
    public static function cleanShopFields(array $fields): array
    {
        if (array_key_exists('opening_hours', $fields)) {
            $hours = [];

            foreach (self::DAYS as $day) {
                $slot = $fields['opening_hours'][$day] ?? null;
                $open = $slot['open'] ?? null;
                $close = $slot['close'] ?? null;

                $hours[$day] = ($open && $close && $open !== $close) ? ['open' => $open, 'close' => $close] : null;
            }

            $fields['opening_hours'] = array_filter($hours) === [] && ($fields['opening_hours'] ?? []) === []
                ? null
                : $hours;
        }

        if (array_key_exists('service_pincodes', $fields)) {
            $pins = array_values(array_unique(array_map('strval', $fields['service_pincodes'] ?? [])));
            $fields['service_pincodes'] = $pins ?: null;
        }

        foreach (['accepting_orders', 'auto_accept'] as $never_null) {
            if (array_key_exists($never_null, $fields) && $fields[$never_null] === null) {
                unset($fields[$never_null]);   // these columns are never null
            }
        }

        if (array_key_exists('min_order_amount', $fields) && $fields['min_order_amount'] === null) {
            $fields['min_order_amount'] = 0;
        }

        return $fields;
    }

    /** Whether the shop has switched order-taking off. A shop that was never switched is on. */
    private function pausedOrders(): bool
    {
        if (($this->accepting_orders ?? true) === false) {
            return true;
        }

        return $this->paused_until !== null && $this->paused_until->isFuture();
    }

    private static function hourOf(string $hhmm): int
    {
        return ((int) substr($hhmm, 0, 2)) * 60 + (int) substr($hhmm, 3, 2);
    }

    /** The slot for a weekday key ("mon"), or null when closed that day. */
    private function slot(string $day): ?array
    {
        $slot = ($this->opening_hours ?? [])[$day] ?? null;

        return is_array($slot) && ! empty($slot['open']) && ! empty($slot['close']) ? $slot : null;
    }

    /**
     * Whether the shop is taking orders at [$now]: not paused, and inside its
     * hours. A slot that closes before it opens runs past midnight, so Friday
     * 18:00-02:00 is still open at 01:00 on Saturday.
     */
    public function isOpenNow(?\DateTimeInterface $now = null): bool
    {
        if ($this->pausedOrders()) {
            return false;
        }

        if (empty($this->opening_hours)) {
            return true;
        }

        $at = \Carbon\CarbonImmutable::instance($now ?? now())->setTimezone(config('marketplace.timezone', 'Asia/Kolkata'));
        $minute = $at->hour * 60 + $at->minute;

        $today = $this->slot(strtolower(substr($at->format('D'), 0, 3)));
        if ($today) {
            $open = self::hourOf($today['open']);
            $close = self::hourOf($today['close']);

            if ($close > $open ? ($minute >= $open && $minute < $close) : $minute >= $open) {
                return true;
            }
        }

        $yesterday = $this->slot(strtolower(substr($at->subDay()->format('D'), 0, 3)));
        if ($yesterday) {
            $open = self::hourOf($yesterday['open']);
            $close = self::hourOf($yesterday['close']);

            if ($close < $open && $minute < $close) {
                return true;
            }
        }

        return false;
    }

    /** Why a shop is closed, and when it next opens, in words ("Opens tomorrow at 9:00 AM"). */
    public function closedText(?\DateTimeInterface $now = null): string
    {
        if ($this->pausedOrders()) {
            if (($this->accepting_orders ?? true) !== false && $this->paused_until) {
                $back = \Carbon\CarbonImmutable::instance($this->paused_until)->setTimezone(config('marketplace.timezone', 'Asia/Kolkata'));

                return 'Back '.($back->isToday() ? 'today' : $back->format('D')).' at '.$back->format('g:i A');
            }

            return 'Not taking orders right now';
        }

        $at = \Carbon\CarbonImmutable::instance($now ?? now())->setTimezone(config('marketplace.timezone', 'Asia/Kolkata'));

        for ($i = 0; $i <= 7; $i++) {
            $day = $at->addDays($i);
            $slot = $this->slot(strtolower(substr($day->format('D'), 0, 3)));

            if (! $slot) {
                continue;
            }

            $opens = $day->setTime((int) substr($slot['open'], 0, 2), (int) substr($slot['open'], 3, 2));

            if ($opens > $at) {
                $when = $i === 0 ? 'today' : ($i === 1 ? 'tomorrow' : $opens->format('D'));

                return "Opens {$when} at ".$opens->format('g:i A');
            }
        }

        return 'Closed';
    }

    /** Whether the shop delivers to a PIN code. No list means no restriction. */
    public function servesPincode(?string $pincode): bool
    {
        $served = $this->service_pincodes ?? [];

        return $served === [] || $pincode === null || in_array($pincode, $served, true);
    }

    /** Active, and not the owner's own shop in a store where that is hidden. */
    public function scopeVisibleToShoppers($query)
    {
        $query->where('status', 'ACTIVE');

        if (! \App\Support\StoreMode::houseVisible()) {
            $query->where('is_house', false);
        }

        return $query;
    }

    public function isVisibleToShoppers(): bool
    {
        return $this->status === 'ACTIVE' && ($this->is_house ? \App\Support\StoreMode::houseVisible() : true);
    }

    /** The shop fields as the seller's and admin's forms read and write them. */
    public function shopFields(): array
    {
        return [
            'logo_url' => $this->logo_url,
            'banner_url' => $this->banner_url,
            'tagline' => $this->tagline,
            'about' => $this->about,
            'opening_hours' => $this->opening_hours,
            'accepting_orders' => ($this->accepting_orders ?? true) !== false,
            'paused_until' => $this->paused_until?->toIso8601String(),
            'auto_accept' => (bool) ($this->auto_accept ?? true),
            'min_order_amount' => (float) $this->min_order_amount,
            'service_pincodes' => $this->service_pincodes ?? [],
            'prep_minutes' => $this->prep_minutes,
            'is_open' => $this->isOpenNow(),
            'closed_text' => $this->isOpenNow() ? null : $this->closedText(),
        ];
    }

    public function user()
    {
        return $this->belongsTo(User::class);
    }

    public function products()
    {
        return $this->hasMany(Product::class);
    }

    public function ledgerEntries()
    {
        return $this->hasMany(SellerLedgerEntry::class);
    }

    public function kyc()
    {
        return $this->hasOne(SellerKycProfile::class);
    }

    public function documents()
    {
        return $this->hasMany(SellerDocument::class);
    }

    /**
     * Whether this account may be switched on.
     *
     * The house seller is the platform itself and has nobody to verify. Every
     * other merchant needs approved KYC before they can list anything or accrue
     * a payout balance — that check is the whole reason public seller signup is
     * safe to offer at all.
     */
    public function mayBeActivated(): bool
    {
        return $this->is_house || (bool) $this->kyc?->isApproved();
    }

    /** Validation for the pickup fields; shared by the seller's and the admin's forms. */
    public static function pickupRules(): array
    {
        return [
            'pickup_name' => 'nullable|string|max:120',
            'pickup_phone' => ['nullable', 'string', 'regex:/^[0-9+\-\s]{7,20}$/'],
            'pickup_line1' => 'nullable|string|max:200',
            'pickup_city' => 'nullable|string|max:80',
            'pickup_state' => 'nullable|string|max:80',
            'pickup_pincode' => ['nullable', 'string', 'regex:/^[1-9][0-9]{5}$/'],
            'pickup_lat' => 'nullable|numeric|between:-90,90',
            'pickup_lng' => 'nullable|numeric|between:-180,180',
            'pickup_code' => 'nullable|string|max:80',
        ];
    }

    /** Whether this seller has said where to collect from (street and a valid PIN). */
    public function hasPickupAddress(): bool
    {
        return filled($this->pickup_line1) && preg_match('/^[1-9][0-9]{5}$/', (string) $this->pickup_pincode) === 1;
    }

    /** The pickup fields as the apps show and edit them. */
    public function pickupFields(): array
    {
        return [
            'pickup_name' => $this->pickup_name,
            'pickup_phone' => $this->pickup_phone,
            'pickup_line1' => $this->pickup_line1,
            'pickup_city' => $this->pickup_city,
            'pickup_state' => $this->pickup_state,
            'pickup_pincode' => $this->pickup_pincode,
            'pickup_lat' => $this->pickup_lat !== null ? (float) $this->pickup_lat : null,
            'pickup_lng' => $this->pickup_lng !== null ? (float) $this->pickup_lng : null,
            'pickup_code' => $this->pickup_code,
            'has_pickup_address' => $this->hasPickupAddress(),
        ];
    }

    public function scopeActive($query)
    {
        return $query->where('status', 'ACTIVE');
    }

    /** The platform's own storefront inventory. */
    public static function house(): self
    {
        return static::where('is_house', true)->firstOrFail();
    }

    public function isActive(): bool
    {
        return $this->status === 'ACTIVE';
    }

    /**
     * Split a line's takings between the platform and this seller.
     *
     * `$gross` is what the customer actually paid for the line — net of its
     * share of any discount, not the list price. Discounts come out of the
     * seller's take, which is what makes "who funds the promotion" a settled
     * question rather than an argument after the fact.
     *
     * Besides the commission, the marketplace may deduct GST on that commission,
     * TCS and TDS. Their rates are admin settings and zero until set, so a store
     * that does not collect them sees exactly the old split.
     *
     * @return array{commission: float, gst: float, tcs: float, tds: float, net: float}
     */
    public function splitOf(float $gross): array
    {
        $commission = round($gross * ((float) $this->commission_rate / 100), 2);
        $gst = round($commission * ((float) config('marketplace.commission_gst_percent', 0) / 100), 2);
        $tcs = round($gross * ((float) config('marketplace.tcs_percent', 0) / 100), 2);
        $tds = round($gross * ((float) config('marketplace.tds_percent', 0) / 100), 2);

        return [
            'commission' => $commission,
            'gst' => $gst,
            'tcs' => $tcs,
            'tds' => $tds,
            'net' => round($gross - $commission - $gst - $tcs - $tds, 2),
        ];
    }
}
