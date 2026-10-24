<?php

namespace App\Services\Delivery\Tracking;

use App\Models\Order;
use App\Models\TrackingEvent;
use App\Services\Contracts\DeliveryCarrier;
use App\Services\Delivery\CarrierRegistry;
use Carbon\Carbon;
use Illuminate\Support\Facades\Log;

/**
 * One answer to "where is my order?", whichever partner is carrying it.
 *
 * Partners report differently: some push events to a webhook, some only answer
 * when asked, a few (rider networks) also give a live position. This class takes
 * whatever each one gives - stored webhook events, a fresh poll, nothing at all -
 * and returns a single shape the apps render: a status, a timeline, an expected
 * date, and a position only when there genuinely is one.
 *
 * It never throws on a partner's behalf. A failed poll just means the shopper
 * sees what we already know.
 */
class ShipmentTracker
{
    public function __construct(private readonly CarrierRegistry $registry) {}

    /**
     * @return array<string, mixed>
     */
    public function snapshot(Order $order, bool $refresh = true): array
    {
        $carrier = $order->carrier ? $this->registry->get($order->carrier) : null;
        $raw = [];

        if ($refresh && $order->tracking_no && $carrier) {
            $raw = $this->poll($carrier, $order);
            $this->storePolled($order, $raw);
        }

        $events = TrackingEvent::where('order_id', $order->id)
            ->orderByDesc('occurred_at')
            ->get();

        $timeline = $events->map(fn (TrackingEvent $e) => [
            'status' => $e->status,
            'label' => TrackingStatus::label($e->status),
            'description' => $e->description,
            'location' => $e->location,
            'at' => $e->occurred_at?->toIso8601String(),
        ])->values()->all();

        foreach ((array) ($raw['sandbox'] ?? false ? ($raw['scans'] ?? []) : []) as $scan) {
            $text = trim((string) ($scan['status'] ?? ''));
            if ($text !== '') {
                $timeline[] = [
                    'status' => TrackingStatus::fromText($text),
                    'label' => $text,
                    'description' => null,
                    'location' => $scan['location'] ?? null,
                    'at' => $scan['at'] ?? null,
                ];
            }
        }

        // Always at least the first rung: the order was placed.
        $timeline[] = [
            'status' => TrackingStatus::CONFIRMED,
            'label' => 'Order confirmed',
            'description' => null,
            'location' => null,
            'at' => $order->created_at?->toIso8601String(),
        ];

        // Newest first.
        usort($timeline, fn ($a, $b) => $this->time($b['at'] ?? null)->getTimestamp() <=> $this->time($a['at'] ?? null)->getTimestamp());

        $latest = $events->first();
        $status = $order->status === 'CANCELLED'
            ? TrackingStatus::CANCELLED
            : $this->furthest(
                TrackingStatus::fromOrderStatus($order->status),
                $latest?->status,
            );

        $mode = TrackingMode::for($order);
        $position = $mode === TrackingMode::LIVE_MAP ? ($raw['position'] ?? null) : null;

        return [
            'mode' => $mode,
            'status' => $status,
            'status_label' => TrackingStatus::label($status),
            'location' => $latest?->location,
            'events' => $timeline,
            'expected_by' => $order->promised_by?->toIso8601String(),
            'track_url' => $this->trackUrl($order),
            'carrier_label' => $carrier?->label() ?? $order->courier,
            'tracking_no' => $order->tracking_no,
            'position' => $position && ($position['lat'] ?? null) !== null ? $position : null,
            'rider' => $mode === TrackingMode::LIVE_MAP ? ($raw['rider'] ?? null) : null,
            'eta_minutes' => $raw['eta_minutes'] ?? null,
            'sandbox' => (bool) ($raw['sandbox'] ?? false),
        ];
    }

    /** @return array<string, mixed> */
    private function poll(DeliveryCarrier $carrier, Order $order): array
    {
        try {
            return $carrier->track($order->tracking_no);
        } catch (\Throwable $e) {
            Log::warning('Tracking poll failed', ['carrier' => $carrier->key(), 'order' => $order->id, 'error' => $e->getMessage()]);

            return [];
        }
    }

    /** Turn a partner's poll response into stored events. */
    private function storePolled(Order $order, array $raw): void
    {
        // Sandbox scans are invented on every call; storing them would pile up
        // a fresh "event" each poll. They are shown, not kept (see snapshot()).
        if (! empty($raw['sandbox'])) {
            return;
        }

        $scans = (array) ($raw['scans'] ?? []);

        foreach ($scans as $scan) {
            $text = trim((string) ($scan['status'] ?? ''));
            if ($text === '') {
                continue;
            }

            $this->record($order, [
                'status' => TrackingStatus::fromText($text),
                'description' => $text,
                'location' => $scan['location'] ?? null,
                'at' => $scan['at'] ?? null,
                'source' => 'poll',
                'raw' => $scan,
            ]);
        }

        // A partner with no scan list but a current status still tells us one thing.
        if ($scans === [] && ! empty($raw['current_status']) && empty($raw['sandbox'])) {
            $this->record($order, [
                'status' => TrackingStatus::fromText((string) $raw['current_status']),
                'description' => (string) $raw['current_status'],
                'location' => null,
                'at' => null,
                'source' => 'poll',
                'raw' => ['current_status' => $raw['current_status']],
            ]);
        }
    }

    /**
     * Store one event once. The same scan arrives by webhook and again on the
     * next poll; the fingerprint is what stops it appearing twice.
     *
     * @param  array{status: string, description?: ?string, location?: ?string, at?: mixed, source?: string, raw?: mixed, lat?: mixed, lng?: mixed}  $event
     */
    public function record(Order $order, array $event): ?TrackingEvent
    {
        $at = $this->time($event['at'] ?? null);
        $location = isset($event['location']) ? trim((string) $event['location']) : null;
        $status = $event['status'];

        $fingerprint = substr(sha1($status.'|'.strtolower((string) $location).'|'.$at->format('Y-m-d H:i')), 0, 40);

        $stored = TrackingEvent::firstOrCreate(
            ['order_id' => $order->id, 'fingerprint' => $fingerprint],
            [
                'carrier' => $order->carrier,
                'tracking_no' => $order->tracking_no,
                'status' => $status,
                'description' => isset($event['description']) ? mb_substr((string) $event['description'], 0, 255) : null,
                'location' => $location !== '' ? $location : null,
                'lat' => $event['lat'] ?? null,
                'lng' => $event['lng'] ?? null,
                'occurred_at' => $at,
                'source' => $event['source'] ?? 'poll',
                'raw' => is_array($event['raw'] ?? null) ? $event['raw'] : null,
            ],
        );

        return $stored;
    }

    /** Dates arrive as ISO strings, "11 Oct 2026, 04:10 PM", epoch seconds, or not at all. */
    private function time(mixed $value): Carbon
    {
        if ($value === null || $value === '') {
            return now();
        }

        try {
            if (is_numeric($value)) {
                return Carbon::createFromTimestamp((int) $value > 20000000000 ? (int) ($value / 1000) : (int) $value);
            }

            return Carbon::parse((string) $value);
        } catch (\Throwable) {
            return now();
        }
    }

    /** Never report a status behind where the order record already is. */
    private function furthest(string $a, ?string $b): string
    {
        if ($b === null) {
            return $a;
        }

        // Exceptions (delayed, failed attempt, returning) are the latest news
        // and must show even though they are not "ahead" on the happy path.
        if (! in_array($b, TrackingStatus::PROGRESS, true)) {
            return $a === TrackingStatus::DELIVERED ? $a : $b;
        }

        $ai = array_search($a, TrackingStatus::PROGRESS, true);
        $bi = array_search($b, TrackingStatus::PROGRESS, true);

        return ($bi === false || ($ai !== false && $ai >= $bi)) ? $a : $b;
    }

    private function trackUrl(Order $order): ?string
    {
        if (! $order->tracking_no || ! $order->carrier) {
            return null;
        }

        $template = config("delivery.carriers.{$order->carrier}.track_url");

        return $template ? str_replace('{awb}', rawurlencode($order->tracking_no), $template) : null;
    }
}
