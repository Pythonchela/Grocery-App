<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\Payments\InvalidWebhookException;
use App\Services\Payments\PaymentGatewayManager;
use App\Services\Payments\PaymentService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;

/**
 * One webhook endpoint for every gateway: POST /webhooks/payments/{provider}.
 *
 * Each gateway authenticates and translates its own payloads (that is what its
 * driver's `parseWebhook` is for); what happens next is the platform's business
 * and identical for all of them. Adding a gateway adds no route.
 *
 * Public by necessity — the gateway is not a logged-in user — so the signature
 * check is the only thing standing in front of it, and a failure is a flat 400
 * with no detail.
 */
class PaymentWebhookController extends Controller
{
    public function handle(
        Request $request,
        string $provider,
        PaymentGatewayManager $gateways,
        PaymentService $payments,
    ) {
        if (! $gateways->has($provider)) {
            return response()->json(['status' => 'error', 'message' => 'Unknown gateway.'], 404);
        }

        // Header names arrive as arrays of values; drivers want one string each.
        $headers = array_map(fn ($v) => (string) ($v[0] ?? ''), $request->headers->all());

        try {
            $events = $gateways->driver($provider)->parseWebhook($request->getContent(), $headers);
        } catch (InvalidWebhookException $e) {
            Log::warning('[Payments] rejected a webhook', ['provider' => $provider, 'reason' => $e->getMessage()]);

            return response()->json(['status' => 'error', 'message' => 'Invalid webhook.'], 400);
        }

        foreach ($events as $event) {
            $outcome = $payments->handleEvent($provider, $event);
            Log::info('[Payments] webhook handled', ['provider' => $provider, 'event' => $event['type'], 'outcome' => $outcome]);
        }

        // Always acknowledge a genuine delivery. A non-2xx makes the gateway
        // retry, which is only useful for failures worth retrying.
        return response()->json(['status' => 'ok']);
    }
}
