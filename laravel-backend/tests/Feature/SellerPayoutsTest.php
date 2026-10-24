<?php

namespace Tests\Feature;

use App\Models\AppNotification;
use App\Models\Order;
use App\Models\Product;
use App\Models\ProductVariant;
use App\Models\Seller;
use App\Models\SellerKycProfile;
use App\Models\SellerLedgerEntry;
use App\Models\User;
use App\Services\SellerPayoutService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Validation\ValidationException;
use Tests\TestCase;

/**
 * Paying sellers: only for orders that are delivered and past the return window,
 * recorded against a bank reference, and never more than is payable. And telling
 * a seller when an order arrives.
 */
class SellerPayoutsTest extends TestCase
{
    use RefreshDatabase;

    private const ADDRESS = [
        'name' => 'Priya Sharma', 'phone' => '9876543210', 'line1' => '221B Indiranagar',
        'city' => 'Bengaluru', 'state' => 'Karnataka', 'pincode' => '560038',
    ];

    private function seller(): Seller
    {
        $user = User::factory()->create(['role' => User::ROLE_SELLER, 'status' => 'ACTIVE']);

        return Seller::factory()->create(['user_id' => $user->id, 'commission_rate' => 10]);
    }

    private function admin(): User
    {
        return User::factory()->create(['role' => User::ROLE_ADMIN, 'status' => 'ACTIVE']);
    }

    /** A COD order of one unit of each product (Rs 1000 each, so a seller earns Rs 900 per line). */
    private function buy(array $products): Order
    {
        $customer = User::factory()->create(['role' => 'CUSTOMER', 'status' => 'ACTIVE']);

        $number = $this->actingAs($customer, 'sanctum')->postJson('/api/v1/orders/checkout', [
            'items' => collect($products)->map(fn ($p) => [
                'product_id' => $p->id, 'variant_id' => $p->variants->first()->id, 'quantity' => 1,
            ])->all(),
            'shipping_address' => self::ADDRESS,
            'payment_method' => 'COD',
        ])->assertCreated()->json('data.order_number');

        return Order::where('order_number', $number)->firstOrFail();
    }

    private function product(Seller $seller): Product
    {
        $product = Product::factory()->pricedAt(1000)->soldBy($seller)->create();
        ProductVariant::factory()->withStock(20)->create(['product_id' => $product->id]);

        return $product->fresh('variants');
    }

    private function delivered(Order $order, int $daysAgo): void
    {
        $order->update(['status' => 'DELIVERED', 'delivered_at' => now()->subDays($daysAgo)]);
    }

    private function payouts(): SellerPayoutService
    {
        return app(SellerPayoutService::class);
    }

    // ── What is payable ──────────────────────────────────────────────────

    public function test_a_sale_is_owed_at_once_but_is_not_payable_until_it_is_delivered_and_the_return_window_passes(): void
    {
        $seller = $this->seller();
        $order = $this->buy([$this->product($seller)]);

        $this->assertSame(900.0, (float) $seller->fresh()->payout_balance);
        $this->assertSame(900.0, $this->payouts()->pending($seller));
        $this->assertSame(0.0, $this->payouts()->withdrawable($seller), 'not even shipped');

        $this->delivered($order, 0);
        $this->assertSame(900.0, $this->payouts()->pending($seller), 'delivered today: the goods can still come back');
        $this->assertSame(0.0, $this->payouts()->withdrawable($seller));

        $this->delivered($order, 6);
        $this->assertSame(900.0, $this->payouts()->pending($seller->fresh()), 'day six of a seven-day window');

        $this->delivered($order, 8);
        $this->assertSame(0.0, $this->payouts()->pending($seller->fresh()));
        $this->assertSame(900.0, $this->payouts()->withdrawable($seller->fresh()), 'the window has passed');
    }

    public function test_each_order_clears_on_its_own_clock(): void
    {
        $seller = $this->seller();
        $old = $this->buy([$this->product($seller)]);
        $recent = $this->buy([$this->product($seller)]);
        $this->delivered($old, 10);
        $this->delivered($recent, 2);

        $this->assertSame(1800.0, (float) $seller->fresh()->payout_balance);
        $this->assertSame(900.0, $this->payouts()->pending($seller->fresh()));
        $this->assertSame(900.0, $this->payouts()->withdrawable($seller->fresh()));
    }

    public function test_a_refund_on_a_cleared_order_comes_out_of_what_is_payable(): void
    {
        $seller = $this->seller();
        $order = $this->buy([$this->product($seller)]);
        $this->delivered($order, 10);
        $item = $order->items()->first();
        $this->payouts()->debitRefund($item, $order, 1, 1000.0);   // the whole line comes back

        $this->assertSame(0.0, (float) $seller->fresh()->payout_balance);
        $this->assertSame(0.0, $this->payouts()->withdrawable($seller->fresh()));
    }

    public function test_a_cancelled_order_nets_to_nothing_pending(): void
    {
        $seller = $this->seller();
        $order = $this->buy([$this->product($seller)]);
        $item = $order->items()->first();
        $this->payouts()->debitRefund($item, $order, 1, 1000.0);
        $order->update(['status' => 'CANCELLED']);

        $this->assertSame(0.0, $this->payouts()->pending($seller->fresh()));
    }

    public function test_it_is_never_negative(): void
    {
        $seller = $this->seller();
        $this->payouts()->adjust($seller, -50, 'chargeback');

        $this->assertSame(0.0, $this->payouts()->pending($seller));
        $this->assertSame(0.0, $this->payouts()->withdrawable($seller->fresh()));
    }

    // ── Recording a payout ───────────────────────────────────────────────

    public function test_a_payout_debits_the_balance_and_leaves_a_traceable_entry(): void
    {
        $seller = $this->seller();
        $this->delivered($this->buy([$this->product($seller)]), 10);

        $entry = $this->payouts()->recordPayout($seller, 500, 'UTR123456');

        $this->assertSame('PAYOUT', $entry->type);
        $this->assertSame(-500.0, (float) $entry->net);
        $this->assertStringContainsString('UTR123456', $entry->note);
        $this->assertSame(400.0, (float) $seller->fresh()->payout_balance);
        $this->assertSame(400.0, $this->payouts()->withdrawable($seller->fresh()));
    }

    public function test_it_cannot_pay_out_more_than_is_payable(): void
    {
        $seller = $this->seller();
        $this->delivered($this->buy([$this->product($seller)]), 10);   // 900 payable
        $this->buy([$this->product($seller)]);                         // 900 more, still pending

        $this->assertSame(1800.0, (float) $seller->fresh()->payout_balance);

        try {
            $this->payouts()->recordPayout($seller->fresh(), 1000, 'UTR1');
            $this->fail('1000 is more than the 900 that is payable');
        } catch (ValidationException $e) {
            $this->assertStringContainsString('₹900.00', $e->errors()['amount'][0]);
        }

        $this->assertSame(1800.0, (float) $seller->fresh()->payout_balance, 'nothing was taken');
        $this->payouts()->recordPayout($seller->fresh(), 900, 'UTR2');
        $this->assertSame(900.0, (float) $seller->fresh()->payout_balance);
    }

    public function test_with_nothing_payable_it_says_when_money_becomes_payable(): void
    {
        $seller = $this->seller();
        $this->buy([$this->product($seller)]);

        try {
            $this->payouts()->recordPayout($seller->fresh(), 100, 'UTR1');
            $this->fail('nothing is payable yet');
        } catch (ValidationException $e) {
            $this->assertStringContainsString('delivered and the return window has passed', $e->errors()['amount'][0]);
        }
    }

    public function test_a_payout_of_nothing_or_less_is_refused(): void
    {
        $seller = $this->seller();
        $this->delivered($this->buy([$this->product($seller)]), 10);

        foreach ([0, -10] as $amount) {
            try {
                $this->payouts()->recordPayout($seller->fresh(), $amount, 'UTR');
                $this->fail("{$amount} is not a payout");
            } catch (ValidationException) {
                $this->assertTrue(true);
            }
        }
    }

    // ── The admin's view ─────────────────────────────────────────────────

    public function test_the_admin_sees_each_vendor_with_owed_pending_and_payable(): void
    {
        $paid = $this->seller();
        $waiting = $this->seller();
        $this->delivered($this->buy([$this->product($paid)]), 10);
        $this->buy([$this->product($waiting)]);
        $paid->kyc()->create([
            'business_type' => 'INDIVIDUAL', 'legal_name' => 'A Seller',
            'bank_account_holder' => 'A Seller', 'bank_account_number' => '123456789012', 'bank_ifsc' => 'HDFC0001234', 'bank_name' => 'HDFC Bank',
        ]);

        $response = $this->actingAs($this->admin(), 'sanctum')->getJson('/api/v1/admin/payouts')->assertOk();
        $rows = collect($response->json('data'))->keyBy('id');

        $this->assertEquals(900, $rows[$paid->id]['balance']);
        $this->assertEquals(0, $rows[$paid->id]['pending']);
        $this->assertEquals(900, $rows[$paid->id]['withdrawable']);
        $this->assertEquals(900, $rows[$waiting->id]['pending']);
        $this->assertEquals(0, $rows[$waiting->id]['withdrawable']);
        $this->assertEquals(1800, $response->json('totals.owed'));
        $this->assertEquals(900, $response->json('totals.withdrawable'));

        $bank = $rows[$paid->id]['bank'];
        $this->assertSame('9012', $bank['account_last4'], 'enough to find the account, not the number itself');
        $this->assertStringNotContainsString('123456789012', json_encode($response->json()));
        $this->assertNull($rows[$waiting->id]['bank']);
    }

    public function test_the_owners_own_shop_is_not_in_the_payout_list(): void
    {
        $house = \Database\Factories\SellerFactory::house();
        $vendor = $this->seller();

        $ids = collect($this->actingAs($this->admin(), 'sanctum')->getJson('/api/v1/admin/payouts')->json('data'))->pluck('id');

        $this->assertTrue($ids->contains($vendor->id));
        $this->assertFalse($ids->contains($house->id));
    }

    public function test_the_admin_records_a_transfer_and_the_list_shows_it(): void
    {
        $seller = $this->seller();
        $this->delivered($this->buy([$this->product($seller)]), 10);
        $admin = $this->admin();

        $this->actingAs($admin, 'sanctum')->postJson("/api/v1/admin/sellers/{$seller->id}/payouts", ['amount' => 600, 'reference' => 'UTR998877'])
            ->assertCreated()
            ->assertJsonPath('seller.balance', 300)
            ->assertJsonPath('seller.withdrawable', 300);

        $row = collect($this->actingAs($admin, 'sanctum')->getJson('/api/v1/admin/payouts')->json('data'))->firstWhere('id', $seller->id);
        $this->assertEquals(600, $row['last_payout']['amount']);
        $this->assertStringContainsString('UTR998877', $row['last_payout']['note']);
    }

    public function test_recording_too_much_is_a_clear_refusal_not_an_overdraft(): void
    {
        $seller = $this->seller();
        $this->buy([$this->product($seller)]);   // pending only

        $this->actingAs($this->admin(), 'sanctum')->postJson("/api/v1/admin/sellers/{$seller->id}/payouts", ['amount' => 100, 'reference' => 'UTR1'])
            ->assertStatus(422)->assertJsonValidationErrors('amount');

        $this->assertSame(900.0, (float) $seller->fresh()->payout_balance);
    }

    public function test_a_reference_and_an_amount_are_required(): void
    {
        $seller = $this->seller();
        $post = fn (array $body) => $this->actingAs($this->admin(), 'sanctum')->postJson("/api/v1/admin/sellers/{$seller->id}/payouts", $body);

        $post(['amount' => 100])->assertStatus(422)->assertJsonValidationErrors('reference');
        $post(['reference' => 'UTR1'])->assertStatus(422)->assertJsonValidationErrors('amount');
        $post(['amount' => 0, 'reference' => 'UTR1'])->assertStatus(422)->assertJsonValidationErrors('amount');
    }

    public function test_only_staff_can_see_or_record_payouts(): void
    {
        $seller = $this->seller();
        $customer = User::factory()->create(['role' => 'CUSTOMER', 'status' => 'ACTIVE']);

        $this->getJson('/api/v1/admin/payouts')->assertUnauthorized();
        $this->actingAs($customer, 'sanctum')->getJson('/api/v1/admin/payouts')->assertForbidden();
        $this->actingAs($seller->user, 'sanctum')->getJson('/api/v1/admin/payouts')->assertForbidden();
        $this->actingAs($seller->user, 'sanctum')->postJson("/api/v1/admin/sellers/{$seller->id}/payouts", ['amount' => 100, 'reference' => 'X'])->assertForbidden();
    }

    public function test_the_house_shop_cannot_be_paid_out(): void
    {
        $house = \Database\Factories\SellerFactory::house();

        $this->actingAs($this->admin(), 'sanctum')->postJson("/api/v1/admin/sellers/{$house->id}/payouts", ['amount' => 100, 'reference' => 'X'])
            ->assertNotFound();
    }

    // ── The seller's view ────────────────────────────────────────────────

    public function test_the_seller_sees_what_is_pending_and_what_is_payable_and_their_payouts(): void
    {
        $seller = $this->seller();
        $this->delivered($this->buy([$this->product($seller)]), 10);
        $this->buy([$this->product($seller)]);
        $this->payouts()->recordPayout($seller->fresh(), 400, 'UTR55');

        $response = $this->actingAs($seller->user, 'sanctum')->getJson('/api/v1/seller/ledger')->assertOk();

        $this->assertEquals(1400, $response->json('balance'));
        $this->assertEquals(900, $response->json('pending'));
        $this->assertEquals(500, $response->json('withdrawable'));
        $this->assertContains('PAYOUT', collect($response->json('data'))->pluck('type')->all());
    }

    // ── Telling a seller about a new order ───────────────────────────────

    public function test_a_seller_is_told_about_a_new_order(): void
    {
        $seller = $this->seller();
        $order = $this->buy([$this->product($seller), $this->product($seller)]);

        $note = AppNotification::where('user_id', $seller->user_id)->where('type', 'SELLER_ORDER')->first();

        $this->assertNotNull($note);
        $this->assertSame("New order {$order->order_number}: 2 items to pack", $note->title);
        $this->assertStringContainsString('₹1,800.00', $note->body);
        $this->assertTrue($note->data['seller_order']);
        $this->assertArrayNotHasKey('order_id', $note->data, 'a tap must not open the shopper\'s order page');
    }

    public function test_each_seller_is_told_only_about_their_own_goods(): void
    {
        $a = $this->seller();
        $b = $this->seller();
        config(['marketplace.cart_rule' => 'mixed']);
        $this->buy([$this->product($a), $this->product($b)]);

        $forA = AppNotification::where('user_id', $a->user_id)->where('type', 'SELLER_ORDER')->get();
        $forB = AppNotification::where('user_id', $b->user_id)->where('type', 'SELLER_ORDER')->get();

        $this->assertCount(1, $forA);
        $this->assertCount(1, $forB);
        $this->assertStringContainsString('1 item to pack', $forA->first()->title);
        $this->assertStringContainsString('₹900.00', $forA->first()->body, 'their share, not the whole basket');
    }

    public function test_the_owners_own_shop_has_nobody_to_tell_and_that_is_fine(): void
    {
        $house = \Database\Factories\SellerFactory::house();
        $this->buy([$this->product($house)]);

        $this->assertSame(0, AppNotification::where('type', 'SELLER_ORDER')->count());
    }

    public function test_a_seller_who_turned_the_alerts_off_is_left_alone(): void
    {
        $seller = $this->seller();
        $seller->user->update(['notification_preferences' => ['SELLER_ORDER' => false]]);

        $this->buy([$this->product($seller)]);

        $this->assertSame(0, AppNotification::where('user_id', $seller->user_id)->where('type', 'SELLER_ORDER')->count());
    }

    public function test_a_notification_that_fails_does_not_lose_the_order(): void
    {
        $seller = $this->seller();
        $this->app->bind(\App\Services\NotificationService::class, fn () => new class(app(\App\Services\Messaging\SmsGatewayManager::class)) extends \App\Services\NotificationService {
            public function newSellerOrder($order): void
            {
                throw new \RuntimeException('push provider down');
            }
        });

        $order = $this->buy([$this->product($seller)]);

        $this->assertSame('CONFIRMED', $order->fresh()->status);
    }
}
