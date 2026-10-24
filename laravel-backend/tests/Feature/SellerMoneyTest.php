<?php

namespace Tests\Feature;

use App\Models\Order;
use App\Models\PayoutRequest;
use App\Models\Product;
use App\Models\ProductVariant;
use App\Models\Seller;
use App\Models\SellerLedgerEntry;
use App\Models\User;
use App\Services\SellerPayoutService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Getting paid: tax lines on a sale, payout requests, bank changes that need
 * confirming, and monthly statements read from the ledger.
 */
class SellerMoneyTest extends TestCase
{
    use RefreshDatabase;

    private const ADDRESS = [
        'name' => 'Priya Sharma', 'phone' => '9876543210', 'line1' => '221B Indiranagar',
        'city' => 'Bengaluru', 'state' => 'Karnataka', 'pincode' => '560038',
    ];

    private function seller(bool $withBank = true): Seller
    {
        $user = User::factory()->create(['role' => User::ROLE_SELLER, 'status' => 'ACTIVE']);
        $seller = Seller::factory()->create(['user_id' => $user->id, 'status' => 'ACTIVE', 'commission_rate' => 10]);

        if ($withBank) {
            $kyc = $seller->kyc()->create([
                'business_type' => 'INDIVIDUAL', 'legal_name' => 'A Seller',
                'bank_account_holder' => 'A Seller', 'bank_account_number' => '123456789012',
                'bank_ifsc' => 'HDFC0001234', 'bank_name' => 'HDFC Bank',
            ]);
            $kyc->forceFill(['status' => 'APPROVED'])->save();
        }

        return $seller->fresh();
    }

    private function admin(): User
    {
        return User::factory()->create(['role' => User::ROLE_ADMIN, 'status' => 'ACTIVE']);
    }

    /** Money a seller can withdraw right now, put there the way staff do. */
    private function fund(Seller $seller, float $amount): void
    {
        app(SellerPayoutService::class)->adjust($seller, $amount, 'Test credit');
    }

    private function buyOne(Seller $seller, float $price = 1000): Order
    {
        $product = Product::factory()->pricedAt($price)->soldBy($seller)->create();
        ProductVariant::factory()->withStock(10)->create(['product_id' => $product->id]);
        $product = $product->fresh('variants');
        $customer = User::factory()->create(['role' => 'CUSTOMER', 'status' => 'ACTIVE']);

        $number = $this->actingAs($customer, 'sanctum')->postJson('/api/v1/orders/checkout', [
            'items' => [['product_id' => $product->id, 'variant_id' => $product->variants->first()->id, 'quantity' => 1]],
            'shipping_address' => self::ADDRESS,
            'payment_method' => 'COD',
        ])->assertCreated()->json('data.order_number');

        return Order::with('items')->where('order_number', $number)->firstOrFail();
    }

    private function as(Seller $seller)
    {
        return $this->actingAs($seller->user, 'sanctum');
    }

    // ── Tax lines ────────────────────────────────────────────────────────

    public function test_with_no_rates_set_the_split_is_exactly_what_it_was(): void
    {
        $seller = $this->seller();
        $line = $this->buyOne($seller)->items->first();

        $this->assertEquals(100.0, (float) $line->commission_amount);
        $this->assertEquals(900.0, (float) $line->seller_earning);
        $this->assertEquals(0.0, (float) $line->gst_on_commission);
        $this->assertEquals(0.0, (float) $line->tcs);
    }

    public function test_tax_lines_come_off_the_sale_and_are_reversed_in_proportion_on_cancel(): void
    {
        config(['marketplace.commission_gst_percent' => 18, 'marketplace.tcs_percent' => 1, 'marketplace.tds_percent' => 1]);
        $seller = $this->seller();
        $order = $this->buyOne($seller);
        $line = $order->items->first();

        // 1000 gross: commission 100, GST 18, TCS 10, TDS 10 => 862 to the seller.
        $this->assertEquals(18.0, (float) $line->gst_on_commission);
        $this->assertEquals(10.0, (float) $line->tcs);
        $this->assertEquals(862.0, (float) $line->seller_earning);

        $sale = SellerLedgerEntry::where('type', 'SALE')->where('seller_id', $seller->id)->firstOrFail();
        $this->assertEquals(18.0, (float) $sale->gst);
        $this->assertEquals(862.0, (float) $sale->net);
        $this->assertEquals(862.0, (float) $seller->fresh()->payout_balance);

        $this->actingAs($order->user, 'sanctum')->postJson("/api/v1/orders/{$order->id}/cancel")->assertOk();

        $refund = SellerLedgerEntry::where('type', 'REFUND')->where('seller_id', $seller->id)->firstOrFail();
        $this->assertEquals(-18.0, (float) $refund->gst);
        $this->assertEquals(-10.0, (float) $refund->tcs);
        $this->assertEquals(0.0, (float) $seller->fresh()->payout_balance, 'a cancelled sale leaves nothing owed');
    }

    // ── Payout requests ──────────────────────────────────────────────────

    public function test_a_seller_asks_for_money_and_staff_pay_it_with_a_bank_reference(): void
    {
        $seller = $this->seller();
        $this->fund($seller, 1500);

        $money = $this->as($seller)->getJson('/api/v1/seller/money')->assertOk()->json('data');
        $this->assertEquals(1500, $money['withdrawable']);
        $this->assertNull($money['blocker']);
        $this->assertSame('9012', $money['bank']['account_last4']);
        $this->assertStringNotContainsString('123456789012', json_encode($money));

        $id = $this->as($seller)->postJson('/api/v1/seller/payout-requests', ['amount' => 1000])->assertCreated()->json('data.id');
        $this->as($seller)->postJson('/api/v1/seller/payout-requests', ['amount' => 100])->assertStatus(422);

        $this->actingAs($this->admin(), 'sanctum')->postJson("/api/v1/admin/payout-requests/{$id}/pay", ['reference' => 'UTR123'])->assertOk();

        $request = PayoutRequest::findOrFail($id);
        $this->assertSame('PAID', $request->status);
        $this->assertSame('UTR123', $request->reference);
        $this->assertEquals(500, (float) $seller->fresh()->payout_balance);
        $this->assertNotNull($request->ledger_entry_id);

        $this->actingAs($this->admin(), 'sanctum')->postJson("/api/v1/admin/payout-requests/{$id}/pay", ['reference' => 'UTR124'])->assertStatus(422);
    }

    public function test_the_default_amount_is_everything_withdrawable_and_the_rules_hold(): void
    {
        $seller = $this->seller();
        $this->as($seller)->postJson('/api/v1/seller/payout-requests', [])->assertStatus(422); // nothing to pay yet

        $this->fund($seller, 500);
        $this->as($seller)->postJson('/api/v1/seller/payout-requests', ['amount' => 50])->assertStatus(422); // below the minimum
        $this->as($seller)->postJson('/api/v1/seller/payout-requests', ['amount' => 900])->assertStatus(422); // more than withdrawable

        $request = $this->as($seller)->postJson('/api/v1/seller/payout-requests', [])->assertCreated()->json('data');
        $this->assertEquals(500, (float) $request['amount']);

        $this->as($seller)->deleteJson("/api/v1/seller/payout-requests/{$request['id']}")->assertOk();
        $this->assertSame('CANCELLED', PayoutRequest::find($request['id'])->status);
    }

    public function test_pending_earnings_cannot_be_requested(): void
    {
        $seller = $this->seller();
        $this->buyOne($seller); // balance 900, but not delivered, so pending

        $this->assertEquals(0, $this->as($seller)->getJson('/api/v1/seller/money')->json('data.withdrawable'));
        $this->as($seller)->postJson('/api/v1/seller/payout-requests', ['amount' => 500])->assertStatus(422);
    }

    public function test_staff_can_decline_with_a_reason_and_the_seller_is_told(): void
    {
        $seller = $this->seller();
        $this->fund($seller, 800);
        $id = $this->as($seller)->postJson('/api/v1/seller/payout-requests', [])->assertCreated()->json('data.id');

        $this->actingAs($this->admin(), 'sanctum')->postJson("/api/v1/admin/payout-requests/{$id}/reject", ['reason' => 'Bank name does not match'])->assertOk();

        $this->assertSame('REJECTED', PayoutRequest::find($id)->status);
        $this->assertEquals(800, (float) $seller->fresh()->payout_balance);
        $this->assertDatabaseHas('app_notifications', ['user_id' => $seller->user_id, 'type' => 'SELLER_PAYOUT']);
    }

    public function test_without_a_verified_bank_account_nothing_can_be_requested(): void
    {
        $seller = $this->seller(withBank: false);
        $this->fund($seller, 800);

        $this->as($seller)->postJson('/api/v1/seller/payout-requests', [])->assertStatus(422);
    }

    // ── Bank changes ─────────────────────────────────────────────────────

    public function test_a_bank_change_waits_for_staff_and_blocks_payout_requests_meanwhile(): void
    {
        $seller = $this->seller();
        $this->fund($seller, 800);

        $this->as($seller)->postJson('/api/v1/seller/bank', [
            'bank_account_holder' => 'A Seller', 'bank_account_number' => '999988887777', 'bank_ifsc' => 'sbin0000001', 'bank_name' => 'SBI',
        ])->assertStatus(202);

        $kyc = $seller->fresh()->kyc;
        $this->assertSame('123456789012', $kyc->bank_account_number, 'nothing changes on the seller\'s word');
        $this->as($seller)->postJson('/api/v1/seller/payout-requests', [])->assertStatus(422);

        $admin = $this->actingAs($this->admin(), 'sanctum');
        $listed = $admin->getJson('/api/v1/admin/bank-changes')->assertOk();
        $this->assertSame('7777', $listed->json('data.0.proposed.account_last4'));
        $this->assertStringNotContainsString('999988887777', json_encode($listed->json()));

        $this->actingAs($this->admin(), 'sanctum')->postJson("/api/v1/admin/sellers/{$seller->id}/bank-change/approve")->assertOk();

        $kyc = $seller->fresh()->kyc;
        $this->assertSame('999988887777', $kyc->bank_account_number);
        $this->assertSame('SBIN0000001', $kyc->bank_ifsc);
        $this->assertNull($kyc->pending_bank_at);
        $this->as($seller)->postJson('/api/v1/seller/payout-requests', [])->assertCreated();
    }

    public function test_a_declined_bank_change_leaves_the_account_alone_and_bad_details_are_refused(): void
    {
        $seller = $this->seller();

        $this->as($seller)->postJson('/api/v1/seller/bank', ['bank_account_holder' => 'X', 'bank_account_number' => '12', 'bank_ifsc' => 'nope'])
            ->assertStatus(422)->assertJsonValidationErrors(['bank_account_number', 'bank_ifsc']);

        $this->as($seller)->postJson('/api/v1/seller/bank', [
            'bank_account_holder' => 'A Seller', 'bank_account_number' => '999988887777', 'bank_ifsc' => 'SBIN0000001',
        ])->assertStatus(202);
        $this->actingAs($this->admin(), 'sanctum')->postJson("/api/v1/admin/sellers/{$seller->id}/bank-change/reject", ['reason' => 'Could not verify'])->assertOk();

        $this->assertSame('123456789012', $seller->fresh()->kyc->bank_account_number);
        $this->assertNull($seller->fresh()->kyc->pending_bank_at);
    }

    public function test_only_a_verified_seller_may_change_bank_details_this_way(): void
    {
        $seller = $this->seller(withBank: false);

        $this->as($seller)->postJson('/api/v1/seller/bank', [
            'bank_account_holder' => 'A', 'bank_account_number' => '999988887777', 'bank_ifsc' => 'SBIN0000001',
        ])->assertStatus(422);
    }

    // ── Statements ───────────────────────────────────────────────────────

    public function test_a_monthly_statement_adds_up_from_the_ledger(): void
    {
        config(['marketplace.commission_gst_percent' => 18]);
        $seller = $this->seller();
        $order = $this->buyOne($seller);
        $this->fund($seller, 100);
        $month = now(config('marketplace.timezone'))->format('Y-m');

        $s = $this->as($seller)->getJson("/api/v1/seller/statements/{$month}")->assertOk()->json('data');

        $this->assertSame(1, $s['orders']);
        $this->assertEquals(1000, $s['gross_sales']);
        $this->assertEquals(100, $s['commission']);
        $this->assertEquals(18, $s['gst_on_commission']);
        $this->assertEquals(882, $s['earnings']);
        $this->assertEquals(100, $s['adjustments']);
        $this->assertEquals(0, $s['opening_balance']);
        $this->assertEquals(982, $s['closing_balance']);
        $this->assertCount(2, $s['rows']);

        $this->assertContains($month, $this->as($seller)->getJson('/api/v1/seller/statements')->json('data'));
        $this->as($seller)->getJson('/api/v1/seller/statements/not-a-month')->assertStatus(422);

        $csv = $this->as($seller)->get("/api/v1/seller/statements/{$month}/csv")->assertOk();
        $this->assertStringContainsString('Gross sales', $csv->getContent());
        $this->assertStringContainsString($order->order_number, $csv->getContent());
    }

    public function test_a_past_months_statement_opens_with_the_balance_carried_in(): void
    {
        $seller = $this->seller();
        $this->fund($seller, 400);
        SellerLedgerEntry::where('seller_id', $seller->id)->update(['created_at' => now()->subMonths(2)]);
        $this->fund($seller, 100);

        $month = now(config('marketplace.timezone'))->format('Y-m');
        $s = $this->as($seller)->getJson("/api/v1/seller/statements/{$month}")->json('data');

        $this->assertEquals(400, $s['opening_balance']);
        $this->assertEquals(500, $s['closing_balance']);
    }

    public function test_statements_and_money_are_private_to_each_seller_and_staff_can_read_any(): void
    {
        $one = $this->seller();
        $two = $this->seller();
        $this->fund($one, 700);
        $month = now(config('marketplace.timezone'))->format('Y-m');

        $this->assertEquals(0, $this->as($two)->getJson("/api/v1/seller/statements/{$month}")->json('data.adjustments'));
        $this->as($two)->deleteJson('/api/v1/seller/payout-requests/'.PayoutRequest::create(['seller_id' => $one->id, 'amount' => 100])->id)->assertNotFound();

        $admin = $this->actingAs($this->admin(), 'sanctum');
        $this->assertEquals(700, $admin->getJson("/api/v1/admin/sellers/{$one->id}/statements/{$month}")->assertOk()->json('data.adjustments'));
        $this->actingAs($this->admin(), 'sanctum')->get("/api/v1/admin/sellers/{$one->id}/statements/{$month}/csv")->assertOk();
        $this->actingAs(User::factory()->create(['role' => 'CUSTOMER', 'status' => 'ACTIVE']), 'sanctum')
            ->getJson("/api/v1/admin/payout-requests")->assertForbidden();
    }
}
