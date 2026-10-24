<?php

namespace App\Services\Mock;

use App\Services\Contracts\PaymentGateway;
use App\Services\Payments\InvalidWebhookException;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;

/**
 * Sandbox payment driver. Always succeeds — it exists so the checkout and
 * refund flows can be exercised end-to-end without live gateway keys.
 * NOT a real gateway: it performs no capture, no signature verification,
 * and moves no money.
 */
class MockPaymentGateway implements PaymentGateway
{
    public function key(): string
    {
        return 'mock';
    }

    public function createIntent(float $amount, string $receipt, array $meta = []): array
    {
        $intent = [
            'id' => 'order_mock_'.Str::random(14),
            'amount' => (int) round($amount * 100), // paise
            'currency' => 'INR',
            'client' => [],
            'is_mock' => true,
        ];

        Log::info('[MockPaymentGateway] intent created', $intent + ['receipt' => $receipt, 'meta' => $meta]);

        return $intent;
    }

    public function verify(string $intentId, array $evidence): array
    {
        return [
            'verified' => true,
            'payment_id' => ($evidence['payment_id'] ?? null) ?: 'pay_mock_'.Str::random(14),
            'method' => 'UPI',
        ];
    }

    public function refund(string $paymentId, int $amountPaise, string $reason, string $reference): array
    {
        $refund = [
            'id' => 'rfnd_mock_'.Str::random(14),
            'status' => 'PROCESSED',
            'amount' => $amountPaise,
        ];

        Log::info('[MockPaymentGateway] refund issued', $refund + [
            'payment_id' => $paymentId,
            'reason' => $reason,
            'reference' => $reference,
        ]);

        return $refund;
    }

    public function parseWebhook(string $payload, array $headers): array
    {
        throw new InvalidWebhookException('The sandbox gateway does not send webhooks.');
    }
}
