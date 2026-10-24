<?php

namespace Tests\Feature;

use App\Http\Controllers\Api\WalletController;
use App\Models\Coupon;
use App\Models\CouponRedemption;
use App\Models\Order;
use App\Models\Payment;
use App\Models\PaymentIntent;
use App\Models\Product;
use App\Models\ProductVariant;
use App\Models\Refund;
use App\Models\ReturnRequest;
use App\Models\User;
use App\Services\Payments\PaymentGatewayManager;
use App\Services\Payments\PaymentService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Testing\TestResponse;
use Tests\Support\FakeGateway;
use Tests\TestCase;

/**
 * The platform must not depend on any one gateway, and every money flow must
 * hold up on its own terms: pay, cancel, return, refund, coupon, wallet.
 *
 * Everything here runs against FakeGateway — a gateway that looks nothing like
 * Razorpay — so a test can only pass if the API is genuinely gateway-neutral.
 */
class PaymentPlatformTest extends TestCase
{
    use RefreshDatabase;

    private const ADDRESS = [
        'name' => 'Priya Sharma', 'phone' => '9876543210', 'line1' => '221B Indiranagar',
        'city' => 'Bengaluru', 'state' => 'Karnataka', 'pincode' => '560038',
    ];

    private FakeGateway $gateway;

    protected function setUp(): void
    {
        parent::setUp();

        // No real gateway is configured in tests, so registering one makes it
        // the only enabled gateway — and the default.
        $this->gateway = new FakeGateway('fakepay');
        app(PaymentGatewayManager::class)->register($this->gateway);
    }

    // ── Helpers ─────────────────────────────────────────────────────────

    private function customer(): User
    {
        return User::factory()->create(['role' => 'CUSTOMER', 'status' => 'ACTIVE']);
    }

    private function admin(): User
    {
        return User::factory()->create(['role' => 'ADMIN', 'status' => 'ACTIVE']);
    }

    private function product(float $price = 1000, int $stock = 20): Product
    {
        $product = Product::factory()->pricedAt($price)->create();
        ProductVariant::factory()->withStock($stock)->create(['product_id' => $product->id]);

        return $product->fresh('variants');
    }

    private function items(Product $product, int $qty = 1): array
    {
        return [[
            'product_id' => $product->id,
            'variant_id' => $product->variants->first()->id,
            'quantity' => $qty,
        ]];
    }

    private function quote(User $user, array $items, array $extra = []): TestResponse
    {
        return $this->actingAs($user, 'sanctum')->postJson('/api/v1/payments/intent', array_merge([
            'items' => $items,
            'pincode' => self::ADDRESS['pincode'],
            'payment_method' => 'CARD',
        ], $extra));
    }

    private function place(User $user, array $items, array $intent, array $extra = []): TestResponse
    {
        return $this->actingAs($user, 'sanctum')->postJson('/api/v1/orders/checkout', array_merge([
            'items' => $items,
            'shipping_address' => self::ADDRESS,
            'payment_method' => 'CARD',
            'payment_intent_id' => $intent['payment_intent_id'],
        ], $extra));
    }

    /** Quote and pay through the fake gateway, the way a real client would. */
    private function pay(User $user, array $items, array $extra = [], ?string $gateway = null): Order
    {
        $quoteExtra = array_intersect_key($extra, array_flip(['coupon_code', 'use_wallet', 'redeem_points']));
        if ($gateway) {
            $quoteExtra['gateway'] = $gateway;
        }

        $intent = $this->quote($user, $items, $quoteExtra)->assertCreated()->json('data');

        $this->place($user, $items, $intent, $extra + [
            'payment' => ['token' => 'good-'.$intent['provider_intent_id']],
        ])->assertCreated();

        return Order::with('items')->latest('created_at')->latest('id')->firstOrFail();
    }

    private function cod(User $user, array $items, ?string $coupon = null): Order
    {
        $this->actingAs($user, 'sanctum')->postJson('/api/v1/orders/checkout', [
            'items' => $items,
            'shipping_address' => self::ADDRESS,
            'payment_method' => 'COD',
            'coupon_code' => $coupon,
        ])->assertCreated();

        return Order::with('items')->latest('created_at')->latest('id')->firstOrFail();
    }

    private function deliver(Order $order): Order
    {
        $order->update(['status' => 'DELIVERED', 'delivered_at' => now()->subDay()]);

        return $order->fresh('items');
    }

    private function cancel(User $user, Order $order): TestResponse
    {
        return $this->actingAs($user, 'sanctum')->postJson("/api/v1/orders/{$order->id}/cancel", ['reason' => 'Changed my mind']);
    }

    /** Raise, approve, collect and refund a return, returning the refund response. */
    private function returnAndRefund(User $user, Order $order, array $return = [], array $refund = []): TestResponse
    {
        $this->actingAs($user, 'sanctum')->postJson('/api/v1/returns', array_merge([
            'order_item_id' => $order->items->first()->id,
            'kind' => 'RETURN',
            'reason' => 'Did not fit',
        ], $return))->assertCreated();

        $rma = ReturnRequest::latest('created_at')->latest('id')->firstOrFail();
        $admin = $this->admin();

        $this->actingAs($admin, 'sanctum')->postJson("/api/v1/admin/returns/{$rma->id}/approve")->assertOk();
        $this->actingAs($admin, 'sanctum')->postJson("/api/v1/admin/returns/{$rma->id}/picked-up")->assertOk();

        return $this->actingAs($admin, 'sanctum')->postJson("/api/v1/admin/returns/{$rma->id}/refund", $refund);
    }

    private function fund(User $user, float $rupees): void
    {
        WalletController::apply($user, 'CREDIT', $rupees, 'test top-up');
    }

    private function webhook(string $provider, array $events, string $signature = 'ok'): TestResponse
    {
        return $this->postJson("/api/v1/webhooks/payments/{$provider}", $events, ['X-Fake-Signature' => $signature]);
    }

    // ── A gateway that isn't Razorpay works end to end ──────────────────

    public function test_another_gateway_takes_a_payment_with_no_gateway_specific_api(): void
    {
        $user = $this->customer();
        $items = $this->items($this->product(1000));

        $intent = $this->quote($user, $items)->assertCreated()->json('data');

        $this->assertSame('fakepay', $intent['provider']);
        $this->assertSame(['publishable_token' => 'pk_fakepay'], $intent['client']);

        $this->place($user, $items, $intent, [
            'payment' => ['token' => 'good-'.$intent['provider_intent_id']],
        ])->assertCreated();

        $order = Order::firstOrFail();
        $this->assertSame('PAID', $order->payment_status);
        $this->assertSame('pay_'.$intent['provider_intent_id'], $order->transaction_id);

        $payment = Payment::firstOrFail();
        $this->assertSame('fakepay', $payment->provider);
        $this->assertSame($order->id, $payment->order_id);
        $this->assertSame((int) round($order->total_amount * 100), $payment->amount_paise);
        $this->assertSame('CARD', $payment->method);
    }

    public function test_evidence_the_gateway_rejects_places_no_order(): void
    {
        $user = $this->customer();
        $items = $this->items($this->product());
        $intent = $this->quote($user, $items)->assertCreated()->json('data');

        $this->place($user, $items, $intent, ['payment' => ['token' => 'forged']])->assertStatus(422);

        $this->assertSame(0, Order::count());
        $this->assertSame(0, Payment::count());
        $this->assertSame('CREATED', PaymentIntent::firstOrFail()->status);
    }

    public function test_a_shopper_can_choose_between_enabled_gateways(): void
    {
        $other = new FakeGateway('otherpay');
        app(PaymentGatewayManager::class)->register($other);

        $user = $this->customer();
        $items = $this->items($this->product());

        $this->assertSame('otherpay', $this->quote($user, $items, ['gateway' => 'otherpay'])->assertCreated()->json('data.provider'));
        $this->assertSame('fakepay', $this->quote($user, $items, ['gateway' => 'fakepay'])->assertCreated()->json('data.provider'));
    }

    public function test_a_gateway_that_is_not_enabled_cannot_be_chosen(): void
    {
        $user = $this->customer();
        $items = $this->items($this->product());

        $this->quote($user, $items, ['gateway' => 'nonexistent'])->assertStatus(502);
        // The sandbox is not offered once a real gateway exists.
        $this->quote($user, $items, ['gateway' => 'mock'])->assertStatus(502);

        $this->assertSame(0, PaymentIntent::count());
    }

    // ── Refunds go back the way the money came ──────────────────────────

    public function test_a_refund_goes_to_the_gateway_that_took_the_payment_not_the_current_default(): void
    {
        $other = new FakeGateway('otherpay');
        app(PaymentGatewayManager::class)->register($other);

        $user = $this->customer();
        $order = $this->pay($user, $this->items($this->product()), gateway: 'fakepay');

        // "otherpay" is now what new payments could use; the old payment must
        // still be refunded through "fakepay".
        $this->cancel($user, $order)->assertOk();

        $this->assertCount(1, $this->gateway->refunds);
        $this->assertCount(0, $other->refunds);
        $this->assertSame('pay_'.PaymentIntent::firstOrFail()->provider_intent_id, $this->gateway->refunds[0]['payment_id']);
    }

    public function test_cancelling_a_paid_order_refunds_exactly_what_was_charged_and_records_it(): void
    {
        $user = $this->customer();
        $order = $this->pay($user, $this->items($this->product(1000)));

        $this->cancel($user, $order)->assertOk();

        $paise = (int) round($order->total_amount * 100);
        $this->assertSame($paise, $this->gateway->totalRefundedPaise());

        $refund = Refund::firstOrFail();
        $this->assertSame('SOURCE', $refund->destination);
        $this->assertSame('PROCESSED', $refund->status);
        $this->assertSame($paise, $refund->amount_paise);
        $this->assertSame('REFUNDED', Payment::firstOrFail()->status);
        $this->assertSame('REFUNDED', $order->fresh()->payment_status);
    }

    public function test_cancelling_a_part_wallet_order_splits_the_refund_between_gateway_and_wallet(): void
    {
        $user = $this->customer();
        $this->fund($user, 400);
        $order = $this->pay($user, $this->items($this->product(1000)), ['use_wallet' => true]);

        $this->assertEquals(400.0, (float) $order->wallet_applied);
        $this->assertEquals(0.0, (float) $user->fresh()->wallet_balance);

        $this->cancel($user, $order)->assertOk();

        // The card gets back what the card was charged; the wallet gets its 400.
        $this->assertSame((int) round($order->total_amount * 100), $this->gateway->totalRefundedPaise());
        $this->assertEquals(400.0, (float) $user->fresh()->wallet_balance);
        $this->assertSame(1, Refund::where('destination', 'SOURCE')->count());
        $this->assertSame(1, Refund::where('destination', 'WALLET')->count());
    }

    public function test_a_partial_return_on_a_part_wallet_order_refunds_in_proportion_to_how_it_was_paid(): void
    {
        $user = $this->customer();
        $this->fund($user, 600);
        $order = $this->deliver($this->pay($user, $this->items($this->product(1000), 2), ['use_wallet' => true]));

        $this->returnAndRefund($user, $order, ['quantity' => 1])->assertOk();

        $refunded = 100000; // one unit at ₹1000, no discount
        $tender = (int) round(((float) $order->total_amount + (float) $order->wallet_applied) * 100);
        $expectedSource = (int) round($refunded * ((float) $order->total_amount * 100) / $tender);

        $this->assertSame($expectedSource, $this->gateway->totalRefundedPaise());
        $this->assertSame($refunded, (int) Refund::sum('amount_paise'));
        $this->assertEquals(($refunded - $expectedSource) / 100, (float) $user->fresh()->wallet_balance);
    }

    public function test_a_return_refund_never_asks_the_gateway_for_more_than_it_captured(): void
    {
        $user = $this->customer();
        $this->fund($user, 1900);
        // ₹2000 basket mostly paid from the wallet: the card was charged little.
        $order = $this->deliver($this->pay($user, $this->items($this->product(1000), 2), ['use_wallet' => true]));
        $captured = Payment::firstOrFail()->amount_paise;

        $this->returnAndRefund($user, $order, ['quantity' => 2])->assertOk();

        $this->assertLessThanOrEqual($captured, $this->gateway->totalRefundedPaise());
        $this->assertSame(200000, (int) Refund::sum('amount_paise'));
    }

    public function test_refunding_beyond_what_the_order_was_paid_is_refused(): void
    {
        $user = $this->customer();
        $order = $this->pay($user, $this->items($this->product(1000)));
        $service = app(PaymentService::class);
        $tender = (float) $order->total_amount;

        $service->refundOrder($order, $tender, 'full', 'ref-a');

        $this->expectException(\Illuminate\Validation\ValidationException::class);
        $service->refundOrder($order->fresh(), 1, 'one rupee too many', 'ref-b');
    }

    public function test_asking_for_the_same_refund_twice_refunds_once(): void
    {
        $user = $this->customer();
        $order = $this->pay($user, $this->items($this->product(1000)));
        $service = app(PaymentService::class);

        $first = $service->refundOrder($order, 100, 'partial', 'ref-once');
        $second = $service->refundOrder($order->fresh(), 100, 'partial', 'ref-once');

        $this->assertCount(1, $this->gateway->refunds);
        $this->assertSame($first['source_paise'], $second['source_paise']);
        $this->assertSame(10000, Payment::firstOrFail()->refunded_paise);
    }

    public function test_a_refund_the_gateway_refuses_rolls_the_whole_return_back(): void
    {
        $user = $this->customer();
        $product = $this->product(1000);
        $order = $this->deliver($this->pay($user, $this->items($product)));
        $stockBefore = $product->variants->first()->fresh()->stock;

        $this->gateway->failRefunds = true;
        $this->returnAndRefund($user, $order)->assertStatus(502);

        $return = ReturnRequest::firstOrFail();
        $this->assertNotSame('COMPLETED', $return->refund_status);
        $this->assertSame($stockBefore, $product->variants->first()->fresh()->stock, 'stock must not be restocked for an unpaid refund');
        $this->assertSame(0, Refund::where('status', '!=', 'FAILED')->count());
        $this->assertEquals(0.0, (float) $user->fresh()->wallet_balance);
    }

    public function test_a_failed_cancellation_refund_leaves_the_order_uncancelled(): void
    {
        $user = $this->customer();
        $order = $this->pay($user, $this->items($this->product()));

        $this->gateway->failRefunds = true;
        $this->cancel($user, $order)->assertStatus(502);

        $this->assertSame('CONFIRMED', $order->fresh()->status);
        $this->assertSame('PAID', $order->fresh()->payment_status);
    }

    public function test_the_order_shows_the_customer_where_their_refund_went_without_gateway_ids(): void
    {
        $this->gateway->refundStatus = 'PENDING';
        $user = $this->customer();
        $this->fund($user, 400);
        $order = $this->pay($user, $this->items($this->product(1000)), ['use_wallet' => true]);
        $this->cancel($user, $order)->assertOk();

        $data = $this->actingAs($user, 'sanctum')->getJson("/api/v1/orders/{$order->id}")->assertOk()->json('data');

        $byDestination = collect($data['refunds'])->keyBy('destination');
        $this->assertSame('PENDING', $byDestination['SOURCE']['status']);
        $this->assertSame('PROCESSED', $byDestination['WALLET']['status']);
        $this->assertSame(40000, $byDestination['WALLET']['amount_paise']);
        $this->assertArrayNotHasKey('provider_refund_id', $byDestination['SOURCE']);
        $this->assertArrayNotHasKey('payment_id', $byDestination['SOURCE']);
    }

    // ── Cash on delivery ────────────────────────────────────────────────

    public function test_delivering_a_cod_order_marks_it_paid(): void
    {
        $user = $this->customer();
        $order = $this->cod($user, $this->items($this->product()));
        $this->assertSame('PENDING', $order->payment_status);

        $this->actingAs($this->admin(), 'sanctum')
            ->putJson("/api/v1/admin/orders/{$order->id}", ['status' => 'DELIVERED'])
            ->assertOk();

        $this->assertSame('PAID', $order->fresh()->payment_status);
    }

    public function test_a_cod_return_refunds_to_the_wallet_even_when_source_is_requested(): void
    {
        $user = $this->customer();
        $order = $this->deliver($this->cod($user, $this->items($this->product(1000))));

        // There is no gateway payment on a COD order to reverse.
        $this->returnAndRefund($user, $order, ['refund_mode' => 'SOURCE'])->assertOk();

        $this->assertCount(0, $this->gateway->refunds);
        $this->assertEquals(1000.0, (float) $user->fresh()->wallet_balance);
        $this->assertSame('WALLET', Refund::firstOrFail()->destination);
    }

    public function test_cancelling_an_unpaid_cod_order_refunds_nothing_at_a_gateway(): void
    {
        $user = $this->customer();
        $order = $this->cod($user, $this->items($this->product()));

        $this->cancel($user, $order)->assertOk();

        $this->assertCount(0, $this->gateway->refunds);
        $this->assertSame(0, Refund::count());
    }

    // ── Coupons, points and zero-value orders ───────────────────────────

    public function test_a_coupon_order_refunds_the_discounted_amount_through_the_gateway(): void
    {
        $user = $this->customer();
        Coupon::factory()->percent(10)->create(['code' => 'TEN']);

        $order = $this->deliver($this->pay($user, $this->items($this->product(1000)), ['coupon_code' => 'TEN']));
        $this->assertEquals(100.0, (float) $order->discount);

        $this->returnAndRefund($user, $order)->assertOk();

        // 1000 − 10% = 900 refunded; the shipping fee is not part of the item.
        $this->assertSame(90000, (int) Refund::sum('amount_paise'));
        $this->assertSame(90000, $this->gateway->totalRefundedPaise());
    }

    public function test_cancelling_a_coupon_order_releases_the_coupon_and_refunds_the_paid_total(): void
    {
        $user = $this->customer();
        $coupon = Coupon::factory()->percent(10)->create(['code' => 'TEN']);

        $order = $this->pay($user, $this->items($this->product(1000)), ['coupon_code' => 'TEN']);
        $this->assertSame(1, $coupon->fresh()->used_count);

        $this->cancel($user, $order)->assertOk();

        $this->assertSame(0, $coupon->fresh()->used_count);
        $this->assertSame(0, CouponRedemption::where('order_id', $order->id)->count());
        $this->assertSame((int) round($order->total_amount * 100), $this->gateway->totalRefundedPaise());
    }

    public function test_an_order_the_wallet_fully_covers_needs_no_gateway_and_refunds_to_the_wallet(): void
    {
        $user = $this->customer();
        $this->fund($user, 5000);
        $items = $this->items($this->product(1000));

        $intent = $this->quote($user, $items, ['use_wallet' => true])->assertCreated()->json('data');
        $this->assertSame('none', $intent['provider']);
        $this->assertSame(0, $intent['amount_paise']);

        $this->place($user, $items, $intent, ['use_wallet' => true])->assertCreated();
        $order = Order::firstOrFail();

        $this->assertSame('PAID', $order->payment_status);
        $this->assertSame(0, Payment::count());
        $spent = 5000 - (float) $user->fresh()->wallet_balance;

        $this->cancel($user, $order)->assertOk();

        $this->assertCount(0, $this->gateway->refunds);
        $this->assertEquals(5000.0, (float) $user->fresh()->wallet_balance, "wallet must be whole again after spending {$spent}");
    }

    public function test_returning_an_item_takes_back_the_points_it_earned(): void
    {
        $user = $this->customer();
        $order = $this->deliver($this->pay($user, $this->items($this->product(1000))));
        $earned = (int) $order->points_earned;

        $this->assertGreaterThan(0, $earned);
        $this->assertSame($earned, (int) $user->fresh()->loyalty_points);

        $this->returnAndRefund($user, $order)->assertOk();

        $this->assertLessThan($earned, (int) $user->fresh()->loyalty_points);
    }

    // ── Webhooks ────────────────────────────────────────────────────────

    public function test_a_webhook_with_a_bad_signature_is_rejected(): void
    {
        $this->webhook('fakepay', [['type' => 'payment.captured']], 'forged')->assertStatus(400);
    }

    public function test_a_webhook_for_an_unknown_gateway_is_a_404(): void
    {
        $this->webhook('nosuchpay', [])->assertNotFound();
    }

    public function test_a_captured_payment_for_an_order_that_is_not_ours_is_ignored(): void
    {
        // One gateway account can serve several apps; their payments reach us too.
        $this->webhook('fakepay', [[
            'type' => 'payment.captured',
            'provider_order_id' => 'someone_elses_order',
            'provider_payment_id' => 'pay_theirs',
            'amount_paise' => 5000,
        ]])->assertOk();

        $this->assertSame(0, Payment::count());
    }

    public function test_a_pending_refund_is_settled_by_the_gateway_webhook(): void
    {
        $this->gateway->refundStatus = 'PENDING';
        $user = $this->customer();
        $order = $this->pay($user, $this->items($this->product()));
        $this->cancel($user, $order)->assertOk();

        $refund = Refund::firstOrFail();
        $this->assertSame('PENDING', $refund->status);

        $this->webhook('fakepay', [[
            'type' => 'refund.processed',
            'provider_refund_id' => $refund->provider_refund_id,
        ]])->assertOk();

        $this->assertSame('PROCESSED', $refund->fresh()->status);
        $this->assertNotNull($refund->fresh()->processed_at);
    }

    public function test_a_refund_that_fails_after_being_accepted_stops_counting_as_refunded(): void
    {
        $this->gateway->refundStatus = 'PENDING';
        $user = $this->customer();
        $order = $this->pay($user, $this->items($this->product()));
        $this->cancel($user, $order)->assertOk();

        $refund = Refund::firstOrFail();
        $this->assertSame('REFUNDED', Payment::firstOrFail()->status);

        $this->webhook('fakepay', [[
            'type' => 'refund.failed',
            'provider_refund_id' => $refund->provider_refund_id,
        ]])->assertOk();

        $this->assertSame('FAILED', $refund->fresh()->status);
        // The customer is still owed the money, so the payment is refundable again.
        $this->assertSame(0, Payment::firstOrFail()->refunded_paise);
        $this->assertSame('CAPTURED', Payment::firstOrFail()->status);
    }

    public function test_replaying_a_webhook_changes_nothing(): void
    {
        $this->gateway->refundStatus = 'PENDING';
        $user = $this->customer();
        $order = $this->pay($user, $this->items($this->product()));
        $this->cancel($user, $order)->assertOk();
        $refund = Refund::firstOrFail();

        $event = [['type' => 'refund.processed', 'provider_refund_id' => $refund->provider_refund_id]];
        $this->webhook('fakepay', $event)->assertOk();
        $this->webhook('fakepay', $event)->assertOk();

        $this->assertSame('PROCESSED', $refund->fresh()->status);
        $this->assertCount(1, $this->gateway->refunds);
    }

    public function test_a_payment_the_webhook_saw_first_can_still_be_claimed_by_checkout(): void
    {
        $user = $this->customer();
        $items = $this->items($this->product());
        $intent = $this->quote($user, $items)->assertCreated()->json('data');
        $paymentId = 'pay_'.$intent['provider_intent_id'];

        // The gateway reports the payment before the app's own checkout call.
        $this->webhook('fakepay', [[
            'type' => 'payment.captured',
            'provider_order_id' => $intent['provider_intent_id'],
            'provider_payment_id' => $paymentId,
            'amount_paise' => $intent['amount_paise'],
        ]])->assertOk();

        $this->assertSame('PAID', PaymentIntent::firstOrFail()->status);
        $this->assertNull(Payment::firstOrFail()->order_id);

        $this->place($user, $items, $intent, ['payment' => ['token' => 'good-'.$intent['provider_intent_id']]])->assertCreated();

        $this->assertSame(1, Payment::count(), 'the payment must not be recorded twice');
        $this->assertSame(Order::firstOrFail()->id, Payment::firstOrFail()->order_id);
        $this->assertSame('CONSUMED', PaymentIntent::firstOrFail()->status);
    }

    public function test_money_nobody_claimed_is_refunded_after_the_grace_period(): void
    {
        $user = $this->customer();
        $intent = $this->quote($user, $this->items($this->product()))->assertCreated()->json('data');

        // Customer paid, then the app died: only the webhook knows.
        $this->webhook('fakepay', [[
            'type' => 'payment.captured',
            'provider_order_id' => $intent['provider_intent_id'],
            'provider_payment_id' => 'pay_orphan',
            'amount_paise' => $intent['amount_paise'],
        ]])->assertOk();

        // Inside the grace period nothing happens: checkout may still be running.
        $this->artisan('payments:refund-unclaimed')->assertSuccessful();
        $this->assertCount(0, $this->gateway->refunds);

        $this->travel(31)->minutes();
        $this->artisan('payments:refund-unclaimed')->assertSuccessful();

        $this->assertCount(1, $this->gateway->refunds);
        $this->assertSame($intent['amount_paise'], $this->gateway->refunds[0]['paise']);
        $this->assertSame('REFUNDED', PaymentIntent::firstOrFail()->status);
        $this->assertSame('REFUNDED', Payment::firstOrFail()->status);

        // And a second sweep does not refund it again.
        $this->artisan('payments:refund-unclaimed')->assertSuccessful();
        $this->assertCount(1, $this->gateway->refunds);
    }

    public function test_a_payment_that_became_an_order_is_never_swept_up_as_unclaimed(): void
    {
        $user = $this->customer();
        $this->pay($user, $this->items($this->product()));

        $this->travel(2)->hours();
        $this->artisan('payments:refund-unclaimed')->assertSuccessful();

        $this->assertCount(0, $this->gateway->refunds);
    }
}
