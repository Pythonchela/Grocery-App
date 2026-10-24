<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Order;
use App\Services\Delivery\CarrierRegistry;
use App\Services\Delivery\Tracking\ShipmentTracker;
use App\Services\Delivery\Tracking\TrackingStatus;
use App\Services\NotificationService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;

/**
 * Where delivery partners push shipment updates: POST /webhooks/delivery/{carrier}.
 *
 * A partner is only accepted when a secret is configured for it and the request
 * proves it knows it - either an HMAC of the body, or a shared token header.
 * With no secret configured the endpoint refuses everything, so a half-finished
 * integration can't be used to forge "delivered" events.
 *
 * What the partner sends is read through the field aliases in
 * config/delivery.php, so a partner whose JSON uses different names is fixed by
 * editing config, not code.
 */
class DeliveryWebhookController extends Controller
{
    /** Order statuses in the order an order moves through them. */
    private const ORDER_FLOW = ['PENDING', 'CONFIRMED', 'PACKED', 'SHIPPED', 'OUT_FOR_DELIVERY', 'DELIVERED'];

    public function __construct(
        private readonly CarrierRegistry $registry,
        private readonly ShipmentTracker $tracker,
        private readonly NotificationService $notifications,
    ) {}

    public function handle(Request $request, string $carrierKey)
    {
        $carrier = $this->registry->get($carrierKey);

        if (! $carrier) {
            return response()->json(['status' => 'error', 'message' => 'Unknown carrier'], 404);
        }

        if (! $this->authentic($request, $carrierKey)) {
            return response()->json(['status' => 'error', 'message' => 'Unauthorised'], 401);
        }

        $events = $carrier->parseWebhook($request->all());
        $accepted = 0;

        foreach ($events as $event) {
            $order = Order::where('tracking_no', $event['tracking_no'])
                ->where(fn ($q) => $q->where('carrier', $carrierKey)->orWhereNull('carrier'))
                ->first();

            if (! $order) {
                continue;
            }

            $status = TrackingStatus::fromText($event['status_text'] ?? '');

            $this->tracker->record($order, [
                'status' => $status,
                'description' => $event['status_text'] ?? null,
                'location' => $event['location'] ?? null,
                'at' => $event['at'] ?? null,
                'lat' => $event['lat'] ?? null,
                'lng' => $event['lng'] ?? null,
                'source' => 'webhook',
                'raw' => $event['raw'] ?? null,
            ]);

            $this->advanceOrder($order, $status);
            $accepted++;
        }

        // Always 200 once authenticated: a partner that gets an error retries the
        // same payload forever, and an unmatched AWB is not their fault.
        return response()->json(['status' => 'success', 'received' => count($events), 'accepted' => $accepted]);
    }

    /** Move the order forward - never backward - and tell the shopper. */
    private function advanceOrder(Order $order, string $shipmentStatus): void
    {
        $target = TrackingStatus::toOrderStatus($shipmentStatus);

        if (! $target || in_array($order->status, ['CANCELLED', 'DELIVERED'], true)) {
            return;
        }

        $from = array_search($order->status, self::ORDER_FLOW, true);
        $to = array_search($target, self::ORDER_FLOW, true);

        if ($from === false || $to === false || $to <= $from) {
            return;
        }

        $changes = ['status' => $target];

        // A courier saying "delivered" must do what staff marking it delivered
        // does (OrderController::update): start the return window, and count
        // cash-on-delivery as collected.
        if ($target === 'DELIVERED') {
            $changes['delivered_at'] = $order->delivered_at ?? now();

            if ($order->payment_method === 'COD' && $order->payment_status === 'PENDING') {
                $changes['payment_status'] = 'PAID';
            }
        }

        $order->update($changes);

        // Sellers' lines follow the order, so a delivered order leaves their
        // "to ship" list and their takings are settled.
        app(\App\Services\FulfilmentService::class)->syncLinesToOrderStatus($order);

        try {
            $this->notifications->orderStatusChanged($order->load('user'), $target);
        } catch (\Throwable $e) {
            Log::warning('Order status notification failed', ['order' => $order->id, 'error' => $e->getMessage()]);
        }
    }

    private function authentic(Request $request, string $carrierKey): bool
    {
        $config = config("delivery.carriers.{$carrierKey}", []);
        $secret = (string) ($config['webhook_secret'] ?? '');
        $token = (string) ($config['webhook_token'] ?? '');

        if ($secret !== '') {
            $header = (string) $request->header($config['webhook_signature_header'] ?? 'X-Signature', '');
            $expected = hash_hmac('sha256', $request->getContent(), $secret);

            if ($header !== '' && (hash_equals($expected, $header) || hash_equals('sha256='.$expected, $header))) {
                return true;
            }
        }

        if ($token !== '') {
            $given = (string) $request->header($config['webhook_token_header'] ?? 'X-Api-Key', '');

            if ($given !== '' && hash_equals($token, $given)) {
                return true;
            }
        }

        return false;
    }
}
