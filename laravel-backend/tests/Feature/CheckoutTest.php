<?php

namespace Tests\Feature;

use App\Models\Order;
use App\Models\PaymentIntent;
use App\Models\Product;
use App\Models\ProductVariant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Checkout is where every other bug in this codebase eventually costs money, so
 * these tests are written adversarially: most of them describe a request a
 * hostile client would send, and assert the server refuses it *and* leaves
 * nothing behind.
 */
class CheckoutTest extends TestCase
{
    use RefreshDatabase;

    private const ADDRESS = [
        'name' => 'Priya Sharma',
        'phone' => '9876543210',
        'line1' => '221B Indiranagar',
        'city' => 'Bengaluru',
        'state' => 'Karnataka',
        'pincode' => '560038',
    ];

    private function customer(): User
    {
        return User::factory()->create(['role' => 'CUSTOMER', 'status' => 'ACTIVE']);
    }

    /** A sellable product at a known price. */
    private function product(float $price = 1000, int $stock = 10): Product
    {
        $product = Product::factory()->pricedAt($price)->create();
        ProductVariant::factory()->withStock($stock)->create(['product_id' => $product->id]);

        return $product->fresh('variants');
    }

    private function lineFor(Product $product, int $qty = 1): array
    {
        return [
            'product_id' => $product->id,
            'variant_id' => $product->variants->first()->id,
            'quantity' => $qty,
        ];
    }

    /** Walks the real quote endpoint, as the storefront does. */
    private function intentFor(User $user, array $items): array
    {
        return $this->actingAs($user, 'sanctum')
            ->postJson('/api/v1/payments/intent', [
                'items' => $items,
                'pincode' => self::ADDRESS['pincode'],
                'payment_method' => 'UPI',
            ])
            ->assertCreated()
            ->json('data');
    }

    private function checkout(User $user, array $body): \Illuminate\Testing\TestResponse
    {
        return $this->actingAs($user, 'sanctum')->postJson('/api/v1/orders/checkout', array_merge([
            'shipping_address' => self::ADDRESS,
            'payment_method' => 'UPI',
        ], $body));
    }

    // ── The payment gate ────────────────────────────────────────────────

    public function test_prepaid_checkout_is_refused_without_a_payment_intent(): void
    {
        $user = $this->customer();
        $product = $this->product();

        $this->checkout($user, ['items' => [$this->lineFor($product)]])
            ->assertStatus(422)
            ->assertJsonValidationErrors('payment_intent_id');

        $this->assertSame(0, Order::count());
    }

    public function test_a_client_invented_transaction_id_buys_nothing(): void
    {
        $user = $this->customer();
        $product = $this->product();

        // Exactly what the old storefront sent: a made-up UPI reference.
        $this->checkout($user, [
            'items' => [$this->lineFor($product)],
            'transaction_id' => 'UPI-'.random_int(1000000000, 9999999999),
        ])->assertStatus(422);

        $this->assertSame(0, Order::count());
    }

    public function test_an_unknown_payment_intent_is_refused(): void
    {
        $user = $this->customer();
        $product = $this->product();

        $this->checkout($user, [
            'items' => [$this->lineFor($product)],
            'payment_intent_id' => '11111111-1111-1111-1111-111111111111',
        ])->assertStatus(422);

        $this->assertSame(0, Order::count());
    }

    public function test_an_intent_belonging_to_another_user_is_refused(): void
    {
        $product = $this->product();
        $items = [$this->lineFor($product)];

        $victim = $this->customer();
        $attacker = $this->customer();

        $intent = $this->intentFor($victim, $items);

        $this->checkout($attacker, [
            'items' => $items,
            'payment_intent_id' => $intent['payment_intent_id'],
        ])->assertStatus(422);

        $this->assertSame(0, Order::count());
        $this->assertSame('CREATED', PaymentIntent::first()->status);
    }

    public function test_changing_the_cart_after_quoting_invalidates_the_intent(): void
    {
        $user = $this->customer();
        $product = $this->product(price: 1000, stock: 10);

        // Quote for one unit, then try to check out three against it.
        $intent = $this->intentFor($user, [$this->lineFor($product, 1)]);

        $this->checkout($user, [
            'items' => [$this->lineFor($product, 3)],
            'payment_intent_id' => $intent['payment_intent_id'],
        ])->assertStatus(422);

        $this->assertSame(0, Order::count());
        $this->assertSame(10, $product->variants->first()->fresh()->stock);
    }

    public function test_a_payment_intent_cannot_be_spent_twice(): void
    {
        $user = $this->customer();
        $product = $this->product(stock: 10);
        $items = [$this->lineFor($product)];

        $intent = $this->intentFor($user, $items);
        $body = ['items' => $items, 'payment_intent_id' => $intent['payment_intent_id']];

        $this->checkout($user, $body)->assertCreated();
        $this->checkout($user, $body)->assertStatus(422);

        $this->assertSame(1, Order::count());
    }

    public function test_an_expired_intent_is_refused(): void
    {
        $user = $this->customer();
        $product = $this->product();
        $items = [$this->lineFor($product)];

        $intent = $this->intentFor($user, $items);
        PaymentIntent::whereKey($intent['payment_intent_id'])
            ->update(['expires_at' => now()->subMinute()]);

        $this->checkout($user, ['items' => $items, 'payment_intent_id' => $intent['payment_intent_id']])
            ->assertStatus(422);

        $this->assertSame(0, Order::count());
    }

    // ── The happy path ──────────────────────────────────────────────────

    public function test_a_verified_prepaid_order_is_placed_and_priced_from_the_database(): void
    {
        $user = $this->customer();
        $product = $this->product(price: 1499, stock: 10);
        $items = [$this->lineFor($product, 2)];

        $intent = $this->intentFor($user, $items);

        $response = $this->checkout($user, [
            'items' => $items,
            'payment_intent_id' => $intent['payment_intent_id'],
        ])->assertCreated();

        $order = Order::with('items')->first();

        $this->assertSame('PAID', $order->payment_status);
        $this->assertSame('CONFIRMED', $order->status);
        // Priced from the product row, not from anything the client sent.
        $this->assertEquals(2998.0, (float) $order->subtotal);
        $this->assertEquals(
            (float) $order->subtotal - (float) $order->discount + (float) $order->shipping_charge,
            (float) $order->total_amount,
        );
        // The gateway names the transaction now, not the browser.
        $this->assertStringStartsWith('pay_mock_', $order->transaction_id);

        $this->assertSame(8, $product->variants->first()->fresh()->stock);
        $this->assertSame('CONSUMED', PaymentIntent::first()->status);
        $this->assertSame($order->id, PaymentIntent::first()->order_id);

        $response->assertJsonPath('data.order_number', $order->order_number);
    }

    public function test_cod_does_not_require_a_payment_intent_and_stays_unpaid(): void
    {
        $user = $this->customer();
        $product = $this->product();

        $this->checkout($user, [
            'items' => [$this->lineFor($product)],
            'payment_method' => 'COD',
        ])->assertCreated();

        $order = Order::first();
        $this->assertSame('COD', $order->payment_method);
        $this->assertSame('PENDING', $order->payment_status);
        $this->assertNull($order->transaction_id);
    }

    // ── Cart integrity ──────────────────────────────────────────────────

    public function test_delivery_instructions_travel_with_the_address(): void
    {
        $user = $this->customer();
        $product = $this->product();

        $response = $this->actingAs($user, 'sanctum')->postJson('/api/v1/orders/checkout', [
            'items' => [$this->lineFor($product)],
            'shipping_address' => self::ADDRESS + ['instructions' => 'Leave at the door, do not ring'],
            'payment_method' => 'COD',
        ])->assertCreated();

        $order = Order::findOrFail($response->json('data.id'));
        $this->assertSame('Leave at the door, do not ring', $order->shipping_address['instructions']);
    }

    public function test_delivery_instructions_are_optional_and_length_limited(): void
    {
        $user = $this->customer();
        $product = $this->product();

        $this->actingAs($user, 'sanctum')->postJson('/api/v1/orders/checkout', [
            'items' => [$this->lineFor($product)],
            'shipping_address' => self::ADDRESS + ['instructions' => str_repeat('x', 201)],
            'payment_method' => 'COD',
        ])->assertStatus(422);
    }

    public function test_a_variant_from_a_different_product_is_refused(): void
    {
        $user = $this->customer();
        $dear = $this->product(price: 7499);
        $cheap = $this->product(price: 199);

        // The substitution: expensive product id, cheap product's variant id.
        $this->actingAs($user, 'sanctum')->postJson('/api/v1/payments/intent', [
            'items' => [[
                'product_id' => $dear->id,
                'variant_id' => $cheap->variants->first()->id,
                'quantity' => 1,
            ]],
            'pincode' => self::ADDRESS['pincode'],
            'payment_method' => 'UPI',
        ])->assertStatus(422);

        $this->assertSame(0, Order::count());
    }

    public function test_quantity_is_capped_per_line(): void
    {
        $user = $this->customer();
        $product = $this->product(stock: 100000);

        $this->checkout($user, [
            'items' => [$this->lineFor($product, 9999)],
            'payment_method' => 'COD',
        ])->assertStatus(422);

        $this->assertSame(0, Order::count());
    }

    public function test_the_quantity_cap_cannot_be_split_across_duplicate_lines(): void
    {
        $user = $this->customer();
        $product = $this->product(stock: 100000);
        $line = $this->lineFor($product, 15);

        // 15 + 15 is over the per-line cap of 20 once the lines are merged.
        $this->checkout($user, [
            'items' => [$line, $line],
            'payment_method' => 'COD',
        ])->assertStatus(422);

        $this->assertSame(0, Order::count());
    }

    public function test_a_draft_product_cannot_be_bought(): void
    {
        $user = $this->customer();
        $product = $this->product();
        $product->update(['status' => 'DRAFT']);

        $this->checkout($user, [
            'items' => [$this->lineFor($product)],
            'payment_method' => 'COD',
        ])->assertStatus(422);

        $this->assertSame(0, Order::count());
    }

    public function test_checkout_is_refused_when_stock_is_short_and_nothing_is_decremented(): void
    {
        $user = $this->customer();
        $product = $this->product(stock: 2);

        $this->checkout($user, [
            'items' => [$this->lineFor($product, 5)],
            'payment_method' => 'COD',
        ])->assertStatus(422);

        $this->assertSame(0, Order::count());
        $this->assertSame(2, $product->variants->first()->fresh()->stock);
    }

    public function test_cod_is_refused_for_a_product_that_does_not_offer_it(): void
    {
        $user = $this->customer();
        $product = Product::factory()->pricedAt(500)->codUnavailable()->create();
        ProductVariant::factory()->withStock(5)->create(['product_id' => $product->id]);

        $this->checkout($user, [
            'items' => [[
                'product_id' => $product->id,
                'variant_id' => $product->variants()->first()->id,
                'quantity' => 1,
            ]],
            'payment_method' => 'COD',
        ])->assertStatus(422);

        $this->assertSame(0, Order::count());
    }

    public function test_checkout_requires_authentication(): void
    {
        $product = $this->product();

        $this->postJson('/api/v1/orders/checkout', [
            'items' => [$this->lineFor($product)],
            'shipping_address' => self::ADDRESS,
            'payment_method' => 'COD',
        ])->assertUnauthorized();
    }
}
