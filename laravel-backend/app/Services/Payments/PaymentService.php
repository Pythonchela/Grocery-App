<?php

namespace App\Services\Payments;

use App\Http\Controllers\Api\WalletController;
use App\Models\Order;
use App\Models\Payment;
use App\Models\PaymentIntent;
use App\Models\Refund;
use App\Models\ReturnRequest;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Validation\ValidationException;
use Throwable;

/**
 * The platform's side of every payment.
 *
 * Gateways are hooks: they take money and give it back, and know nothing else.
 * This class is where the rules live — which gateway a refund goes to, how much
 * of it, what goes to the wallet instead, and what happens when a gateway tells
 * us something out of band. Because the rules are here and not in a driver,
 * every gateway gets them for free and none can get them subtly wrong.
 *
 * Money is in integer paise from the moment it enters this class.
 */
class PaymentService
{
    public function __construct(private readonly PaymentGatewayManager $gateways) {}

    // ── Taking payment ──────────────────────────────────────────────────

    /**
     * Ask the gateway that opened this intent whether it was really paid.
     *
     * @param  array<string, mixed>  $evidence  whatever the client SDK returned
     * @return array{verified: bool, payment_id: ?string, method: ?string}
     */
    public function verify(PaymentIntent $intent, array $evidence): array
    {
        // A ₹0 order (wallet, points or a coupon covered everything) has no
        // gateway and nothing to prove — but only an intent quoted at exactly
        // zero may skip the gateway, so this is not a way around paying.
        if ($intent->provider === 'none') {
            return ['verified' => $intent->amount_paise === 0, 'payment_id' => null, 'method' => null];
        }

        return $this->gateways
            ->driver($intent->provider)
            ->verify($intent->provider_intent_id, $evidence);
    }

    /**
     * Record a captured payment against an order.
     *
     * Idempotent on the gateway's payment id: if a webhook got there first the
     * row already exists and this only attaches the order to it.
     */
    public function recordCapture(PaymentIntent $intent, array $verified, ?Order $order): ?Payment
    {
        if ($intent->provider === 'none') {
            return null; // nothing was captured, so there is nothing to record
        }

        $providerPaymentId = $verified['payment_id'] ?: $intent->provider_intent_id;

        $payment = Payment::where('provider', $intent->provider)
            ->where('provider_payment_id', $providerPaymentId)
            ->lockForUpdate()
            ->first();

        if ($payment) {
            $payment->update([
                'order_id' => $order?->id ?? $payment->order_id,
                'method' => $payment->method ?? $verified['method'] ?? null,
            ]);

            return $payment;
        }

        return Payment::create([
            'order_id' => $order?->id,
            'user_id' => $intent->user_id,
            'payment_intent_id' => $intent->id,
            'provider' => $intent->provider,
            'provider_order_id' => $intent->provider_intent_id,
            'provider_payment_id' => $providerPaymentId,
            'method' => $verified['method'] ?? null,
            'amount_paise' => $intent->amount_paise,
            'status' => 'CAPTURED',
            'captured_at' => now(),
        ]);
    }

    // ── Giving money back ───────────────────────────────────────────────

    /**
     * Refund an order, however it was paid.
     *
     * The customer gets back what they put in, in the proportions they put it
     * in: an order paid ₹600 by card and ₹400 from the wallet refunds 60/40,
     * with the card share capped at what is still refundable on the payment.
     * An order with no gateway payment (cash on delivery) can only be refunded
     * to the wallet, which is also the only place a COD customer's money can go.
     *
     * Call this *last* inside the caller's transaction. The gateway is the one
     * step that cannot be rolled back, so nothing that might fail should come
     * after it.
     *
     * Asking twice with the same `$reference` returns the first answer instead
     * of refunding twice.
     *
     * @param  string  $mode  Refund::SOURCE (default) or Refund::WALLET
     * @return array{source_paise: int, wallet_paise: int, skipped_paise: int, refunds: list<Refund>}
     */
    public function refundOrder(
        Order $order,
        float $amount,
        string $reason,
        string $reference,
        ?ReturnRequest $return = null,
        string $mode = Refund::SOURCE,
    ): array {
        $paise = (int) round($amount * 100);

        $prior = Refund::where('reference', $reference)->get();
        if ($prior->isNotEmpty() && $prior->every(fn (Refund $r) => $r->status !== 'FAILED')) {
            return $this->summarise($prior->all());
        }

        if ($paise <= 0) {
            return ['source_paise' => 0, 'wallet_paise' => 0, 'skipped_paise' => 0, 'refunds' => []];
        }

        $payment = Payment::where('order_id', $order->id)->lockForUpdate()->first();

        // Everything the customer handed over for this order, gateway and
        // wallet together. No sequence of refunds may exceed it.
        $tender = (int) round(((float) $order->total_amount + (float) $order->wallet_applied) * 100);
        $alreadyRefunded = (int) Refund::where('order_id', $order->id)
            ->where('status', '!=', 'FAILED')
            ->sum('amount_paise');
        $left = $tender - $alreadyRefunded;

        if ($paise > $left) {
            throw ValidationException::withMessages([
                'refund' => ['This refund is more than is left to refund on the order.'],
            ]);
        }

        // A prepaid order with no payment record predates the ledger (or was paid
        // under the sandbox). Nothing says money reached a gateway, so sending it
        // "back" to the wallet would invent store credit. It gets what it always
        // got: the gateway share is recorded as skipped and nothing moves, while
        // any wallet money the customer really did spend still goes back to them.
        $legacyPrepaid = ! $payment && ! in_array($order->payment_method, ['COD', 'EXCHANGE'], true);

        $source = 0;
        $skipped = 0;

        if ($mode === Refund::SOURCE && $payment) {
            // Refunding everything that is left clears the payment exactly;
            // otherwise split in proportion to how the order was paid.
            $source = $paise === $left
                ? $payment->refundablePaise()
                : (int) round($paise * $payment->amount_paise / max(1, $tender));
            $source = min($source, $payment->refundablePaise());
        } elseif ($mode === Refund::SOURCE && $legacyPrepaid) {
            $gatewayTender = (int) round((float) $order->total_amount * 100);
            $skippedBefore = (int) Refund::where('order_id', $order->id)
                ->where('destination', Refund::SOURCE)
                ->where('status', '!=', 'FAILED')
                ->sum('amount_paise');
            $remaining = max(0, $gatewayTender - $skippedBefore);

            $skipped = $paise === $left
                ? $remaining
                : min($remaining, (int) round($paise * $gatewayTender / max(1, $tender)));
        }

        $wallet = $paise - $source - $skipped;
        $refunds = [];

        if ($wallet > 0) {
            $order->loadMissing('user');
            WalletController::apply(
                $order->user,
                'CREDIT',
                $wallet / 100,
                $reason,
                $return ? 'RETURN' : 'ORDER',
                $return?->id ?? $order->id,
            );

            $refunds[] = $this->row($order, $return, $reference, Refund::WALLET, $wallet, $reason, [
                'status' => 'PROCESSED',
                'processed_at' => now(),
            ]);
        }

        if ($skipped > 0) {
            Log::warning('[Payments] refund skipped: order has no gateway payment on record', [
                'order' => $order->order_number, 'paise' => $skipped,
            ]);

            $refunds[] = $this->row($order, $return, $reference, Refund::SOURCE, $skipped, $reason, [
                'status' => 'SKIPPED',
                'failure_reason' => 'No gateway payment on record for this order.',
            ]);
        }

        if ($source > 0) {
            $refunds[] = $this->refundPayment($payment, $source, $reason, $reference, $order, $return);
        }

        return $this->summarise($refunds);
    }

    /**
     * Send money back through the gateway that took it.
     *
     * The gateway is looked up from the payment, never assumed: this is the one
     * place the "which gateway?" question is answered for a refund.
     */
    public function refundPayment(
        Payment $payment,
        int $paise,
        string $reason,
        string $reference,
        ?Order $order = null,
        ?ReturnRequest $return = null,
    ): Refund {
        $payment = Payment::whereKey($payment->id)->lockForUpdate()->firstOrFail();

        if ($paise <= 0 || $paise > $payment->refundablePaise()) {
            throw ValidationException::withMessages([
                'refund' => ['That is more than remains refundable on this payment.'],
            ]);
        }

        $refund = $this->row($order, $return, $reference, Refund::SOURCE, $paise, $reason, [
            'payment_id' => $payment->id,
            'provider' => $payment->provider,
            'order_id' => $order?->id ?? $payment->order_id,
        ]);

        try {
            $result = $this->gateways
                ->driver($payment->provider)
                ->refund($payment->provider_payment_id, $paise, $reason, $reference);
        } catch (Throwable $e) {
            // Keeps the record honest if the caller isn't in a transaction to
            // roll this back; inside one, the rollback wins anyway.
            $refund->update(['status' => 'FAILED', 'failure_reason' => substr($e->getMessage(), 0, 250)]);

            throw $e;
        }

        $refund->update([
            'provider_refund_id' => $result['id'],
            'status' => $result['status'],
            'processed_at' => $result['status'] === 'PROCESSED' ? now() : null,
        ]);

        $this->syncRefunded($payment, $paise);

        return $refund;
    }

    // ── What a gateway tells us on its own ──────────────────────────────

    /**
     * Apply one normalised webhook event. Safe to replay — gateways deliver
     * webhooks at least once — and safe on events that aren't ours, since one
     * gateway account can serve several apps.
     *
     * @param  array<string, mixed>  $event
     * @return string what happened, for logs and tests
     */
    public function handleEvent(string $provider, array $event): string
    {
        return match ($event['type']) {
            'payment.captured' => $this->onCaptured($provider, $event),
            'refund.processed' => $this->onRefundSettled($provider, $event, true),
            'refund.failed' => $this->onRefundSettled($provider, $event, false),
            default => 'ignored',
        };
    }

    /**
     * Refund payments that were captured but never turned into an order.
     * This is the safety net for a customer who paid and then lost connection
     * (or the app) before checkout could place the order.
     *
     * @return int refunds issued
     */
    public function refundUnclaimed(int $olderThanMinutes): int
    {
        $issued = 0;

        $intents = PaymentIntent::where('status', 'PAID')
            ->where('paid_at', '<=', now()->subMinutes($olderThanMinutes))
            ->get();

        foreach ($intents as $intent) {
            try {
                DB::transaction(function () use ($intent) {
                    $payment = Payment::where('provider', $intent->provider)
                        ->where('provider_payment_id', $intent->provider_payment_id)
                        ->whereNull('order_id')
                        ->lockForUpdate()
                        ->first();

                    if ($payment && $payment->refundablePaise() > 0) {
                        $this->refundPayment(
                            $payment,
                            $payment->refundablePaise(),
                            'Payment received but the order was not completed',
                            "unclaimed:{$intent->id}",
                        );
                    }

                    $intent->update(['status' => 'REFUNDED']);
                });

                $issued++;
            } catch (Throwable $e) {
                // One stuck payment must not stop the rest; it is picked up
                // again on the next run.
                Log::error('[Payments] could not refund an unclaimed payment', [
                    'intent' => $intent->id,
                    'error' => $e->getMessage(),
                ]);
            }
        }

        return $issued;
    }

    private function onCaptured(string $provider, array $event): string
    {
        $paymentId = $event['provider_payment_id'];

        if (! $paymentId || Payment::where('provider', $provider)->where('provider_payment_id', $paymentId)->exists()) {
            return 'known';
        }

        $intent = PaymentIntent::where('provider', $provider)
            ->where('provider_intent_id', $event['provider_order_id'])
            ->lockForUpdate()
            ->first();

        // Not an order of ours. Normal when a gateway account is shared.
        if (! $intent) {
            return 'ignored';
        }

        $amount = $event['amount_paise'] ?: $intent->amount_paise;
        if ($amount !== $intent->amount_paise) {
            Log::warning('[Payments] webhook amount differs from the quote', [
                'intent' => $intent->id, 'quoted' => $intent->amount_paise, 'captured' => $amount,
            ]);
        }

        Payment::create([
            'order_id' => $intent->order_id, // set if checkout finished first
            'user_id' => $intent->user_id,
            'payment_intent_id' => $intent->id,
            'provider' => $provider,
            'provider_order_id' => $intent->provider_intent_id,
            'provider_payment_id' => $paymentId,
            'method' => $event['method'],
            'amount_paise' => $amount,
            'status' => 'CAPTURED',
            'captured_at' => now(),
        ]);

        // Paid, but no order yet: remembered so the customer's own checkout call
        // can still claim it, and so refundUnclaimed() can return it if not.
        if ($intent->status !== 'CONSUMED') {
            $intent->update(['status' => 'PAID', 'provider_payment_id' => $paymentId, 'paid_at' => now()]);
        }

        return 'recorded';
    }

    private function onRefundSettled(string $provider, array $event, bool $succeeded): string
    {
        $refund = Refund::where('provider', $provider)
            ->where('provider_refund_id', $event['provider_refund_id'])
            ->lockForUpdate()
            ->first();

        if (! $refund) {
            return 'ignored';
        }

        if ($succeeded) {
            $refund->update(['status' => 'PROCESSED', 'processed_at' => $refund->processed_at ?? now()]);

            return 'processed';
        }

        if ($refund->status === 'FAILED') {
            return 'known';
        }

        // The gateway took the refund and then could not pay it out. The
        // customer is still owed the money, so it stops counting as refunded
        // and is left loudly visible for someone to make good.
        $refund->update(['status' => 'FAILED', 'failure_reason' => 'The gateway reported the refund failed.']);

        if ($refund->payment_id && $payment = Payment::find($refund->payment_id)) {
            $this->syncRefunded($payment, -$refund->amount_paise);
        }

        Log::critical('[Payments] a refund failed at the gateway and the customer is still owed the money', [
            'refund' => $refund->id, 'order' => $refund->order_id, 'amount_paise' => $refund->amount_paise,
        ]);

        return 'failed';
    }

    // ── Internals ───────────────────────────────────────────────────────

    /** Adjust a payment's refunded total by a signed amount and restate its status. */
    private function syncRefunded(Payment $payment, int $deltaPaise): void
    {
        $refunded = max(0, $payment->refunded_paise + $deltaPaise);

        $payment->update([
            'refunded_paise' => $refunded,
            'status' => match (true) {
                $refunded === 0 => 'CAPTURED',
                $refunded >= $payment->amount_paise => 'REFUNDED',
                default => 'PARTIALLY_REFUNDED',
            },
        ]);
    }

    /** Create — or revive a FAILED — refund row for a reference and destination. */
    private function row(
        ?Order $order,
        ?ReturnRequest $return,
        string $reference,
        string $destination,
        int $paise,
        string $reason,
        array $extra = [],
    ): Refund {
        $attributes = $extra + [
            'order_id' => $order?->id,
            'return_request_id' => $return?->id,
            'destination' => $destination,
            'amount_paise' => $paise,
            'status' => 'PENDING',
            'reason' => substr($reason, 0, 250),
            'failure_reason' => null,
        ];

        return Refund::updateOrCreate(
            ['reference' => $reference, 'destination' => $destination],
            $attributes,
        );
    }

    /** @param  list<Refund>  $refunds */
    private function summarise(array $refunds): array
    {
        $moved = fn (string $destination) => (int) collect($refunds)
            ->where('destination', $destination)
            ->where('status', '!=', 'SKIPPED')
            ->sum('amount_paise');

        return [
            'source_paise' => $moved(Refund::SOURCE),
            'wallet_paise' => $moved(Refund::WALLET),
            'skipped_paise' => (int) collect($refunds)->where('status', 'SKIPPED')->sum('amount_paise'),
            'refunds' => array_values($refunds),
        ];
    }
}
