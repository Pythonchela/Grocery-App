<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Order;
use App\Services\Delivery\CarrierRegistry;
use App\Services\Delivery\DeliveryAllocator;
use App\Services\Delivery\DeliveryQuote;
use App\Services\Delivery\ServiceLevel;
use Illuminate\Http\Request;

class DeliveryController extends Controller
{
    public function __construct(
        private readonly DeliveryAllocator $allocator,
        private readonly CarrierRegistry $registry,
    ) {}

    /**
     * Delivery options for a cart, before an order exists.
     *
     * The client sends what it has (items and a destination); the server does
     * the weighing, the carrier shortlisting and the pricing. Deliberately not
     * trusting a client-supplied weight — that is the number the shipping fee
     * is computed from, and it is exactly the field someone would tamper with.
     */
    public function quote(Request $request)
    {
        $validated = $request->validate([
            'pincode' => 'required|string|regex:/^[1-9][0-9]{5}$/',
            'items' => 'required|array|min:1',
            'items.*.product_id' => 'required|string',
            'items.*.quantity' => 'required|integer|min:1|max:50',
            'cod' => 'sometimes|boolean',
            'order_value' => 'sometimes|numeric|min:0',
        ]);

        // A shop that does not deliver to this PIN code has nothing to quote.
        $areaProblem = app(\App\Services\Pricing\ShopRules::class)
            ->areaProblem(array_column($validated['items'], 'product_id'), $validated['pincode']);

        if ($areaProblem) {
            return response()->json([
                'status' => 'success',
                'data' => [
                    'pincode' => $validated['pincode'],
                    'recommended_service_level' => null,
                    'serviceable' => false,
                    'message' => $areaProblem,
                    'options' => [],
                    'shipment' => null,
                    'parcels' => [],
                    'sandbox' => ! $this->registry->hasLiveCarrier(),
                ],
            ]);
        }

        $plan = $this->allocator->planForCart(
            items: $validated['items'],
            dropPincode: $validated['pincode'],
            cod: (bool) ($validated['cod'] ?? false),
            valuePaise: (int) round((float) ($validated['order_value'] ?? 0) * 100),
        );

        $quotes = $plan->quotes;

        // Free shipping is a merchandising decision, not a carrier one: we still
        // pay the courier, we just don't pass it on. Applied to the standard
        // option only — someone choosing a 40-minute rider delivery is not
        // expecting that to be free because they spent ₹2,000.
        $freeAbove = (int) \App\Models\Setting::get('delivery.free_above', config('delivery.free_above'));
        $orderValue = (float) ($validated['order_value'] ?? 0);

        $options = array_map(function (DeliveryQuote $q) use ($freeAbove, $orderValue) {
            $row = $q->toArray();
            $row['label'] = ServiceLevel::label($q->serviceLevel);
            $row['description'] = ServiceLevel::description($q->serviceLevel);

            if ($q->serviceLevel === ServiceLevel::STANDARD && $orderValue >= $freeAbove) {
                $row['price_paise'] = 0;
                $row['price'] = 0;
                $row['free_reason'] = "Free on orders over ₹{$freeAbove}";
            }

            return $row;
        }, $quotes);

        // What the app should pre-select. Ordinary goods and parcels: the cheapest
        // (the fast option is an upsell). Hot food: the fastest, because nobody
        // wants a pizza "same day".
        $recommended = $plan->preferFastest
            ? ($options[0]['service_level'] ?? null)
            : (collect($options)->sortBy('price_paise')->first()['service_level'] ?? null);

        return response()->json([
            'status' => 'success',
            'data' => [
                'pincode' => $validated['pincode'],
                'recommended_service_level' => $recommended,
                'serviceable' => count($options) > 0,
                // Set when the cart mixes items that travel differently (hot food
                // with a courier parcel): the app shows it instead of "no delivery".
                'message' => $plan->conflict,
                'options' => $options,
                'shipment' => $plan->first()?->toArray(),
                // One entry per pickup point: a basket from two sellers is two parcels.
                'parcels' => $plan->parcels,
                // Surfaced so the UI can badge sandbox pricing honestly rather
                // than presenting invented numbers as real quotes.
                'sandbox' => ! $this->registry->hasLiveCarrier(),
            ],
        ]);
    }

    /**
     * Staff: where any order's parcel is, in the same normalised form shoppers
     * get: a status, a timeline of events, an expected date.
     */
    public function adminTrack(string $id, \App\Services\Delivery\Tracking\ShipmentTracker $tracker)
    {
        $order = Order::findOrFail($id);

        return response()->json(['status' => 'success', 'data' => [
            'order_number' => $order->order_number,
            'courier' => $order->courier,
            'tracking_no' => $order->tracking_no,
            'label_generated' => (bool) $order->label_generated,
            'tracking' => $order->tracking_no ? $tracker->snapshot($order) : null,
        ]]);
    }

    /**
     * Live tracking for an order, asked of the carrier that actually booked it.
     */
    public function track(Request $request, string $id, \App\Services\Delivery\Tracking\ShipmentTracker $tracker)
    {
        $order = Order::where('id', $id)
            ->where('user_id', $request->user()->id)
            ->firstOrFail();

        // One normalised answer whichever partner is carrying it: a status,
        // a timeline, an expected date, and a position only for live-map orders.
        $snapshot = $tracker->snapshot($order);

        if (! $order->tracking_no) {
            return response()->json([
                'status' => 'success',
                'data' => $snapshot + [
                    'current_status' => $order->status,
                    'message' => 'Not dispatched yet — tracking appears once the courier collects it.',
                    'order_status' => $order->status,
                    'service_level' => $order->service_level,
                    'service_label' => ServiceLevel::label($order->service_level ?? ServiceLevel::STANDARD),
                    'promised_by' => $order->promised_by?->toIso8601String(),
                    'courier' => $order->courier,
                ],
            ]);
        }

        // Old keys (current_status, scans, rider...) stay for clients that read them.
        $legacy = ['tracking_no' => $order->tracking_no, 'current_status' => $order->status];

        return response()->json([
            'status' => 'success',
            'data' => $snapshot + $legacy + [
                'order_status' => $order->status,
                'service_level' => $order->service_level,
                'service_label' => ServiceLevel::label($order->service_level ?? ServiceLevel::STANDARD),
                'promised_by' => $order->promised_by?->toIso8601String(),
                'courier' => $order->courier,
            ],
        ]);
    }

    /**
     * Which partners this deployment can book with, and whether each is live.
     * Admin-facing: the answer to "why did that ship with Porter".
     */
    public function carriers()
    {
        return response()->json([
            'status' => 'success',
            'data' => collect($this->registry->enabled())->map(fn ($c) => [
                'key' => $c->key(),
                'label' => $c->label(),
                'service_levels' => $c->supportedServiceLevels(),
                'configured' => $c->isConfigured(),
                'mode' => $c->isConfigured() ? 'live' : 'sandbox',
            ])->values(),
        ]);
    }
}
