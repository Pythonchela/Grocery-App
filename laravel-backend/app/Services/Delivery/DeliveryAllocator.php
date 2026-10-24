<?php

namespace App\Services\Delivery;

use App\Models\Order;
use App\Models\Product;
use App\Services\Contracts\DeliveryCarrier;
use Illuminate\Support\Facades\Log;

/**
 * Decides who ships what.
 *
 * The rules encode how Indian fulfilment actually splits:
 *
 *   - A 40kg washing machine cannot go on a bike. It needs a Porter truck, and
 *     it needs a scheduled slot rather than a next-day promise.
 *   - A ₹900 phone case going 4km across the same city is absurd to hand to a
 *     surface 3PL for a 4-day transit when a rider does it in 45 minutes.
 *   - Anything crossing cities goes to an aggregator, because rider networks
 *     are intracity only.
 *
 * The allocator never picks *for* the customer at checkout — it produces the
 * option list and the customer chooses. It picks unilaterally only when an
 * order is being booked and the chosen carrier has since become unavailable.
 */
class DeliveryAllocator
{
    public function __construct(private readonly CarrierRegistry $registry) {}

    /**
     * Every bookable option for this shipment, cheapest-within-fastest first.
     *
     * @return DeliveryQuote[]
     */
    public function quotes(Shipment $shipment): array
    {
        $quotes = [];

        foreach ($this->registry->enabled() as $carrier) {
            if (! $carrier->canCarry($shipment)) {
                continue;
            }

            try {
                foreach ($carrier->quote($shipment) as $quote) {
                    $quotes[] = $quote;
                }
            } catch (\Throwable $e) {
                // One partner being down must cost that partner its slot, not
                // break checkout. Logged loudly because a carrier that quietly
                // stops quoting is revenue leaking to its competitors.
                Log::warning('[DeliveryAllocator] carrier quote failed', [
                    'carrier' => $carrier->key(),
                    'error' => $e->getMessage(),
                    'shipment' => $shipment->toArray(),
                ]);
            }
        }

        // A sandbox estimate is a stand-in for a carrier with no credentials yet.
        // Once a real carrier prices a speed, an invented price must not compete
        // with it: it is usually the cheapest, so it would win and the shopper
        // would be shown (and charged) a figure no courier ever quoted.
        $realLevels = [];
        foreach ($quotes as $quote) {
            if (! $quote->sandbox) {
                $realLevels[$quote->serviceLevel] = true;
            }
        }
        $quotes = array_values(array_filter(
            $quotes,
            fn (DeliveryQuote $q) => ! $q->sandbox || ! isset($realLevels[$q->serviceLevel]),
        ));

        // Cheapest within each tier, then fastest tier first. Sorting has to
        // happen after the dedupe as well as before it — the dedupe rebuilds
        // the list keyed by service level, which does not preserve order.
        usort($quotes, fn (DeliveryQuote $a, DeliveryQuote $b) => $a->pricePaise <=> $b->pricePaise);

        // Only the speeds this kind of item can actually travel at: a dish is
        // never offered as a 3-day parcel, a sofa never to a rider.
        if ($shipment->allowedLevels !== null) {
            $quotes = array_values(array_filter(
                $quotes,
                fn (DeliveryQuote $q) => in_array($q->serviceLevel, $shipment->allowedLevels, true),
            ));
        }

        $best = $this->dedupeByServiceLevel($quotes);

        // The courier's clock starts when the order is ready, not when it is placed.
        if ($shipment->prepMinutes > 0) {
            $best = array_map(fn (DeliveryQuote $q) => $q->withExtraMinutes($shipment->prepMinutes), $best);
        }

        usort(
            $best,
            fn (DeliveryQuote $a, DeliveryQuote $b) => ServiceLevel::rank($a->serviceLevel)
                <=> ServiceLevel::rank($b->serviceLevel),
        );

        return $best;
    }

    /**
     * One option per service level — the cheapest. Showing a customer four
     * different "standard delivery" rows from four aggregators is noise; they
     * are choosing a speed, not a logistics vendor.
     *
     * @param  DeliveryQuote[]  $quotes
     * @return DeliveryQuote[]
     */
    private function dedupeByServiceLevel(array $quotes): array
    {
        $best = [];

        foreach ($quotes as $quote) {
            $existing = $best[$quote->serviceLevel] ?? null;
            if (! $existing || $quote->pricePaise < $existing->pricePaise) {
                $best[$quote->serviceLevel] = $quote;
            }
        }

        return array_values($best);
    }

    /**
     * The carrier to actually book with for a chosen service level, re-quoting
     * at booking time.
     *
     * A quote shown at checkout can be minutes old; by the time payment clears,
     * the rider network may be saturated. Re-quoting here means we book what is
     * actually available rather than what was available when the page rendered.
     */
    public function carrierFor(Shipment $shipment, string $serviceLevel): ?DeliveryCarrier
    {
        foreach ($this->quotes($shipment) as $quote) {
            if ($quote->serviceLevel === $serviceLevel) {
                return $this->registry->get($quote->carrier);
            }
        }

        // Nothing at the promised speed any more. Fall back to the slowest
        // option that exists rather than failing the order outright — a late
        // delivery is recoverable, a dropped order is not.
        $fallback = $this->quotes($shipment);

        return $fallback ? $this->registry->get(end($fallback)->carrier) : null;
    }

    /**
     * Build a Shipment from an order. Weight and dimensions come off the
     * products; anything missing falls back to a conservative per-item default
     * so a catalogue gap under-promises rather than under-charges.
     */
    public function shipmentForOrder(Order $order, string $pickupPincode = null): Shipment
    {
        $weight = 0;
        $longest = 0;
        $girth = 0;
        $count = 0;
        $order->loadMissing('items.product.category', 'items.product.seller');
        $profile = DeliveryProfile::forProducts($order->items->map(fn ($i) => $i->product)->filter()->all());
        $pickup = PickupLocation::forOrder($order);

        foreach ($order->items as $item) {
            $product = $item->product;
            $qty = (int) $item->quantity;
            $count += $qty;

            $weight += ($product?->weight_grams ?? config('delivery.default_item_weight_grams')) * $qty;
            $longest = max($longest, (int) ($product?->length_cm ?? 25));
            $girth = max($girth, (int) (
                ($product?->length_cm ?? 25) + ($product?->width_cm ?? 20) + ($product?->height_cm ?? 12)
            ));
        }

        return new Shipment(
            pickupPincode: $pickupPincode ?? $pickup['pincode'],
            dropPincode: (string) ($order->shipping_address['pincode'] ?? ''),
            weightGrams: $weight,
            longestSideCm: $longest,
            girthCm: $girth,
            valuePaise: (int) round($order->total_amount * 100),
            cod: $order->payment_method === 'COD',
            itemCount: $count,
            order: $order,
            allowedLevels: $profile['allowed'],
            prepMinutes: $profile['prep_minutes'],
            conflict: $profile['conflict'],
            preferFastest: $profile['profile'] === DeliveryProfile::INSTANT,
            pickup: $pickup,
        );
    }

    /**
     * Plan the delivery of a cart, before an order exists - what the checkout
     * screen quotes against.
     *
     * Items are grouped by where they are collected from: each seller's goods
     * leave from that seller's pickup address, so a basket from two sellers is
     * two parcels, quoted from their own places. (Items with no seller address
     * share the platform's.)
     *
     * @param  array<int, array{product_id: string, quantity: int}>  $items
     */
    public function planForCart(array $items, string $dropPincode, bool $cod, int $valuePaise): CartDeliveryPlan
    {
        $products = Product::with(['category:id,delivery_profile,prep_minutes', 'seller'])
            ->whereIn('id', array_column($items, 'product_id'))->get()->keyBy('id');

        // The speed is chosen once for the whole order, so what items may use is
        // decided across all of them.
        $whole = DeliveryProfile::forProducts($products);

        // Group by physical pickup point.
        $groups = [];
        $cartSubtotal = 0.0;
        foreach ($items as $line) {
            $product = $products->get($line['product_id']);
            $qty = (int) ($line['quantity'] ?? 1);
            $location = PickupLocation::forSeller($product?->seller);
            $key = PickupLocation::key($location);

            $groups[$key] ??= ['location' => $location, 'weight' => 0, 'longest' => 0, 'girth' => 0, 'count' => 0, 'value' => 0.0, 'products' => []];
            $g = &$groups[$key];

            $g['count'] += $qty;
            $g['weight'] += ($product?->weight_grams ?? config('delivery.default_item_weight_grams')) * $qty;
            $g['longest'] = max($g['longest'], (int) ($product?->length_cm ?? 25));
            $g['girth'] = max($g['girth'], (int) (
                ($product?->length_cm ?? 25) + ($product?->width_cm ?? 20) + ($product?->height_cm ?? 12)
            ));
            $lineValue = (float) ($product?->price ?? 0) * $qty;
            $g['value'] += $lineValue;
            $cartSubtotal += $lineValue;
            if ($product) {
                $g['products'][] = $product;
            }
            unset($g);
        }

        $shipments = [];
        $parcels = [];
        foreach ($groups as $g) {
            $own = DeliveryProfile::forProducts($g['products']);
            // Declared value is split by what each parcel is worth.
            $share = $cartSubtotal > 0 ? $g['value'] / $cartSubtotal : 1 / max(1, count($groups));

            $shipments[] = new Shipment(
                pickupPincode: $g['location']['pincode'],
                dropPincode: $dropPincode,
                weightGrams: $g['weight'],
                longestSideCm: $g['longest'],
                girthCm: $g['girth'],
                valuePaise: (int) round($valuePaise * $share),
                cod: $cod,
                itemCount: $g['count'],
                allowedLevels: $whole['allowed'],
                // Each seller prepares their own goods; the order waits for the slowest.
                prepMinutes: $own['prep_minutes'],
                conflict: $whole['conflict'],
                preferFastest: $whole['profile'] === DeliveryProfile::INSTANT,
                pickup: $g['location'],
            );
            $parcels[] = [
                'seller_id' => $g['location']['seller_id'],
                'seller_name' => $g['location']['seller_name'],
                'pickup_pincode' => $g['location']['pincode'],
                'pickup_city' => $g['location']['city'],
                'items' => $g['count'],
            ];
        }

        $quotes = $whole['conflict'] ? [] : $this->combinedQuotes($shipments);

        return new CartDeliveryPlan(
            shipments: $shipments,
            quotes: $quotes,
            parcels: $parcels,
            conflict: $whole['conflict'],
            preferFastest: $whole['profile'] === DeliveryProfile::INSTANT,
        );
    }

    /**
     * Options that cover every parcel. One parcel: just its quotes. Several: a
     * speed counts only if each parcel can go at it; the price is the parcels'
     * added up, and it arrives when the slowest does.
     *
     * @param  Shipment[]  $shipments
     * @return DeliveryQuote[] fastest first
     */
    private function combinedQuotes(array $shipments): array
    {
        if (count($shipments) === 1) {
            return $this->quotes($shipments[0]);
        }

        /** @var array<int, array<string, DeliveryQuote>> $perParcel each parcel's quotes by speed */
        $perParcel = array_map(
            fn (Shipment $s) => collect($this->quotes($s))->keyBy('serviceLevel')->all(),
            $shipments,
        );
        $levels = array_keys($perParcel[0] ?? []);

        $combined = [];
        foreach ($levels as $level) {
            $parts = array_map(fn (array $quotes) => $quotes[$level] ?? null, $perParcel);
            if (in_array(null, $parts, true)) {
                continue;   // some parcel cannot go at this speed
            }

            $carriers = array_unique(array_map(fn (DeliveryQuote $q) => $q->carrier, $parts));

            $combined[] = new DeliveryQuote(
                carrier: count($carriers) === 1 ? $carriers[0] : 'multiple',
                carrierLabel: count($carriers) === 1 ? $parts[0]->carrierLabel : 'Several couriers',
                serviceLevel: $level,
                pricePaise: (int) array_sum(array_map(fn (DeliveryQuote $q) => $q->pricePaise, $parts)),
                etaMinutes: (int) max(array_map(fn (DeliveryQuote $q) => $q->etaMinutes, $parts)),
                codSupported: ! in_array(false, array_map(fn (DeliveryQuote $q) => $q->codSupported, $parts), true),
                serviceCode: null,
                sandbox: in_array(true, array_map(fn (DeliveryQuote $q) => $q->sandbox, $parts), true),
                raw: ['parcels' => array_map(fn (DeliveryQuote $q) => ['carrier' => $q->carrier, 'price_paise' => $q->pricePaise, 'eta_minutes' => $q->etaMinutes], $parts)],
            );
        }

        usort($combined, fn (DeliveryQuote $a, DeliveryQuote $b) => ServiceLevel::rank($a->serviceLevel) <=> ServiceLevel::rank($b->serviceLevel));

        return $combined;
    }
}
