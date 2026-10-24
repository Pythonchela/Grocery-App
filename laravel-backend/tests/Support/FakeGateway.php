<?php

namespace Tests\Support;

use App\Services\Contracts\PaymentGateway;
use App\Services\Payments\InvalidWebhookException;
use App\Services\PaymentGatewayException;

/**
 * A stand-in for "some other gateway" — the proof that the platform is not
 * married to Razorpay. Deliberately shaped nothing like it: its client config is
 * a publishable token, its evidence is a single `token`, its webhook is
 * authenticated by a header. If the platform only worked because every gateway
 * looked like Razorpay, tests written against this would fail.
 */
class FakeGateway implements PaymentGateway
{
    /** @var list<array{payment_id: string, paise: int, reference: string}> */
    public array $refunds = [];

    public string $refundStatus = 'PROCESSED';

    public bool $failRefunds = false;

    private int $counter = 0;

    public function __construct(private readonly string $key = 'fakepay') {}

    public function key(): string
    {
        return $this->key;
    }

    public function createIntent(float $amount, string $receipt, array $meta = []): array
    {
        return [
            'id' => $this->key.'_order_'.(++$this->counter),
            'amount' => (int) round($amount * 100),
            'currency' => 'INR',
            'client' => ['publishable_token' => 'pk_'.$this->key],
            'is_mock' => false,
        ];
    }

    /** Valid evidence is `['token' => 'good-<intent id>']`. */
    public function verify(string $intentId, array $evidence): array
    {
        $good = ($evidence['token'] ?? null) === 'good-'.$intentId;

        return [
            'verified' => $good,
            'payment_id' => $good ? 'pay_'.$intentId : null,
            'method' => $good ? 'CARD' : null,
        ];
    }

    public function refund(string $paymentId, int $amountPaise, string $reason, string $reference): array
    {
        if ($this->failRefunds) {
            throw new PaymentGatewayException('The payment provider rejected this request.', 'fake refund failure');
        }

        $this->refunds[] = ['payment_id' => $paymentId, 'paise' => $amountPaise, 'reference' => $reference];

        return [
            'id' => $this->key.'_refund_'.count($this->refunds),
            'status' => $this->refundStatus,
            'amount' => $amountPaise,
        ];
    }

    /** Authenticated by `X-Fake-Signature: ok`; the body is already normalised. */
    public function parseWebhook(string $payload, array $headers): array
    {
        if (($headers['x-fake-signature'] ?? null) !== 'ok') {
            throw new InvalidWebhookException('Bad signature.');
        }

        return array_map(fn (array $e) => $e + [
            'provider_order_id' => null,
            'provider_payment_id' => null,
            'provider_refund_id' => null,
            'amount_paise' => 0,
            'method' => null,
            'reason' => null,
        ], json_decode($payload, true) ?? []);
    }

    public function totalRefundedPaise(): int
    {
        return array_sum(array_column($this->refunds, 'paise'));
    }
}
