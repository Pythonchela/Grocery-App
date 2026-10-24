<?php

namespace App\Services\Contracts;

/**
 * What the platform needs from *any* payment gateway — nothing more.
 *
 * A gateway is a hook for taking money and giving it back. It does not know
 * about orders, carts, coupons, wallets or returns; the platform owns all of
 * that (see App\Services\Payments\PaymentService) and talks to a gateway only
 * in terms of provider ids and amounts in paise. That is what lets a second
 * gateway sit beside the first, and what lets an old payment be refunded through
 * the gateway that took it after the default has moved on.
 *
 * Adding a gateway: implement this, add the class to config/payments.php. No
 * controller, model or migration changes.
 */
interface PaymentGateway
{
    /** Stable identifier stored on every payment ("razorpay", "stripe", …). */
    public function key(): string;

    /**
     * Open a payment for an amount in rupees.
     *
     * @return array{
     *   id: string,
     *   amount: int,
     *   currency: string,
     *   client: array<string, mixed>,
     *   is_mock: bool
     * } `amount` is paise. `client` is the public, non-secret configuration the
     *   storefront's SDK needs to collect payment (a publishable key, say); the
     *   API hands it to the client untouched.
     */
    public function createIntent(float $amount, string $receipt, array $meta = []): array;

    /**
     * Decide whether the client's claim of payment is true.
     *
     * `$evidence` is whatever the gateway's client SDK returned — its shape is
     * the gateway's business. Return `verified => false` for a payment that
     * simply did not happen; throw PaymentGatewayException when the gateway
     * cannot be asked, because not knowing is not the same as "no".
     *
     * @param  array<string, mixed>  $evidence
     * @return array{verified: bool, payment_id: ?string, method: ?string}
     */
    public function verify(string $intentId, array $evidence): array;

    /**
     * Send money back against a captured payment.
     *
     * `$reference` is the platform's own key for this refund; gateways that
     * support idempotency or a receipt field should pass it through.
     *
     * @return array{id: ?string, status: string, amount: int} `status` is
     *   'PROCESSED' or 'PENDING' (accepted, not yet paid out). A refund that is
     *   refused throws PaymentGatewayException.
     */
    public function refund(string $paymentId, int $amountPaise, string $reason, string $reference): array;

    /**
     * Authenticate and normalise a webhook delivery.
     *
     * Throws InvalidWebhookException when the signature does not check out.
     * Events the platform has no use for are simply left out of the result.
     *
     * @param  array<string, string>  $headers  lower-cased header name => value
     * @return list<array{
     *   type: 'payment.captured'|'payment.failed'|'refund.processed'|'refund.failed',
     *   provider_order_id: ?string,
     *   provider_payment_id: ?string,
     *   provider_refund_id: ?string,
     *   amount_paise: int,
     *   method: ?string,
     *   reason: ?string
     * }>
     */
    public function parseWebhook(string $payload, array $headers): array;
}
