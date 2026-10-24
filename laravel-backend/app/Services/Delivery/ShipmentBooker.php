<?php

namespace App\Services\Delivery;

use App\Models\Order;
use App\Services\Contracts\LogisticsProvider;
use Illuminate\Support\Facades\DB;

/**
 * Books the courier for an order, once.
 *
 * Booking spends money (the carrier charges the shipper's wallet when a courier
 * is assigned), so the one rule here is that asking twice never books twice: the
 * order row is locked while the carrier is called, and an order that already has
 * a tracking number simply returns it.
 *
 * Used by the seller's "ship" action (automatic booking) and by the admin
 * "create shipment" button, so both behave the same.
 */
class ShipmentBooker
{
    public function __construct(private readonly LogisticsProvider $logistics) {}

    /** Whether shipping an order should book the courier without the seller typing anything. */
    public static function automatic(): bool
    {
        $setting = config('delivery.auto_book', 'on');

        return ! in_array(strtolower(trim((string) $setting)), ['off', '0', 'false', 'no', ''], true);
    }

    /**
     * @return array<string, mixed> at least courier, tracking_no and already_booked
     *
     * @throws \RuntimeException when the carrier cannot or will not book it
     */
    public function book(Order $order): array
    {
        return DB::transaction(function () use ($order) {
            $locked = Order::whereKey($order->id)->lockForUpdate()->firstOrFail();

            if ($locked->label_generated && filled($locked->tracking_no)) {
                return [
                    'courier' => $locked->courier,
                    'tracking_no' => $locked->tracking_no,
                    'already_booked' => true,
                ];
            }

            $shipment = $this->logistics->createShipment($locked);

            $locked->update([
                'courier' => $shipment['courier'] ?? $locked->courier,
                'tracking_no' => $shipment['tracking_no'] ?? null,
                'label_generated' => true,
            ]);

            return $shipment + ['already_booked' => false];
        });
    }
}
