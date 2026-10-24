<?php

namespace App\Services;

use App\Services\Contracts\PaymentGateway;
use App\Services\Payments\InvalidWebhookException;
use Illuminate\Http\Client\ConnectionException;
use Illuminate\Http\Client\PendingRequest;
use Illuminate\Http\Client\Response;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

/**
 * Razorpay driver (Orders API).
 *
 * Flow: `createIntent` opens a Razorpay *order* for the exact amount we priced.
 * The customer pays in Razorpay's checkout window, which hands the client a
 * payment id and a signature. `verify` then refuses to believe either until
 *
 *   1. the signature matches HMAC-SHA256(order_id|payment_id, key_secret) —
 *      proof the pair came from Razorpay and not from the client, and
 *   2. Razorpay itself says that payment belongs to *this* order and is
 *      captured (an "authorized" payment is captured here, so money is taken
 *      rather than left to lapse and auto-refund).
 *
 * The amount needs no separate check: Razorpay will not accept a payment on an
 * order for any other figure.
 *
 * Network or provider failures throw PaymentGatewayException instead of
 * returning "not verified" — being unable to ask is not the same as being told
 * no, and the customer may well have been charged.
 */
class RazorpayGateway implements PaymentGateway
{
    /** Razorpay caps `receipt` at 40 characters. */
    private const RECEIPT_MAX = 40;

    /** Smallest chargeable amount: ₹1. */
    private const MIN_PAISE = 100;

    public function __construct(
        private readonly string $keyId,
        private readonly string $keySecret,
        private readonly ?string $webhookSecret = null,
        private readonly string $baseUrl = 'https://api.razorpay.com/v1',
    ) {}

    /** Null while credentials are missing, so the gateway simply isn't offered. */
    public static function fromConfig(): ?static
    {
        $keyId = config('services.razorpay.key_id');
        $secret = config('services.razorpay.key_secret');

        return filled($keyId) && filled($secret)
            ? new static($keyId, $secret, config('services.razorpay.webhook_secret'))
            : null;
    }

    public function key(): string
    {
        return 'razorpay';
    }

    public function createIntent(float $amount, string $receipt, array $meta = []): array
    {
        $paise = (int) round($amount * 100);

        if ($paise < self::MIN_PAISE) {
            throw new PaymentGatewayException(
                'This order is below the minimum online payment of ₹1.',
                "amount {$paise} paise",
            );
        }

        $order = $this->call('create order', fn (PendingRequest $r) => $r->post('/orders', [
            'amount' => $paise,
            'currency' => 'INR',
            'receipt' => substr($receipt, 0, self::RECEIPT_MAX),
            // Razorpay notes are string-valued and capped at 256 chars each.
            'notes' => array_map(fn ($v) => substr((string) $v, 0, 256), $meta),
        ]));

        return [
            'id' => $order['id'],
            'amount' => (int) $order['amount'],
            'currency' => $order['currency'],
            // Public half of the key pair; the client needs it to open checkout.
            'client' => ['key_id' => $this->keyId],
            'is_mock' => false,
        ];
    }

    public function verify(string $intentId, array $evidence): array
    {
        $paymentId = $evidence['payment_id'] ?? null;
        $signature = $evidence['signature'] ?? null;
        $unverified = ['verified' => false, 'payment_id' => $paymentId, 'method' => null];

        if (blank($paymentId) || blank($signature)) {
            return $unverified;
        }

        $expected = hash_hmac('sha256', $intentId.'|'.$paymentId, $this->keySecret);

        if (! hash_equals($expected, $signature)) {
            Log::warning('[Razorpay] signature mismatch', ['order' => $intentId, 'payment' => $paymentId]);

            return $unverified;
        }

        $payment = $this->call('fetch payment', fn (PendingRequest $r) => $r->get("/payments/{$paymentId}"));

        // A validly signed pair for a *different* order must not settle this one.
        if (($payment['order_id'] ?? null) !== $intentId) {
            Log::warning('[Razorpay] payment belongs to another order', [
                'expected' => $intentId,
                'actual' => $payment['order_id'] ?? null,
                'payment' => $paymentId,
            ]);

            return $unverified;
        }

        if (($payment['status'] ?? null) === 'authorized') {
            $payment = $this->call('capture payment', fn (PendingRequest $r) => $r->post("/payments/{$paymentId}/capture", [
                'amount' => (int) $payment['amount'],
                'currency' => $payment['currency'] ?? 'INR',
            ]));
        }

        if (($payment['status'] ?? null) !== 'captured') {
            return $unverified;
        }

        return [
            'verified' => true,
            'payment_id' => $paymentId,
            'method' => strtoupper((string) ($payment['method'] ?? '')) ?: null,
        ];
    }

    public function refund(string $paymentId, int $amountPaise, string $reason, string $reference): array
    {
        $refund = $this->call('refund payment', fn (PendingRequest $r) => $r->post("/payments/{$paymentId}/refund", [
            'amount' => $amountPaise,
            'speed' => 'normal',
            'receipt' => substr($reference, 0, self::RECEIPT_MAX),
            'notes' => ['reason' => substr($reason, 0, 256)],
        ]));

        return [
            'id' => $refund['id'],
            // Razorpay says 'processed' or 'pending'; anything not yet settled is pending.
            'status' => ($refund['status'] ?? '') === 'processed' ? 'PROCESSED' : 'PENDING',
            'amount' => (int) $refund['amount'],
        ];
    }

    /**
     * Razorpay signs the raw body with the webhook secret (a separate secret
     * from the API key, set when the webhook is created in the dashboard) and
     * sends it as X-Razorpay-Signature.
     */
    public function parseWebhook(string $payload, array $headers): array
    {
        if (blank($this->webhookSecret)) {
            throw new InvalidWebhookException('RAZORPAY_WEBHOOK_SECRET is not set, so webhooks cannot be trusted.');
        }

        $expected = hash_hmac('sha256', $payload, $this->webhookSecret);

        if (! hash_equals($expected, $headers['x-razorpay-signature'] ?? '')) {
            throw new InvalidWebhookException('Webhook signature mismatch.');
        }

        $body = json_decode($payload, true);
        $event = $body['event'] ?? null;
        $payment = $body['payload']['payment']['entity'] ?? [];
        $refund = $body['payload']['refund']['entity'] ?? [];

        return match ($event) {
            'payment.captured', 'payment.failed' => [[
                'type' => $event,
                'provider_order_id' => $payment['order_id'] ?? null,
                'provider_payment_id' => $payment['id'] ?? null,
                'provider_refund_id' => null,
                'amount_paise' => (int) ($payment['amount'] ?? 0),
                'method' => isset($payment['method']) ? strtoupper($payment['method']) : null,
                'reason' => $payment['error_description'] ?? null,
            ]],
            'refund.processed', 'refund.failed' => [[
                'type' => $event,
                'provider_order_id' => null,
                'provider_payment_id' => $refund['payment_id'] ?? null,
                'provider_refund_id' => $refund['id'] ?? null,
                'amount_paise' => (int) ($refund['amount'] ?? 0),
                'method' => null,
                'reason' => null,
            ]],
            default => [], // events the platform has no use for
        };
    }

    /**
     * Run one API call and return its decoded body, turning every failure into
     * a PaymentGatewayException with a customer-safe message.
     *
     * @param  callable(PendingRequest): Response  $request
     */
    private function call(string $what, callable $request): array
    {
        $client = Http::baseUrl($this->baseUrl)
            ->withBasicAuth($this->keyId, $this->keySecret)
            ->acceptJson()
            ->asJson()
            ->timeout(20);

        try {
            $response = $request($client);
        } catch (ConnectionException $e) {
            Log::error("[Razorpay] could not {$what}: connection failed", ['error' => $e->getMessage()]);

            throw new PaymentGatewayException(
                'We could not reach the payment provider. Please try again in a moment.',
                $e->getMessage(),
            );
        }

        if ($response->failed()) {
            $detail = $response->json('error.description') ?? $response->body();
            Log::error("[Razorpay] could not {$what}", ['status' => $response->status(), 'detail' => $detail]);

            throw new PaymentGatewayException(
                $response->serverError()
                    ? 'The payment provider is having trouble. Please try again in a moment.'
                    : 'The payment provider rejected this request.',
                $detail,
            );
        }

        return $response->json() ?? [];
    }
}
