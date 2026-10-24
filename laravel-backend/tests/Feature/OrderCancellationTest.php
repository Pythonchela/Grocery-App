<?php

namespace Tests\Feature;

use App\Models\LoyaltyTransaction;
use App\Models\Order;
use App\Models\Product;
use App\Models\ProductVariant;
use App\Models\User;
use App\Services\LoyaltyService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Cancelling has to unwind everything the order did.
 *
 * It used to restock and refund the wallet but silently keep the loyalty points
 * the order had earned, and swallow the ones it consumed. Place, cancel, repeat
 * was a points printer, and a customer who spent points on a cancelled order
 * simply lost them.
 */
class OrderCancellationTest extends TestCase
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

    private function product(float $price = 1000, int $stock = 10): Product
    {
        $product = Product::factory()->pricedAt($price)->create();
        ProductVariant::factory()->withStock($stock)->create(['product_id' => $product->id]);

        return $product->fresh('variants');
    }

    private function placeCod(User $user, Product $product, array $extra = []): Order
    {
        // Resolved by the order number the API returned, not by `latest()`:
        // two orders placed in the same test share a created_at to the second,
        // which makes "the most recent one" a coin flip.
        $number = $this->actingAs($user, 'sanctum')
            ->postJson('/api/v1/orders/checkout', array_merge([
                'items' => [[
                    'product_id' => $product->id,
                    'variant_id' => $product->variants->first()->id,
                    'quantity' => 1,
                ]],
                'shipping_address' => self::ADDRESS,
                'payment_method' => 'COD',
            ], $extra))
            ->assertCreated()
            ->json('data.order_number');

        return Order::where('order_number', $number)->firstOrFail();
    }

    private function cancel(User $user, Order $order): \Illuminate\Testing\TestResponse
    {
        return $this->actingAs($user, 'sanctum')
            ->postJson("/api/v1/orders/{$order->id}/cancel", ['reason' => 'changed my mind']);
    }

    // ── Loyalty ─────────────────────────────────────────────────────────

    public function test_points_earned_on_a_cancelled_order_are_taken_back(): void
    {
        $user = $this->customer();
        $order = $this->placeCod($user, $this->product(2000));

        $earned = (int) $order->points_earned;
        $this->assertGreaterThan(0, $earned, 'the order should have earned points to reverse');
        $this->assertSame($earned, (int) $user->fresh()->loyalty_points);

        $this->cancel($user, $order)->assertOk();

        $this->assertSame(0, (int) $user->fresh()->loyalty_points);
        $this->assertSame(1, LoyaltyTransaction::where('type', 'REVOKE')->count());
    }

    public function test_points_redeemed_on_a_cancelled_order_are_returned(): void
    {
        $user = $this->customer();
        app(LoyaltyService::class)->credit($user, 1000, 'Seeded for test');

        $order = $this->placeCod($user, $this->product(2000), ['redeem_points' => 400]);

        $this->assertSame(400, (int) $order->points_redeemed);

        $this->cancel($user, $order)->assertOk();

        // Redeemed points come back, earned points go away: the customer ends
        // exactly where they started.
        $this->assertSame(1000, (int) $user->fresh()->loyalty_points);
    }

    public function test_redeeming_points_reduces_what_is_payable(): void
    {
        $user = $this->customer();
        app(LoyaltyService::class)->credit($user, 1000, 'Seeded for test');

        $plain = $this->placeCod($user, $this->product(2000));
        $discounted = $this->placeCod($user, $this->product(2000), ['redeem_points' => 400]);

        $this->assertLessThan((float) $plain->total_amount, (float) $discounted->total_amount);
        // 400 points at the default ₹0.25 each.
        $this->assertEquals(100.0, (float) $plain->total_amount - (float) $discounted->total_amount);
    }

    public function test_a_user_cannot_redeem_more_points_than_they_hold(): void
    {
        $user = $this->customer();
        app(LoyaltyService::class)->credit($user, 10, 'Seeded for test');

        $order = $this->placeCod($user, $this->product(2000), ['redeem_points' => 99999]);

        $this->assertLessThanOrEqual(10, (int) $order->points_redeemed);
        $this->assertGreaterThanOrEqual(0, (int) $user->fresh()->loyalty_points);
    }

    public function test_the_clawback_stops_at_zero_when_points_were_already_spent(): void
    {
        $user = $this->customer();
        $order = $this->placeCod($user, $this->product(2000));

        // Spend everything the order earned before cancelling it.
        $earned = (int) $user->fresh()->loyalty_points;
        app(LoyaltyService::class)->redeem($user, $earned, 'Spent elsewhere');
        $this->assertSame(0, (int) $user->fresh()->loyalty_points);

        $this->cancel($user, $order)->assertOk();

        // No negative balance, and no exception that would block the refund.
        $this->assertSame(0, (int) $user->fresh()->loyalty_points);
    }

    // ── Stock, wallet, and access ────────────────────────────────────────

    public function test_cancelling_restocks_the_units(): void
    {
        $user = $this->customer();
        $product = $this->product(1000, stock: 10);
        $variant = $product->variants->first();

        $order = $this->placeCod($user, $product);
        $this->assertSame(9, $variant->fresh()->stock);

        $this->cancel($user, $order)->assertOk();

        $this->assertSame(10, $variant->fresh()->stock);
        $this->assertSame('CANCELLED', $order->fresh()->status);
    }

    public function test_cancelling_returns_the_wallet_amount_that_was_applied(): void
    {
        $user = $this->customer();
        \App\Http\Controllers\Api\WalletController::apply($user, 'CREDIT', 500, 'Seeded for test');

        $order = $this->placeCod($user, $this->product(2000), ['use_wallet' => true]);

        $this->assertEquals(500.0, (float) $order->wallet_applied);
        $this->assertEquals(0.0, (float) $user->fresh()->wallet_balance);

        $this->cancel($user, $order)->assertOk();

        $this->assertEquals(500.0, (float) $user->fresh()->wallet_balance);
    }

    public function test_a_dispatched_order_can_no_longer_be_cancelled(): void
    {
        $user = $this->customer();
        $product = $this->product(1000, stock: 10);
        $order = $this->placeCod($user, $product);
        $order->update(['status' => 'SHIPPED']);

        $this->cancel($user, $order)->assertStatus(422);

        $this->assertSame('SHIPPED', $order->fresh()->status);
        // Critically, nothing was unwound on the way to refusing.
        $this->assertSame(9, $product->variants->first()->fresh()->stock);
        $this->assertSame((int) $order->points_earned, (int) $user->fresh()->loyalty_points);
    }

    public function test_a_user_cannot_cancel_someone_elses_order(): void
    {
        $owner = $this->customer();
        $stranger = $this->customer();
        $order = $this->placeCod($owner, $this->product(1000));

        $this->cancel($stranger, $order)->assertForbidden();

        $this->assertSame('CONFIRMED', $order->fresh()->status);
    }
}
