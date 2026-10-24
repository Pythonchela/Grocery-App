<?php

namespace Tests\Feature;

use App\Models\Order;
use App\Models\Payment;
use App\Models\PaymentIntent;
use App\Models\Product;
use App\Models\ProductVariant;
use App\Models\Refund;
use App\Models\User;
use App\Services\Mock\MockPaymentGateway;
use App\Services\Payments\InvalidWebhookException;
use App\Services\Payments\PaymentGatewayManager;
use App\Services\PaymentGatewayException;
use App\Services\RazorpayGateway;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Client\Request;
use Illuminate\Support\Facades\Http;
use Illuminate\Testing\TestResponse;
use Tests\TestCase;

/**
 * Nothing here reaches Razorpay: every call is answered by Http::fake(), and the
 * signatures are computed with the same HMAC recipe Razorpay documents, so a
 * regression in the trust checks fails here rather than in production.
 *
 * What is *not* specific to Razorpay — refund routing, wallet splits, webhooks
 * reconciling payments — is covered against a different gateway in
 * PaymentPlatformTest.
 */
class RazorpayGatewayTest extends TestCase
{
    use RefreshDatabase;

    private const KEY_ID = 'rzp_test_abc123';
    private const SECRET = 'test_secret_value';
    private const WEBHOOK_SECRET = 'whsec_test_value';
    private const ORDER_ID = 'order_TestOrder0001';
    private const PAYMENT_ID = 'pay_TestPayment001';

    private function gateway(?string $webhookSecret = self::WEBHOOK_SECRET): RazorpayGateway
    {
        return new RazorpayGateway(self::KEY_ID, self::SECRET, $webhookSecret);
    }

    private function sign(string $orderId = self::ORDER_ID, string $paymentId = self::PAYMENT_ID): string
    {
        return hash_hmac('sha256', $orderId.'|'.$paymentId, self::SECRET);
    }

    private function evidence(?string $signature = null): array
    {
        return ['payment_id' => self::PAYMENT_ID, 'signature' => $signature ?? $this->sign()];
    }

    private function payment(array $overrides = []): array
    {
        return array_merge([
            'id' => self::PAYMENT_ID,
            'order_id' => self::ORDER_ID,
            'status' => 'captured',
            'method' => 'upi',
            'amount' => 100000,
            'currency' => 'INR',
        ], $overrides);
    }

    /** Make the app use Razorpay, the way setting both keys in .env does. */
    private function configureRazorpay(?string $webhookSecret = self::WEBHOOK_SECRET): void
    {
        config([
            'services.razorpay.key_id' => self::KEY_ID,
            'services.razorpay.key_secret' => self::SECRET,
            'services.razorpay.webhook_secret' => $webhookSecret,
        ]);
        $this->app->forgetInstance(PaymentGatewayManager::class);
    }

    // ── Being offered at all ────────────────────────────────────────────

    public function test_only_the_sandbox_is_offered_when_no_keys_are_configured(): void
    {
        $manager = app(PaymentGatewayManager::class);

        $this->assertSame(['mock'], $manager->enabled());
        $this->assertInstanceOf(MockPaymentGateway::class, $manager->default());
    }

    public function test_razorpay_is_offered_once_both_keys_are_configured(): void
    {
        $this->configureRazorpay();
        $manager = app(PaymentGatewayManager::class);

        $this->assertSame(['razorpay'], $manager->enabled());
        $this->assertInstanceOf(RazorpayGateway::class, $manager->default());
    }

    public function test_one_key_alone_does_not_switch_on_the_real_gateway(): void
    {
        config(['services.razorpay.key_id' => self::KEY_ID, 'services.razorpay.key_secret' => '']);
        $this->app->forgetInstance(PaymentGatewayManager::class);

        $this->assertSame(['mock'], app(PaymentGatewayManager::class)->enabled());
    }

    public function test_the_sandbox_stays_addressable_so_its_old_payments_remain_refundable(): void
    {
        $this->configureRazorpay();

        $this->assertInstanceOf(MockPaymentGateway::class, app(PaymentGatewayManager::class)->driver('mock'));
    }

    // ── createIntent ────────────────────────────────────────────────────

    public function test_create_intent_opens_an_order_for_the_exact_amount_in_paise(): void
    {
        Http::fake(['api.razorpay.com/v1/orders' => Http::response([
            'id' => self::ORDER_ID, 'amount' => 149950, 'currency' => 'INR',
            'receipt' => 'cart-1', 'status' => 'created',
        ])]);

        $intent = $this->gateway()->createIntent(1499.50, 'cart-1', ['fingerprint' => 'abc']);

        $this->assertSame(self::ORDER_ID, $intent['id']);
        $this->assertSame(['key_id' => self::KEY_ID], $intent['client']);
        $this->assertFalse($intent['is_mock']);

        Http::assertSent(fn (Request $r) => $r->method() === 'POST'
            && $r->url() === 'https://api.razorpay.com/v1/orders'
            && $r['amount'] === 149950
            && $r['currency'] === 'INR'
            && $r['notes']['fingerprint'] === 'abc'
            && $r->hasHeader('Authorization', 'Basic '.base64_encode(self::KEY_ID.':'.self::SECRET)));
    }

    public function test_the_secret_half_of_the_key_never_reaches_the_client(): void
    {
        Http::fake(['api.razorpay.com/v1/orders' => Http::response([
            'id' => self::ORDER_ID, 'amount' => 10000, 'currency' => 'INR', 'status' => 'created',
        ])]);

        $intent = $this->gateway()->createIntent(100, 'cart-1');

        $this->assertStringNotContainsString(self::SECRET, json_encode($intent));
    }

    public function test_create_intent_truncates_a_receipt_longer_than_razorpays_limit(): void
    {
        Http::fake(['api.razorpay.com/v1/orders' => Http::response([
            'id' => self::ORDER_ID, 'amount' => 10000, 'currency' => 'INR', 'status' => 'created',
        ])]);

        // 'cart-' + a 36-char uuid is 41 characters — one over the limit.
        $this->gateway()->createIntent(100, 'cart-11111111-1111-1111-1111-111111111111');

        Http::assertSent(fn (Request $r) => strlen($r['receipt']) === 40);
    }

    public function test_create_intent_refuses_an_amount_below_one_rupee_without_calling_razorpay(): void
    {
        Http::fake();

        $this->expectException(PaymentGatewayException::class);

        try {
            $this->gateway()->createIntent(0.50, 'cart-1');
        } finally {
            Http::assertNothingSent();
        }
    }

    public function test_a_razorpay_outage_becomes_a_customer_safe_exception(): void
    {
        Http::fake(['api.razorpay.com/*' => Http::response(['error' => ['description' => 'Internal secret detail']], 500)]);

        try {
            $this->gateway()->createIntent(100, 'cart-1');
            $this->fail('Expected a PaymentGatewayException.');
        } catch (PaymentGatewayException $e) {
            $this->assertStringNotContainsString('secret detail', $e->getMessage());
            $this->assertSame('Internal secret detail', $e->detail);
        }
    }

    public function test_a_rejected_key_becomes_a_payment_gateway_exception(): void
    {
        Http::fake(['api.razorpay.com/*' => Http::response(['error' => ['description' => 'Authentication failed']], 401)]);

        $this->expectException(PaymentGatewayException::class);

        $this->gateway()->createIntent(100, 'cart-1');
    }

    // ── verify ──────────────────────────────────────────────────────────

    public function test_a_correctly_signed_captured_payment_is_verified(): void
    {
        Http::fake(['api.razorpay.com/v1/payments/*' => Http::response($this->payment())]);

        $result = $this->gateway()->verify(self::ORDER_ID, $this->evidence());

        $this->assertTrue($result['verified']);
        $this->assertSame(self::PAYMENT_ID, $result['payment_id']);
        $this->assertSame('UPI', $result['method']);
    }

    public function test_a_forged_signature_is_rejected_without_asking_razorpay(): void
    {
        Http::fake();

        $result = $this->gateway()->verify(self::ORDER_ID, $this->evidence(str_repeat('a', 64)));

        $this->assertFalse($result['verified']);
        Http::assertNothingSent();
    }

    public function test_a_signature_made_with_the_wrong_secret_is_rejected(): void
    {
        Http::fake();

        $forged = hash_hmac('sha256', self::ORDER_ID.'|'.self::PAYMENT_ID, 'not-the-secret');

        $this->assertFalse($this->gateway()->verify(self::ORDER_ID, $this->evidence($forged))['verified']);
    }

    public function test_missing_payment_evidence_is_rejected(): void
    {
        Http::fake();

        $this->assertFalse($this->gateway()->verify(self::ORDER_ID, [])['verified']);
        $this->assertFalse($this->gateway()->verify(self::ORDER_ID, ['payment_id' => self::PAYMENT_ID])['verified']);
        $this->assertFalse($this->gateway()->verify(self::ORDER_ID, ['signature' => 'sig'])['verified']);
        Http::assertNothingSent();
    }

    public function test_a_validly_signed_payment_for_another_order_does_not_settle_this_one(): void
    {
        // Genuine payment, genuine signature — but Razorpay says it belongs to a
        // different order. Reusing it must not buy a second cart.
        Http::fake(['api.razorpay.com/v1/payments/*' => Http::response($this->payment(['order_id' => 'order_Somebody_Else']))]);

        $this->assertFalse($this->gateway()->verify(self::ORDER_ID, $this->evidence())['verified']);
    }

    public function test_a_payment_that_is_not_captured_is_not_verified(): void
    {
        Http::fake(['api.razorpay.com/v1/payments/*' => Http::response($this->payment(['status' => 'failed']))]);

        $this->assertFalse($this->gateway()->verify(self::ORDER_ID, $this->evidence())['verified']);
    }

    public function test_an_authorized_payment_is_captured_before_it_counts(): void
    {
        Http::fake([
            'api.razorpay.com/v1/payments/'.self::PAYMENT_ID.'/capture' => Http::response($this->payment(['status' => 'captured'])),
            'api.razorpay.com/v1/payments/'.self::PAYMENT_ID => Http::response($this->payment(['status' => 'authorized'])),
        ]);

        $result = $this->gateway()->verify(self::ORDER_ID, $this->evidence());

        $this->assertTrue($result['verified']);
        Http::assertSent(fn (Request $r) => $r->method() === 'POST'
            && str_ends_with($r->url(), '/capture')
            && $r['amount'] === 100000);
    }

    public function test_being_unable_to_reach_razorpay_aborts_rather_than_deciding(): void
    {
        Http::fake(['api.razorpay.com/*' => Http::response([], 503)]);

        $this->expectException(PaymentGatewayException::class);

        $this->gateway()->verify(self::ORDER_ID, $this->evidence());
    }

    // ── refund ──────────────────────────────────────────────────────────

    public function test_a_refund_is_sent_against_the_payment_in_paise(): void
    {
        Http::fake(['api.razorpay.com/v1/payments/*/refund' => Http::response([
            'id' => 'rfnd_Test0001', 'payment_id' => self::PAYMENT_ID, 'amount' => 25050, 'status' => 'processed',
        ])]);

        $refund = $this->gateway()->refund(self::PAYMENT_ID, 25050, 'Return RMA-1', 'return:abc');

        $this->assertSame('rfnd_Test0001', $refund['id']);
        $this->assertSame('PROCESSED', $refund['status']);
        Http::assertSent(fn (Request $r) => $r->url() === 'https://api.razorpay.com/v1/payments/'.self::PAYMENT_ID.'/refund'
            && $r['amount'] === 25050
            && $r['receipt'] === 'return:abc'
            && $r['notes']['reason'] === 'Return RMA-1');
    }

    public function test_a_refund_razorpay_has_not_paid_out_yet_is_reported_as_pending(): void
    {
        Http::fake(['api.razorpay.com/v1/payments/*/refund' => Http::response([
            'id' => 'rfnd_Test0002', 'amount' => 1000, 'status' => 'pending',
        ])]);

        $this->assertSame('PENDING', $this->gateway()->refund(self::PAYMENT_ID, 1000, 'x', 'ref')['status']);
    }

    public function test_a_refund_razorpay_rejects_raises_instead_of_pretending_it_worked(): void
    {
        Http::fake(['api.razorpay.com/*' => Http::response(
            ['error' => ['description' => 'The refund amount provided is greater than amount captured']],
            400,
        )]);

        $this->expectException(PaymentGatewayException::class);

        $this->gateway()->refund(self::PAYMENT_ID, 9999900, 'Too much', 'ref');
    }

    // ── Webhooks ────────────────────────────────────────────────────────

    private function signedWebhook(array $body, ?string $secret = self::WEBHOOK_SECRET): array
    {
        $payload = json_encode($body);

        return [$payload, ['x-razorpay-signature' => hash_hmac('sha256', $payload, $secret)]];
    }

    public function test_a_captured_payment_webhook_is_normalised(): void
    {
        [$payload, $headers] = $this->signedWebhook([
            'event' => 'payment.captured',
            'payload' => ['payment' => ['entity' => [
                'id' => self::PAYMENT_ID, 'order_id' => self::ORDER_ID, 'amount' => 50000, 'method' => 'upi',
            ]]],
        ]);

        $events = $this->gateway()->parseWebhook($payload, $headers);

        $this->assertCount(1, $events);
        $this->assertSame('payment.captured', $events[0]['type']);
        $this->assertSame(self::ORDER_ID, $events[0]['provider_order_id']);
        $this->assertSame(self::PAYMENT_ID, $events[0]['provider_payment_id']);
        $this->assertSame(50000, $events[0]['amount_paise']);
        $this->assertSame('UPI', $events[0]['method']);
    }

    public function test_a_refund_webhook_is_normalised(): void
    {
        [$payload, $headers] = $this->signedWebhook([
            'event' => 'refund.processed',
            'payload' => ['refund' => ['entity' => ['id' => 'rfnd_1', 'payment_id' => self::PAYMENT_ID, 'amount' => 2500]]],
        ]);

        $events = $this->gateway()->parseWebhook($payload, $headers);

        $this->assertSame('refund.processed', $events[0]['type']);
        $this->assertSame('rfnd_1', $events[0]['provider_refund_id']);
        $this->assertSame(2500, $events[0]['amount_paise']);
    }

    public function test_events_the_platform_has_no_use_for_are_dropped(): void
    {
        [$payload, $headers] = $this->signedWebhook(['event' => 'order.paid', 'payload' => []]);

        $this->assertSame([], $this->gateway()->parseWebhook($payload, $headers));
    }

    public function test_a_webhook_signed_with_another_secret_is_rejected(): void
    {
        [$payload, $headers] = $this->signedWebhook(['event' => 'payment.captured'], 'not-our-secret');

        $this->expectException(InvalidWebhookException::class);

        $this->gateway()->parseWebhook($payload, $headers);
    }

    public function test_a_webhook_with_no_signature_is_rejected(): void
    {
        $this->expectException(InvalidWebhookException::class);

        $this->gateway()->parseWebhook('{"event":"payment.captured"}', []);
    }

    public function test_webhooks_are_refused_outright_until_a_webhook_secret_is_set(): void
    {
        // Without a secret nothing can be authenticated — accepting them
        // unsigned would let anyone mark payments as captured.
        [$payload, $headers] = $this->signedWebhook(['event' => 'payment.captured'], '');

        $this->expectException(InvalidWebhookException::class);

        $this->gateway(null)->parseWebhook($payload, $headers);
    }

    public function test_the_webhook_endpoint_accepts_a_signed_razorpay_delivery(): void
    {
        $this->configureRazorpay();
        [$user, $items] = $this->checkoutFixture();
        $this->fakeRazorpayOrder();
        $intent = $this->quote($user, $items);

        [$payload, $headers] = $this->signedWebhook([
            'event' => 'payment.captured',
            'payload' => ['payment' => ['entity' => [
                'id' => self::PAYMENT_ID, 'order_id' => self::ORDER_ID, 'amount' => $intent['amount_paise'], 'method' => 'upi',
            ]]],
        ]);

        $this->call('POST', '/api/v1/webhooks/payments/razorpay', [], [], [], [
            'CONTENT_TYPE' => 'application/json',
            'HTTP_X_RAZORPAY_SIGNATURE' => $headers['x-razorpay-signature'],
        ], $payload)->assertOk();

        $this->assertSame('PAID', PaymentIntent::firstOrFail()->status);
        $this->assertSame('razorpay', Payment::firstOrFail()->provider);
    }

    public function test_the_webhook_endpoint_rejects_a_forged_razorpay_delivery(): void
    {
        $this->configureRazorpay();

        $this->call('POST', '/api/v1/webhooks/payments/razorpay', [], [], [], [
            'CONTENT_TYPE' => 'application/json',
            'HTTP_X_RAZORPAY_SIGNATURE' => 'forged',
        ], '{"event":"payment.captured"}')->assertStatus(400);

        $this->assertSame(0, Payment::count());
    }

    // ── Through the real checkout endpoints ─────────────────────────────

    /**
     * Replace the faked responses outright. Http::fake() only appends, and the
     * first matching stub wins — so a second phase of a test would otherwise be
     * answered by the stubs from the first.
     */
    private function refake(array $stubs): void
    {
        Http::swap(new \Illuminate\Http\Client\Factory());
        Http::fake($stubs);
    }

    private function fakeRazorpayOrder(): void
    {
        Http::fake(['api.razorpay.com/v1/orders' => fn (Request $r) => Http::response([
            'id' => self::ORDER_ID, 'amount' => $r['amount'], 'currency' => 'INR',
            'receipt' => $r['receipt'], 'status' => 'created',
        ])]);
    }

    private function checkoutFixture(): array
    {
        $user = User::factory()->create(['role' => 'CUSTOMER', 'status' => 'ACTIVE']);
        $product = Product::factory()->pricedAt(1000)->create();
        ProductVariant::factory()->withStock(10)->create(['product_id' => $product->id]);
        $product = $product->fresh('variants');

        $items = [[
            'product_id' => $product->id,
            'variant_id' => $product->variants->first()->id,
            'quantity' => 1,
        ]];

        return [$user, $items];
    }

    private function quote(User $user, array $items): array
    {
        return $this->actingAs($user, 'sanctum')
            ->postJson('/api/v1/payments/intent', [
                'items' => $items,
                'pincode' => '560038',
                'payment_method' => 'UPI',
            ])
            ->assertCreated()
            ->json('data');
    }

    private function place(User $user, array $items, array $intent, array $extra = []): TestResponse
    {
        return $this->actingAs($user, 'sanctum')->postJson('/api/v1/orders/checkout', array_merge([
            'items' => $items,
            'shipping_address' => [
                'name' => 'Priya Sharma', 'phone' => '9876543210', 'line1' => '221B Indiranagar',
                'city' => 'Bengaluru', 'state' => 'Karnataka', 'pincode' => '560038',
            ],
            'payment_method' => 'UPI',
            'payment_intent_id' => $intent['payment_intent_id'],
        ], $extra));
    }

    /** A paid order, ready for the cancel and refund tests. */
    private function paidOrder(): array
    {
        $this->configureRazorpay();
        $this->fakeRazorpayOrder();
        [$user, $items] = $this->checkoutFixture();
        $intent = $this->quote($user, $items);

        $this->refake(['api.razorpay.com/v1/payments/*' => Http::response($this->payment())]);
        $this->place($user, $items, $intent, ['payment' => $this->evidence()])->assertCreated();

        return [$user, Order::firstOrFail(), $intent, $items];
    }

    public function test_the_quote_carries_what_the_client_needs_to_open_the_payment_window(): void
    {
        $this->configureRazorpay();
        $this->fakeRazorpayOrder();
        [$user, $items] = $this->checkoutFixture();

        $intent = $this->quote($user, $items);

        $this->assertSame('razorpay', $intent['provider']);
        $this->assertSame(self::ORDER_ID, $intent['provider_intent_id']);
        $this->assertSame(['key_id' => self::KEY_ID], $intent['client']);
        $this->assertSame($intent['amount_paise'], Http::recorded()->first()[0]['amount']);
    }

    public function test_a_genuinely_paid_order_is_placed_and_the_payment_is_recorded(): void
    {
        [, $order] = $this->paidOrder();

        $this->assertSame('PAID', $order->payment_status);
        $this->assertSame(self::PAYMENT_ID, $order->transaction_id);
        $this->assertSame('CONSUMED', PaymentIntent::firstOrFail()->status);

        $payment = Payment::firstOrFail();
        $this->assertSame('razorpay', $payment->provider);
        $this->assertSame(self::PAYMENT_ID, $payment->provider_payment_id);
        $this->assertSame($order->id, $payment->order_id);
    }

    public function test_the_older_flat_payment_fields_are_still_accepted(): void
    {
        $this->configureRazorpay();
        $this->fakeRazorpayOrder();
        [$user, $items] = $this->checkoutFixture();
        $intent = $this->quote($user, $items);

        $this->refake(['api.razorpay.com/v1/payments/*' => Http::response($this->payment())]);

        $this->place($user, $items, $intent, [
            'payment_id' => self::PAYMENT_ID,
            'signature' => $this->sign(),
        ])->assertCreated();
    }

    public function test_placing_an_order_without_payment_evidence_is_refused_and_leaves_nothing_behind(): void
    {
        $this->configureRazorpay();
        $this->fakeRazorpayOrder();
        [$user, $items] = $this->checkoutFixture();
        $intent = $this->quote($user, $items);

        $this->place($user, $items, $intent)->assertStatus(422);

        $this->assertSame(0, Order::count());
        $this->assertSame(10, ProductVariant::first()->stock);
    }

    public function test_a_forged_signature_cannot_place_an_order(): void
    {
        $this->configureRazorpay();
        $this->fakeRazorpayOrder();
        [$user, $items] = $this->checkoutFixture();
        $intent = $this->quote($user, $items);

        $this->place($user, $items, $intent, ['payment' => $this->evidence(str_repeat('0', 64))])->assertStatus(422);

        $this->assertSame(0, Order::count());
        $this->assertSame(0, Payment::count());
        $this->assertSame('CREATED', PaymentIntent::firstOrFail()->status);
    }

    public function test_a_provider_outage_at_checkout_places_no_order_and_reports_502(): void
    {
        $this->configureRazorpay();
        $this->fakeRazorpayOrder();
        [$user, $items] = $this->checkoutFixture();
        $intent = $this->quote($user, $items);

        $this->refake(['api.razorpay.com/*' => Http::response([], 503)]);

        $this->place($user, $items, $intent, ['payment' => $this->evidence()])
            ->assertStatus(502)
            ->assertJsonPath('status', 'error');

        $this->assertSame(0, Order::count());
        $this->assertSame(10, ProductVariant::first()->stock);
    }

    public function test_cancelling_a_paid_order_refunds_the_real_payment(): void
    {
        [$user, $order] = $this->paidOrder();
        $paise = (int) round($order->total_amount * 100);

        $this->refake(['api.razorpay.com/v1/payments/*/refund' => Http::response([
            'id' => 'rfnd_Test0001', 'payment_id' => self::PAYMENT_ID, 'amount' => $paise, 'status' => 'processed',
        ])]);

        $this->actingAs($user, 'sanctum')
            ->postJson("/api/v1/orders/{$order->id}/cancel", ['reason' => 'Changed my mind'])
            ->assertSuccessful();

        Http::assertSent(fn (Request $r) => str_ends_with($r->url(), self::PAYMENT_ID.'/refund') && $r['amount'] === $paise);
        $this->assertSame('REFUNDED', $order->fresh()->payment_status);

        $refund = Refund::firstOrFail();
        $this->assertSame('rfnd_Test0001', $refund->provider_refund_id);
        $this->assertSame('razorpay', $refund->provider);
        $this->assertSame('PROCESSED', $refund->status);
    }

    public function test_a_refund_razorpay_refuses_leaves_the_order_uncancelled(): void
    {
        [$user, $order] = $this->paidOrder();

        $this->refake(['api.razorpay.com/*' => Http::response(['error' => ['description' => 'Refund failed']], 400)]);

        $this->actingAs($user, 'sanctum')
            ->postJson("/api/v1/orders/{$order->id}/cancel", ['reason' => 'Changed my mind'])
            ->assertStatus(502);

        // Cancelling without the refund would leave the customer out of pocket.
        $this->assertSame('CONFIRMED', $order->fresh()->status);
        $this->assertSame('PAID', $order->fresh()->payment_status);
    }
}
