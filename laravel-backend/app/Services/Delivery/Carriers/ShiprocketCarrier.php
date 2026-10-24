<?php

namespace App\Services\Delivery\Carriers;

use App\Models\Order;
use App\Models\ReturnRequest;
use App\Services\Delivery\DeliveryQuote;
use App\Services\Delivery\ServiceLevel;
use App\Services\Delivery\Shipment;
use Illuminate\Support\Facades\Cache;

/**
 * Shiprocket — parcel aggregator. The workhorse for anything crossing a city.
 *
 * ─────────────────────────────────────────────────────────────────────────────
 * Of the five carriers here this is the one you can actually get credentials
 * for without a commercial negotiation: sign up, create an API user, and the
 * `/v1/external` endpoints below become live. The endpoint paths and the
 * token-exchange flow are from their public integration docs.
 *
 * Still verify the courier-serviceability response mapping against a live call
 * before go-live — the aggregator returns a long courier list whose shape has
 * changed across versions.
 * ─────────────────────────────────────────────────────────────────────────────
 */
class ShiprocketCarrier extends BaseCarrier
{
    public function key(): string
    {
        return 'shiprocket';
    }

    public function supportedServiceLevels(): array
    {
        return [ServiceLevel::EXPRESS, ServiceLevel::STANDARD];
    }

    public function isConfigured(): bool
    {
        return filled($this->config['email'] ?? null) && filled($this->config['password'] ?? null);
    }

    /**
     * Shiprocket issues a bearer token valid for 10 days. Cached for 9 so we
     * are not re-authenticating on every quote — their auth endpoint is rate
     * limited far more aggressively than the rate endpoint.
     */
    private function token(): ?string
    {
        // Keyed by the credentials that fetched it. One fixed key meant a changed
        // email or password kept using the old account's token for up to nine days.
        $cacheKey = 'shiprocket.token.'.substr(hash('sha256', ($this->config['email'] ?? '').'|'.($this->config['password'] ?? '')), 0, 16);

        return Cache::remember($cacheKey, now()->addDays(9), function () {
            $response = $this->http()->post($this->baseUrl().'/auth/login', [
                'email' => $this->config['email'],
                'password' => $this->config['password'],
            ]);

            return $response->successful() ? ($response->json()['token'] ?? null) : null;
        });
    }

    private function authHeaders(): array
    {
        return ['Authorization' => 'Bearer '.$this->token()];
    }

    public function quote(Shipment $shipment): array
    {
        if (! $this->isConfigured()) {
            return [
                $this->sandboxQuote($shipment, ServiceLevel::STANDARD, 'Shiprocket — Surface'),
                $this->sandboxQuote($shipment, ServiceLevel::EXPRESS, 'Shiprocket — Air'),
            ];
        }

        try {
            $response = $this->http($this->authHeaders())
                ->get($this->baseUrl().'/courier/serviceability/', [
                    'pickup_postcode' => $shipment->pickupPincode,
                    'delivery_postcode' => $shipment->dropPincode,
                    'cod' => $shipment->cod ? 1 : 0,
                    'weight' => round($shipment->billableGrams() / 1000, 2),
                ]);

            return $response->successful() ? $this->mapQuoteResponse($response->json()) : [];
        } catch (\Throwable $e) {
            $this->logFailure('quote', $e, ['shipment' => $shipment->toArray()]);

            return [];
        }
    }

    protected function mapQuoteResponse(array $body): array
    {
        $couriers = $body['data']['available_courier_companies'] ?? [];
        $quotes = [];

        foreach ($couriers as $courier) {
            $days = (int) ($courier['estimated_delivery_days'] ?? 4);

            $quotes[] = new DeliveryQuote(
                carrier: $this->key(),
                carrierLabel: 'Shiprocket — '.($courier['courier_name'] ?? 'Surface'),
                // Their own "is this air" flag is unreliable across couriers, so
                // classify on the promise instead: 1 day is express, else standard.
                serviceLevel: $days <= 1 ? ServiceLevel::EXPRESS : ServiceLevel::STANDARD,
                pricePaise: (int) round(((float) ($courier['rate'] ?? 0)) * 100),
                etaMinutes: max(1, $days) * 24 * 60,
                codSupported: (int) ($courier['cod'] ?? 0) === 1,
                serviceCode: (string) ($courier['courier_company_id'] ?? ''),
                raw: $courier,
            );
        }

        return $quotes;
    }

    public function book(Order $order, string $serviceLevel): array
    {
        if (! $this->isConfigured()) {
            return $this->sandboxBooking($order, $serviceLevel);
        }

        // Shiprocket books in four calls, and only the second one costs money:
        //   1. create the order            -> a shipment id (free)
        //   2. assign a courier            -> the tracking number (charges the wallet)
        //   3. request a pickup            -> a courier is sent to collect it
        //   4. make the label              -> something to stick on the parcel
        // Creating the order alone never produces a tracking number, which is
        // what the customer and the courier webhooks follow, so all four run.
        $shipmentId = $order->carrier_shipment_id;

        if (! $shipmentId) {
            $created = $this->httpOnce($this->authHeaders())
                ->post($this->baseUrl().'/orders/create/adhoc', $this->bookingPayload($order));

            if ($created->failed()) {
                throw new \RuntimeException('Shiprocket rejected the booking: '.$this->reason($created));
            }

            $shipmentId = (string) ($created->json('shipment_id') ?? '');

            if ($shipmentId === '') {
                throw new \RuntimeException('Shiprocket accepted the order but returned no shipment id.');
            }

            // Written down straight away: if a later step fails, trying again
            // continues with this shipment instead of creating a second one.
            $order->forceFill(['carrier_shipment_id' => $shipmentId])->save();
        }

        $assigned = $this->httpOnce($this->authHeaders())
            ->post($this->baseUrl().'/courier/assign/awb', array_filter([
                'shipment_id' => $shipmentId,
                'courier_id' => $this->courierToBook($order, $serviceLevel),
            ], fn ($v) => $v !== null));

        $data = $assigned->json('response.data') ?? [];
        $awb = $data['awb_code'] ?? null;

        if ($assigned->failed() || blank($awb)) {
            throw new \RuntimeException('Shiprocket could not assign a courier: '.$this->reason($assigned));
        }

        // The courier is assigned and paid for by now, so a failure below must
        // not undo the booking: the parcel can still be handed over, and the
        // pickup and label can be requested again from the Shiprocket panel.
        $this->afterAssign('pickup', fn () => $this->httpOnce($this->authHeaders())
            ->post($this->baseUrl().'/courier/generate/pickup', ['shipment_id' => [$shipmentId]]));

        $label = $this->afterAssign('label', fn () => $this->httpOnce($this->authHeaders())
            ->post($this->baseUrl().'/courier/generate/label', ['shipment_id' => [$shipmentId]]));

        return [
            'carrier' => $this->key(),
            'courier' => $data['courier_name'] ?? 'Shiprocket',
            'service_level' => $serviceLevel,
            'tracking_no' => (string) $awb,
            'label_url' => $label?->json('label_url'),
            'shipment_id' => $shipmentId,
            'sandbox' => false,
        ];
    }

    /**
     * The courier to book: the cheapest one that does the speed the shopper
     * paid for, found again now because the quote at checkout is not kept.
     * Null lets Shiprocket choose by the account's own courier priority.
     */
    protected function courierToBook(Order $order, string $serviceLevel): ?int
    {
        try {
            $shipment = app(\App\Services\Delivery\DeliveryAllocator::class)->shipmentForOrder($order);
            $quotes = collect($this->quote($shipment))->filter(fn (DeliveryQuote $q) => filled($q->serviceCode));

            $sameSpeed = $quotes->where('serviceLevel', $serviceLevel);
            $pick = ($sameSpeed->isNotEmpty() ? $sameSpeed : $quotes)->sortBy('pricePaise')->first();

            return $pick ? (int) $pick->serviceCode : null;
        } catch (\Throwable $e) {
            $this->logFailure('courier lookup', $e, ['order' => $order->order_number]);

            return null;
        }
    }

    /** A step that must not fail the booking. Returns its response, or null if it failed. */
    private function afterAssign(string $step, \Closure $call): ?\Illuminate\Http\Client\Response
    {
        try {
            $response = $call();

            if ($response->failed()) {
                \Illuminate\Support\Facades\Log::warning("[Shiprocket] {$step} request failed after booking", ['body' => $response->body()]);

                return null;
            }

            return $response;
        } catch (\Throwable $e) {
            $this->logFailure($step, $e, []);

            return null;
        }
    }

    /** What Shiprocket said went wrong, short enough to show a seller. */
    private function reason(\Illuminate\Http\Client\Response $response): string
    {
        $message = $response->json('message') ?? $response->json('response.data.awb_assign_error') ?? $response->body();

        return mb_substr(trim(is_string($message) ? $message : json_encode($message)), 0, 220);
    }

    protected function bookingPayload(Order $order): array
    {
        $drop = $order->shipping_address;

        return [
            'order_id' => $order->order_number,
            'order_date' => $order->created_at->toDateString(),
            'pickup_location' => \App\Services\Delivery\PickupLocation::forOrder($order)['code'] ?? $this->config['pickup_location'],
            'billing_customer_name' => $drop['name'] ?? '',
            'billing_address' => $drop['line1'] ?? '',
            'billing_address_2' => $drop['line2'] ?? '',
            'billing_city' => $drop['city'] ?? '',
            'billing_pincode' => $drop['pincode'] ?? '',
            'billing_state' => $drop['state'] ?? '',
            'billing_country' => 'India',
            'billing_email' => $order->user->email ?? '',
            'billing_phone' => $drop['phone'] ?? '',
            'shipping_is_billing' => true,
            'order_items' => $order->items->map(fn ($item) => [
                'name' => $item->product->title ?? 'Item',
                'sku' => $item->product->slug ?? $item->product_id,
                'units' => $item->quantity,
                'selling_price' => (float) $item->price,
            ])->all(),
            'payment_method' => $order->payment_method === 'COD' ? 'COD' : 'Prepaid',
            'sub_total' => (float) $order->total_amount,
            // Shiprocket wants cm/kg. Sent as the parcel envelope rather than
            // per-item because it books one shipment, not one per line.
            'length' => 25,
            'breadth' => 20,
            'height' => 12,
            'weight' => round(
                $order->items->sum(fn ($i) => ($i->product->weight_grams ?? 500) * $i->quantity) / 1000,
                2,
            ),
        ];
    }

    public function track(string $trackingNo): array
    {
        if (! $this->isConfigured()) {
            return [
                'tracking_no' => $trackingNo,
                'carrier' => $this->key(),
                'current_status' => 'IN_TRANSIT',
                'scans' => [
                    ['status' => 'Picked Up', 'location' => 'Bengaluru Hub', 'at' => now()->subDays(2)->toIso8601String()],
                    ['status' => 'In Transit', 'location' => 'Sorting Centre', 'at' => now()->subDay()->toIso8601String()],
                ],
                'sandbox' => true,
            ];
        }

        $response = $this->http($this->authHeaders())
            ->get($this->baseUrl().'/courier/track/awb/'.$trackingNo);

        $data = $response->successful() ? ($response->json()['tracking_data'] ?? []) : [];

        return [
            'tracking_no' => $trackingNo,
            'carrier' => $this->key(),
            'current_status' => $data['shipment_track'][0]['current_status'] ?? 'IN_TRANSIT',
            'scans' => collect($data['shipment_track_activities'] ?? [])->map(fn ($s) => [
                'status' => $s['activity'] ?? '',
                'location' => $s['location'] ?? '',
                'at' => $s['date'] ?? '',
            ])->all(),
            'sandbox' => false,
        ];
    }

    public function schedulePickup(ReturnRequest $return): array
    {
        if (! $this->isConfigured()) {
            return parent::schedulePickup($return);
        }

        $response = $this->http($this->authHeaders())
            ->post($this->baseUrl().'/orders/create/return', [
                'order_id' => $return->rma_number,
                'order_date' => now()->toDateString(),
            ]);

        $body = $response->successful() ? $response->json() : [];

        return [
            'carrier' => $this->key(),
            'pickup_tracking_no' => $body['awb_code'] ?? null,
            'scheduled_for' => now()->addDays(2)->toDateString(),
            'sandbox' => false,
        ];
    }
}
