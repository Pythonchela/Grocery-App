<?php

namespace Tests\Feature;

use App\Http\Controllers\Api\WalletController;
use App\Models\Order;
use App\Models\PaymentIntent;
use App\Models\Product;
use App\Models\ProductVariant;
use App\Models\Refund;
use App\Models\ReturnRequest;
use App\Models\User;
use App\Services\Payments\PaymentGatewayManager;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Testing\TestResponse;
use PHPUnit\Framework\Attributes\DataProvider;
use Tests\Support\FakeGateway;
use Tests\TestCase;

/**
 * The safeguards that keep an upgrade from losing money:
 *
 *  - a production server with no gateway keys must not fall back to the sandbox
 *    gateway, which approves every payment without taking any;
 *  - an order from before the payments ledger has no record of money reaching a
 *    gateway, so cancelling or returning it must not mint wallet credit for
 *    money that may never have been collected.
 */
class PaymentSafetyTest extends TestCase
{
    use RefreshDatabase;

    private const ADDRESS = [
        'name' => 'Priya Sharma', 'phone' => '9876543210', 'line1' => '221B Indiranagar',
        'city' => 'Bengaluru', 'state' => 'Karnataka', 'pincode' => '560038',
    ];

    private function customer(): User
    {
        return User::factory()->create(['role' => 'CUSTOMER', 'status' => 'ACTIVE']);
    }

    private function admin(): User
    {
        return User::factory()->create(['role' => 'ADMIN', 'status' => 'ACTIVE']);
    }

    private function items(float $price = 1000, int $qty = 1): array
    {
        $product = Product::factory()->pricedAt($price)->create();
        ProductVariant::factory()->withStock(20)->create(['product_id' => $product->id]);
        $product = $product->fresh('variants');

        return [[
            'product_id' => $product->id,
            'variant_id' => $product->variants->first()->id,
            'quantity' => $qty,
        ]];
    }

    /** Pretend this is a production server: environment set, manager rebuilt. */
    private function asProduction(): void
    {
        $this->app['env'] = 'production';
        config(['payments.allow_sandbox' => null, 'services.razorpay.key_id' => null, 'services.razorpay.key_secret' => null]);
        $this->app->forgetInstance(PaymentGatewayManager::class);
    }

    private function quote(User $user, array $items): TestResponse
    {
        return $this->actingAs($user, 'sanctum')->postJson('/api/v1/payments/intent', [
            'items' => $items, 'pincode' => '560038', 'payment_method' => 'UPI',
        ]);
    }

    // ── The sandbox gateway in production ───────────────────────────────

    public function test_production_without_gateway_keys_refuses_online_payment(): void
    {
        $this->asProduction();

        $response = $this->quote($this->customer(), $this->items())->assertStatus(502);

        $this->assertStringContainsString('Online payment is not available', $response->json('message'));
        $this->assertSame(0, PaymentIntent::count(), 'no payment was opened');
    }

    public function test_production_without_keys_cannot_be_paid_around_with_a_made_up_intent(): void
    {
        $this->asProduction();
        $user = $this->customer();
        $items = $this->items();

        // Prepaid checkout needs an intent, and none can be created: nothing to fake.
        $this->actingAs($user, 'sanctum')->postJson('/api/v1/orders/checkout', [
            'items' => $items, 'shipping_address' => self::ADDRESS, 'payment_method' => 'UPI',
            'payment_intent_id' => '11111111-1111-1111-1111-111111111111',
        ])->assertStatus(422);

        $this->assertSame(0, Order::count());
    }

    public function test_cash_on_delivery_keeps_working_when_online_payment_is_unavailable(): void
    {
        $this->asProduction();

        $this->actingAs($this->customer(), 'sanctum')->postJson('/api/v1/orders/checkout', [
            'items' => $this->items(), 'shipping_address' => self::ADDRESS, 'payment_method' => 'COD',
        ])->assertCreated();
    }

    public function test_a_zero_total_order_needs_no_gateway_even_in_production_without_keys(): void
    {
        $this->asProduction();
        $user = $this->customer();
        WalletController::apply($user, 'CREDIT', 5000, 'top-up');

        $this->actingAs($user, 'sanctum')->postJson('/api/v1/payments/intent', [
            'items' => $this->items(), 'pincode' => '560038', 'payment_method' => 'UPI', 'use_wallet' => true,
        ])->assertCreated()->assertJsonPath('data.provider', 'none');
    }

    public function test_the_sandbox_can_be_switched_on_deliberately_in_production(): void
    {
        $this->asProduction();
        config(['payments.allow_sandbox' => true]);
        $this->app->forgetInstance(PaymentGatewayManager::class);

        $this->quote($this->customer(), $this->items())->assertCreated()->assertJsonPath('data.provider', 'mock');
    }

    public function test_the_sandbox_is_on_by_default_outside_production(): void
    {
        $manager = app(PaymentGatewayManager::class);

        $this->assertTrue($manager->hasOnlinePayment());
        $this->assertSame(['mock'], $manager->enabled());
    }

    public function test_a_real_gateway_is_offered_in_production_whatever_the_sandbox_setting(): void
    {
        $this->asProduction();
        config(['services.razorpay.key_id' => 'rzp_test_x', 'services.razorpay.key_secret' => 's']);
        $this->app->forgetInstance(PaymentGatewayManager::class);

        $this->assertSame(['razorpay'], app(PaymentGatewayManager::class)->enabled());
    }

    public function test_old_sandbox_payments_stay_addressable_in_production_so_they_can_still_be_handled(): void
    {
        $this->asProduction();

        $this->assertSame('mock', app(PaymentGatewayManager::class)->driver('mock')->key());
        $this->assertFalse(app(PaymentGatewayManager::class)->hasOnlinePayment());
    }

    #[DataProvider('sandboxSettings')]
    public function test_the_sandbox_setting_is_read_the_way_it_is_written(string $written, ?bool $expected): void
    {
        putenv("PAYMENTS_ALLOW_SANDBOX={$written}");
        $_ENV['PAYMENTS_ALLOW_SANDBOX'] = $_SERVER['PAYMENTS_ALLOW_SANDBOX'] = $written;

        try {
            $this->assertSame($expected, (require config_path('payments.php'))['allow_sandbox']);
        } finally {
            putenv('PAYMENTS_ALLOW_SANDBOX');
            unset($_ENV['PAYMENTS_ALLOW_SANDBOX'], $_SERVER['PAYMENTS_ALLOW_SANDBOX']);
        }
    }

    public static function sandboxSettings(): array
    {
        return [
            'blank means default (as in .env.example)' => ['', null],
            'spaces mean default' => ['   ', null],
            'null means default' => ['null', null],
            'true' => ['true', true],
            'TRUE' => ['TRUE', true],
            '1' => ['1', true],
            'false' => ['false', false],
            '0' => ['0', false],
        ];
    }

    // ── Orders from before the ledger ───────────────────────────────────

    /** A prepaid order with no payment record, as one placed before the ledger existed. */
    private function legacyPrepaid(User $user, float $price = 1000, int $qty = 1, bool $useWallet = false): Order
    {
        $this->actingAs($user, 'sanctum')->postJson('/api/v1/orders/checkout', [
            'items' => $this->items($price, $qty),
            'shipping_address' => self::ADDRESS,
            'payment_method' => 'COD',
            'use_wallet' => $useWallet,
        ])->assertCreated();

        $order = Order::with('items')->latest('created_at')->latest('id')->firstOrFail();
        $order->update(['payment_method' => 'UPI', 'payment_status' => 'PAID', 'transaction_id' => 'pay_mock_legacy00000']);

        return $order->fresh('items');
    }

    private function cancel(User $user, Order $order): TestResponse
    {
        return $this->actingAs($user, 'sanctum')->postJson("/api/v1/orders/{$order->id}/cancel", ['reason' => 'Changed my mind']);
    }

    private function returnAndRefund(User $user, Order $order, string $mode): TestResponse
    {
        $order->update(['status' => 'DELIVERED', 'delivered_at' => now()->subDay()]);

        $this->actingAs($user, 'sanctum')->postJson('/api/v1/returns', [
            'order_item_id' => $order->items->first()->id, 'kind' => 'RETURN', 'reason' => 'Did not fit', 'refund_mode' => $mode,
        ])->assertCreated();

        $rma = ReturnRequest::firstOrFail();
        $admin = $this->admin();
        $this->actingAs($admin, 'sanctum')->postJson("/api/v1/admin/returns/{$rma->id}/approve")->assertOk();
        $this->actingAs($admin, 'sanctum')->postJson("/api/v1/admin/returns/{$rma->id}/picked-up")->assertOk();

        return $this->actingAs($admin, 'sanctum')->postJson("/api/v1/admin/returns/{$rma->id}/refund", ['refund_mode' => $mode]);
    }

    public function test_cancelling_an_order_with_no_payment_record_does_not_invent_wallet_credit(): void
    {
        app(PaymentGatewayManager::class)->register($gateway = new FakeGateway('fakepay'));
        $user = $this->customer();
        $order = $this->legacyPrepaid($user);

        $this->cancel($user, $order)->assertOk();

        $this->assertEquals(0.0, (float) $user->fresh()->wallet_balance, 'no money was collected, so none comes back');
        $this->assertCount(0, $gateway->refunds);
        $this->assertSame('SKIPPED', Refund::firstOrFail()->status);
        $this->assertSame('CANCELLED', $order->fresh()->status);
    }

    public function test_wallet_money_the_customer_really_spent_still_comes_back(): void
    {
        $user = $this->customer();
        WalletController::apply($user, 'CREDIT', 400, 'top-up');
        $order = $this->legacyPrepaid($user, useWallet: true);
        $this->assertEquals(400.0, (float) $order->wallet_applied);

        $this->cancel($user, $order)->assertOk();

        $this->assertEquals(400.0, (float) $user->fresh()->wallet_balance, 'only the wallet share is returned');
        $this->assertSame(1, Refund::where('destination', 'WALLET')->count());
        $this->assertSame(1, Refund::where('status', 'SKIPPED')->count());
    }

    public function test_a_source_return_on_such_an_order_moves_no_money(): void
    {
        $user = $this->customer();
        $order = $this->legacyPrepaid($user);

        $this->returnAndRefund($user, $order, 'SOURCE')->assertOk();

        $this->assertEquals(0.0, (float) $user->fresh()->wallet_balance);
        $this->assertSame('SKIPPED', Refund::firstOrFail()->status);
        $this->assertSame('COMPLETED', ReturnRequest::firstOrFail()->refund_status, 'the return itself still completes');
    }

    public function test_a_return_to_the_wallet_still_credits_it_as_it_always_did(): void
    {
        $user = $this->customer();
        $order = $this->legacyPrepaid($user);

        $this->returnAndRefund($user, $order, 'WALLET')->assertOk();

        $this->assertEquals(1000.0, (float) $user->fresh()->wallet_balance);
    }

    public function test_the_customer_is_not_told_a_refund_happened_when_nothing_moved(): void
    {
        $user = $this->customer();
        $order = $this->legacyPrepaid($user);

        $this->returnAndRefund($user, $order, 'SOURCE')->assertOk();

        $titles = \App\Models\AppNotification::where('user_id', $user->id)->pluck('title')->implode(' | ');
        $this->assertStringContainsString('nothing to send back', $titles);
        $this->assertStringNotContainsString('refunded ₹', $titles);
    }

    public function test_cash_on_delivery_orders_are_unaffected_and_still_refund_to_the_wallet(): void
    {
        $user = $this->customer();
        $this->actingAs($user, 'sanctum')->postJson('/api/v1/orders/checkout', [
            'items' => $this->items(), 'shipping_address' => self::ADDRESS, 'payment_method' => 'COD',
        ])->assertCreated();
        $order = Order::with('items')->firstOrFail();

        $this->returnAndRefund($user, $order, 'SOURCE')->assertOk();

        $this->assertEquals(1000.0, (float) $user->fresh()->wallet_balance, 'the cash was really collected');
        $this->assertSame('WALLET', Refund::firstOrFail()->destination);
    }
}
