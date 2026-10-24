<?php

namespace Tests\Feature;

use App\Models\Category;
use App\Models\Order;
use App\Models\Product;
use App\Models\ProductVariant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Custom selection options: a category template, per-product edits, and a price
 * the server - never the client - decides.
 */
class ProductOptionsTest extends TestCase
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

    private function admin(): User
    {
        return User::factory()->create(['role' => User::ROLE_ADMIN, 'status' => 'ACTIVE']);
    }

    private function customer(): User
    {
        return User::factory()->create(['role' => 'CUSTOMER', 'status' => 'ACTIVE']);
    }

    /** A pizza-style template: Half/Full sets the price, add-ons add to it, exclusions are free. */
    private function foodTemplate(): array
    {
        return [
            [
                'label' => 'Portion', 'type' => 'single', 'required' => true, 'price_mode' => 'set',
                'choices' => [
                    ['label' => 'Half plate', 'price' => 180, 'default' => true],
                    ['label' => 'Full plate', 'price' => 320],
                ],
            ],
            [
                'label' => 'Add-ons', 'type' => 'multi', 'max' => 2,
                'choices' => [
                    ['label' => 'Extra cheese', 'price' => 30],
                    ['label' => 'Egg', 'price' => 20],
                    ['label' => 'Paneer', 'price' => 50],
                ],
            ],
            [
                'label' => 'Leave out', 'type' => 'multi', 'remove' => true,
                'choices' => [['label' => 'Onion', 'price' => 99], ['label' => 'Garlic']],
            ],
        ];
    }

    private function food(array $template = null, int $stock = 10): Product
    {
        $category = Category::factory()->create([
            'option_groups' => \App\Services\Options\ProductOptions::normalize($template ?? $this->foodTemplate()),
        ]);
        $product = Product::factory()->pricedAt(180)->create(['category_id' => $category->id]);
        ProductVariant::factory()->withStock($stock)->create(['product_id' => $product->id]);

        return $product->fresh(['variants', 'category']);
    }

    private function line(Product $product, array $options = [], int $qty = 1): array
    {
        return [
            'product_id' => $product->id,
            'variant_id' => $product->variants->first()->id,
            'quantity' => $qty,
            'options' => $options,
        ];
    }

    private function price(array $lines): \Illuminate\Testing\TestResponse
    {
        return $this->postJson('/api/v1/cart/price', ['items' => $lines]);
    }

    private function cod(User $user, array $lines): \Illuminate\Testing\TestResponse
    {
        return $this->actingAs($user, 'sanctum')->postJson('/api/v1/orders/checkout', [
            'items' => $lines,
            'shipping_address' => self::ADDRESS,
            'payment_method' => 'COD',
        ]);
    }

    // ── Templates ─────────────────────────────────────────────────────────

    public function test_an_admin_saves_a_template_and_it_comes_back_in_canonical_form(): void
    {
        $category = Category::factory()->create();

        $this->actingAs($this->admin(), 'sanctum')
            ->putJson("/api/v1/categories/{$category->id}", ['option_groups' => $this->foodTemplate()])
            ->assertOk()
            ->assertJsonPath('data.option_groups.0.key', 'portion')
            ->assertJsonPath('data.option_groups.0.choices.1.id', 'full_plate')
            ->assertJsonPath('data.option_groups.1.max', 2)
            ->assertJsonPath('data.option_groups.2.choices.0.price', 0);   // "leave out" is always free
    }

    public function test_a_product_inherits_its_categorys_template(): void
    {
        $product = $this->food();

        $this->getJson("/api/v1/products/{$product->id}")
            ->assertOk()
            ->assertJsonCount(3, 'data.option_groups')
            ->assertJsonPath('data.option_groups.0.label', 'Portion');
    }

    public function test_a_product_can_carry_its_own_list_instead(): void
    {
        $product = $this->food();

        $this->actingAs($this->admin(), 'sanctum')
            ->putJson("/api/v1/products/{$product->id}", ['custom_options' => [
                ['label' => 'Spice', 'type' => 'single', 'choices' => [['label' => 'Mild'], ['label' => 'Hot']]],
            ]])
            ->assertOk();

        $this->getJson("/api/v1/products/{$product->id}")
            ->assertJsonCount(1, 'data.option_groups')
            ->assertJsonPath('data.option_groups.0.key', 'spice');
    }

    public function test_an_empty_own_list_means_no_options_at_all(): void
    {
        $product = $this->food();

        $this->actingAs($this->admin(), 'sanctum')
            ->putJson("/api/v1/products/{$product->id}", ['custom_options' => []])
            ->assertOk();

        $this->getJson("/api/v1/products/{$product->id}")->assertJsonCount(0, 'data.option_groups');
        $this->price([$this->line($product)])->assertOk();
    }

    public function test_only_one_group_may_set_the_price(): void
    {
        $category = Category::factory()->create();
        $set = fn (string $label) => [
            'label' => $label, 'price_mode' => 'set', 'choices' => [['label' => 'A', 'price' => 10]],
        ];

        $this->actingAs($this->admin(), 'sanctum')
            ->putJson("/api/v1/categories/{$category->id}", ['option_groups' => [$set('One'), $set('Two')]])
            ->assertStatus(422);
    }

    public function test_a_group_needs_a_name_and_choices(): void
    {
        $category = Category::factory()->create();
        $admin = $this->actingAs($this->admin(), 'sanctum');

        $admin->putJson("/api/v1/categories/{$category->id}", ['option_groups' => [['type' => 'single', 'choices' => [['label' => 'A']]]]])
            ->assertStatus(422);
        $admin->putJson("/api/v1/categories/{$category->id}", ['option_groups' => [['label' => 'Size', 'type' => 'single', 'choices' => []]]])
            ->assertStatus(422);
    }

    public function test_customers_cannot_edit_templates(): void
    {
        $category = Category::factory()->create();

        $this->actingAs($this->customer(), 'sanctum')
            ->putJson("/api/v1/categories/{$category->id}", ['option_groups' => $this->foodTemplate()])
            ->assertForbidden();
    }

    // ── Pricing ───────────────────────────────────────────────────────────

    public function test_a_set_price_option_replaces_the_base_price(): void
    {
        $product = $this->food();

        $this->price([$this->line($product, ['portion' => ['full_plate']])])
            ->assertOk()
            ->assertJsonPath('data.items.0.unit_price', 320);
    }

    public function test_add_ons_add_to_it_and_exclusions_are_free(): void
    {
        $product = $this->food();

        $this->price([$this->line($product, [
            'portion' => ['half_plate'],
            'add_ons' => ['extra_cheese', 'egg'],
            'leave_out' => ['onion'],
        ])])
            ->assertOk()
            ->assertJsonPath('data.items.0.unit_price', 230)       // 180 + 30 + 20
            ->assertJsonPath('data.items.0.options.2.choices.0.label', 'Onion');
    }

    public function test_a_stepper_multiplies_the_per_unit_price(): void
    {
        $product = $this->food([[
            'label' => 'Weight', 'type' => 'stepper', 'required' => true,
            'stepper' => ['min' => 0.5, 'max' => 5, 'step' => 0.5, 'unit' => 'kg'],
        ]]);
        $product->variants->first()->update(['price' => 60]);

        $this->price([$this->line($product->fresh('variants'), ['weight' => 1.5])])
            ->assertOk()
            ->assertJsonPath('data.items.0.unit_price', 90);
    }

    public function test_a_stepper_value_off_the_grid_is_refused(): void
    {
        $product = $this->food([[
            'label' => 'Weight', 'type' => 'stepper',
            'stepper' => ['min' => 0.5, 'max' => 5, 'step' => 0.5, 'unit' => 'kg'],
        ]]);

        $this->price([$this->line($product, ['weight' => 0.75])])
            ->assertOk()
            ->assertJsonPath('data.items.0.available', false);
    }

    public function test_the_discount_travels_with_a_dearer_option(): void
    {
        $category = Category::factory()->create(['option_groups' => \App\Services\Options\ProductOptions::normalize($this->foodTemplate())]);
        $product = Product::factory()->pricedAt(180, 240)->create(['category_id' => $category->id]);
        ProductVariant::factory()->withStock(5)->create(['product_id' => $product->id]);
        $product = $product->fresh(['variants', 'category']);

        $this->price([$this->line($product, ['portion' => ['full_plate']])])
            ->assertJsonPath('data.items.0.unit_price', 320)
            ->assertJsonPath('data.items.0.unit_mrp', 426.67);   // 240 x 320/180
    }

    // ── What the server refuses ───────────────────────────────────────────

    public function test_a_required_choice_left_out_blocks_checkout(): void
    {
        $product = $this->food();

        $this->cod($this->customer(), [$this->line($product)])
            ->assertStatus(422)
            ->assertJsonPath('errors.items.0', 'Choose Portion for '.$product->title.'.');

        $this->assertSame(0, Order::count());
    }

    public function test_too_many_picks_are_refused(): void
    {
        $product = $this->food();

        $this->cod($this->customer(), [$this->line($product, [
            'portion' => ['half_plate'],
            'add_ons' => ['extra_cheese', 'egg', 'paneer'],
        ])])->assertStatus(422);
    }

    public function test_two_picks_in_a_single_choice_group_are_refused(): void
    {
        $product = $this->food();

        $this->cod($this->customer(), [$this->line($product, ['portion' => ['half_plate', 'full_plate']])])
            ->assertStatus(422);
    }

    public function test_an_invented_choice_or_group_buys_nothing(): void
    {
        $product = $this->food();

        $this->cod($this->customer(), [$this->line($product, ['portion' => ['family_pack']])])->assertStatus(422);
        $this->cod($this->customer(), [$this->line($product, ['portion' => ['half_plate'], 'discount' => ['100']])])->assertStatus(422);
        $this->assertSame(0, Order::count());
    }

    public function test_the_client_cannot_name_its_own_price(): void
    {
        $product = $this->food();
        $user = $this->customer();

        $line = $this->line($product, ['portion' => ['full_plate']]) + ['price' => 1, 'unit_price' => 1];

        $this->cod($user, [$line])->assertCreated();

        $this->assertEquals(320, Order::first()->items->first()->price);
    }

    public function test_an_unavailable_choice_is_refused(): void
    {
        $template = $this->foodTemplate();
        $template[1]['choices'][1]['available'] = false;   // Egg is off today
        $product = $this->food($template);

        $this->cod($this->customer(), [$this->line($product, ['portion' => ['half_plate'], 'add_ons' => ['egg']])])
            ->assertStatus(422);
    }

    // ── Orders ────────────────────────────────────────────────────────────

    public function test_the_order_remembers_what_was_picked(): void
    {
        $product = $this->food();

        $this->cod($this->customer(), [$this->line($product, [
            'portion' => ['full_plate'],
            'leave_out' => ['onion', 'garlic'],
        ])])->assertCreated();

        $item = Order::first()->items->first();
        $this->assertEquals(320, $item->price);
        $this->assertSame('Full plate', $item->selected_options[0]['choices'][0]['label']);
        $this->assertSame(['Garlic', 'Onion'], array_column($item->selected_options[1]['choices'], 'label'));
    }

    public function test_the_same_dish_with_different_picks_is_separate_lines_sharing_one_stock(): void
    {
        $product = $this->food(null, 3);

        $this->cod($this->customer(), [
            $this->line($product, ['portion' => ['half_plate']], 2),
            $this->line($product, ['portion' => ['full_plate']], 1),
        ])->assertCreated();

        $order = Order::first();
        $this->assertCount(2, $order->items);
        $this->assertSame(0, $product->variants->first()->fresh()->stock);
    }

    public function test_lines_with_the_same_picks_merge(): void
    {
        $product = $this->food();

        $this->cod($this->customer(), [
            $this->line($product, ['portion' => ['half_plate'], 'add_ons' => ['egg', 'extra_cheese']], 1),
            $this->line($product, ['portion' => ['half_plate'], 'add_ons' => ['extra_cheese', 'egg']], 2),
        ])->assertCreated();

        $this->assertCount(1, Order::first()->items);
        $this->assertSame(3, Order::first()->items->first()->quantity);
    }

    public function test_split_lines_cannot_dodge_the_stock_check(): void
    {
        $product = $this->food(null, 2);

        $this->cod($this->customer(), [
            $this->line($product, ['portion' => ['half_plate']], 2),
            $this->line($product, ['portion' => ['full_plate']], 1),
        ])->assertStatus(422);

        $this->assertSame(2, $product->variants->first()->fresh()->stock);
    }

    // ── Choice stock ──────────────────────────────────────────────────────

    private function productWithLimitedChoice(int $stock): Product
    {
        $product = $this->food([]);
        $this->actingAs($this->admin(), 'sanctum')
            ->putJson("/api/v1/products/{$product->id}", ['custom_options' => [[
                'label' => 'Flavour', 'type' => 'single', 'required' => true,
                'choices' => [['label' => 'Mango', 'stock' => $stock], ['label' => 'Plain']],
            ]]])->assertOk();

        return $product->fresh(['variants', 'category']);
    }

    public function test_a_choice_with_its_own_stock_counts_down_and_sells_out(): void
    {
        $product = $this->productWithLimitedChoice(2);
        $user = $this->customer();

        $this->cod($user, [$this->line($product, ['flavour' => ['mango']], 2)])->assertCreated();
        $this->assertSame(0, $product->fresh()->custom_options[0]['choices'][0]['stock']);

        $this->cod($user, [$this->line($product, ['flavour' => ['mango']], 1)])->assertStatus(422);
        $this->cod($user, [$this->line($product, ['flavour' => ['plain']], 1)])->assertCreated();
    }

    public function test_cancelling_returns_the_choice_to_stock(): void
    {
        $product = $this->productWithLimitedChoice(2);
        $user = $this->customer();

        $this->cod($user, [$this->line($product, ['flavour' => ['mango']], 2)])->assertCreated();
        $order = Order::first();

        $this->actingAs($user, 'sanctum')
            ->postJson("/api/v1/orders/{$order->id}/cancel", ['reason' => 'Changed my mind'])
            ->assertOk();

        $this->assertSame(2, $product->fresh()->custom_options[0]['choices'][0]['stock']);
    }

    public function test_a_templates_choices_never_carry_stock(): void
    {
        $template = $this->foodTemplate();
        $template[1]['choices'][0]['stock'] = 1;
        $category = Category::factory()->create();

        $this->actingAs($this->admin(), 'sanctum')
            ->putJson("/api/v1/categories/{$category->id}", ['option_groups' => $template])
            ->assertOk()
            ->assertJsonPath('data.option_groups.1.choices.0.stock', null);
    }

    public function test_a_payment_intent_is_tied_to_the_exact_picks(): void
    {
        $product = $this->food([[
            'label' => 'Flavour', 'type' => 'single', 'required' => true,
            'choices' => [['label' => 'Mango'], ['label' => 'Plain']],
        ]]);
        $user = $this->customer();

        $intent = $this->actingAs($user, 'sanctum')->postJson('/api/v1/payments/intent', [
            'items' => [$this->line($product, ['flavour' => ['mango']])],
            'pincode' => self::ADDRESS['pincode'],
            'payment_method' => 'UPI',
        ])->assertCreated()->json('data');

        $spend = fn (string $flavour) => $this->actingAs($user, 'sanctum')->postJson('/api/v1/orders/checkout', [
            'items' => [$this->line($product, ['flavour' => [$flavour]])],
            'shipping_address' => self::ADDRESS,
            'payment_method' => 'UPI',
            'payment_intent_id' => $intent['payment_intent_id'],
        ]);

        // Same total, different dish: the quote doesn't cover it.
        $spend('plain')->assertStatus(422);
        $this->assertSame(0, Order::count());

        $spend('mango')->assertCreated();
    }

    // ── Swatches on variants ──────────────────────────────────────────────

    public function test_a_variant_can_carry_a_swatch_colour(): void
    {
        $product = Product::factory()->create();

        $this->actingAs($this->admin(), 'sanctum')
            ->putJson("/api/v1/products/{$product->id}", ['variants' => [
                ['color' => 'Navy', 'color_hex' => '#1F3A93', 'size' => 'M', 'stock' => 4],
            ]])
            ->assertOk()
            ->assertJsonPath('data.variants.0.color_hex', '#1F3A93');

        $this->actingAs($this->admin(), 'sanctum')
            ->putJson("/api/v1/products/{$product->id}", ['variants' => [
                ['color' => 'Navy', 'color_hex' => 'blue', 'size' => 'M', 'stock' => 4],
            ]])
            ->assertStatus(422);
    }
}
