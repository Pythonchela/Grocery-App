<?php

namespace Tests\Feature;

use App\Models\Category;
use App\Models\Product;
use App\Models\ProductVariant;
use App\Models\Review;
use App\Models\Seller;
use App\Models\User;
use App\Services\Pricing\CartPricingService;
use App\Support\StoreMode;
use Carbon\CarbonImmutable;
use Database\Factories\SellerFactory;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Validation\ValidationException;
use Tests\TestCase;

/**
 * Shop-first selling: the three kinds of store (single business, vendors plus
 * the owner, vendors only), one shop per basket, and what a shop asks of an
 * order (hours, minimum, delivery area).
 */
class ShopModelTest extends TestCase
{
    use RefreshDatabase;

    private function shop(array $attributes = []): Seller
    {
        return Seller::factory()->create($attributes);
    }

    private function product(Seller $seller, float $price = 100, ?Category $category = null): Product
    {
        $product = Product::factory()->pricedAt($price)->soldBy($seller)->create(
            $category ? ['category_id' => $category->id] : []
        );
        ProductVariant::factory()->withStock(50)->create(['product_id' => $product->id]);

        return $product->fresh('variants');
    }

    private function line(Product $p, int $qty = 1): array
    {
        return ['product_id' => $p->id, 'variant_id' => $p->variants->first()->id, 'quantity' => $qty];
    }

    private function price(array $items, array $options = []): void
    {
        app(CartPricingService::class)->price($items, User::factory()->create(), $options);
    }

    private function mode(string $mode): void
    {
        config(['marketplace.mode' => $mode]);
    }

    // ── The three kinds of store ─────────────────────────────────────────

    public function test_the_public_config_tells_the_apps_what_kind_of_store_this_is(): void
    {
        $this->mode('multi');
        config(['marketplace.cart_rule' => 'one_shop']);

        $this->getJson('/api/v1/config')->assertOk()
            ->assertJsonPath('data.mode', 'multi')
            ->assertJsonPath('data.vendors_enabled', true)
            ->assertJsonPath('data.house_visible', false)
            ->assertJsonPath('data.shops_first', true)
            ->assertJsonPath('data.shows_shops', true)
            ->assertJsonPath('data.one_shop_per_cart', true);
    }

    public function test_a_single_business_store_has_no_shops_and_no_basket_rule(): void
    {
        $this->mode('single');

        $this->getJson('/api/v1/config')
            ->assertJsonPath('data.vendors_enabled', false)
            ->assertJsonPath('data.house_visible', true)
            ->assertJsonPath('data.shows_shops', false)
            ->assertJsonPath('data.one_shop_per_cart', false);
    }

    // One request per test: the config endpoint's answer is fixed once a test has asked it.

    public function test_a_vendors_only_store_can_list_products_directly(): void
    {
        $this->mode('multi');
        config(['marketplace.home_layout' => 'products']);

        $this->getJson('/api/v1/config')->assertOk()
            ->assertJsonPath('data.vendors_enabled', true)
            ->assertJsonPath('data.shops_first', false)
            ->assertJsonPath('data.home_shows_shops', false)
            // Shops are still there to browse; only the home stops leading with them.
            ->assertJsonPath('data.shows_shops', true);
    }

    public function test_a_mixed_store_can_list_products_directly(): void
    {
        $this->mode('hybrid');
        config(['marketplace.home_layout' => 'products']);

        $this->getJson('/api/v1/config')->assertOk()
            ->assertJsonPath('data.shops_first', false)
            ->assertJsonPath('data.home_shows_shops', false)
            ->assertJsonPath('data.shows_shops', true);
    }

    public function test_auto_keeps_a_vendors_only_store_opening_on_its_shops(): void
    {
        $this->mode('multi');
        config(['marketplace.home_layout' => 'auto']);

        $this->getJson('/api/v1/config')->assertJsonPath('data.shops_first', true)->assertJsonPath('data.home_shows_shops', true);
    }

    public function test_auto_keeps_a_mixed_store_as_products_with_a_row_of_shops(): void
    {
        $this->mode('hybrid');
        config(['marketplace.home_layout' => 'auto']);

        $this->getJson('/api/v1/config')->assertJsonPath('data.shops_first', false)->assertJsonPath('data.home_shows_shops', true);
    }

    public function test_a_store_can_open_on_its_shops(): void
    {
        $this->mode('hybrid');
        config(['marketplace.home_layout' => 'shops']);

        $this->getJson('/api/v1/config')->assertJsonPath('data.shops_first', true)->assertJsonPath('data.home_shows_shops', true);
    }

    public function test_a_single_business_store_never_shows_shops_whatever_the_layout(): void
    {
        $this->mode('single');
        config(['marketplace.home_layout' => 'shops']);

        $this->getJson('/api/v1/config')
            ->assertJsonPath('data.shops_first', false)
            ->assertJsonPath('data.home_shows_shops', false);
    }

    public function test_an_unknown_layout_means_auto(): void
    {
        config(['marketplace.home_layout' => 'nonsense']);

        $this->assertSame('auto', StoreMode::homeLayout());
    }

    public function test_an_unknown_mode_falls_back_to_hybrid(): void
    {
        $this->mode('nonsense');

        $this->assertSame('hybrid', StoreMode::mode());
    }

    public function test_a_single_business_store_refuses_vendor_applications(): void
    {
        $this->mode('single');
        $user = User::factory()->create(['role' => 'CUSTOMER', 'status' => 'ACTIVE']);

        $this->actingAs($user, 'sanctum')->postJson('/api/v1/sellers/apply', ['display_name' => 'Sharma Kirana'])
            ->assertForbidden();

        $this->assertDatabaseMissing('sellers', ['display_name' => 'Sharma Kirana']);
    }

    public function test_and_the_admin_cannot_add_a_vendor_either(): void
    {
        $this->mode('single');
        $admin = User::factory()->create(['role' => User::ROLE_ADMIN, 'status' => 'ACTIVE']);
        $vendor = User::factory()->create(['role' => User::ROLE_SELLER]);

        $this->actingAs($admin, 'sanctum')->postJson('/api/v1/admin/sellers', ['display_name' => 'X', 'user_id' => $vendor->id])
            ->assertForbidden();
    }

    public function test_vendors_may_apply_in_the_other_two_modes(): void
    {
        foreach (['hybrid', 'multi'] as $mode) {
            $this->mode($mode);
            $user = User::factory()->create(['role' => 'CUSTOMER', 'status' => 'ACTIVE']);

            $this->actingAs($user, 'sanctum')->postJson('/api/v1/sellers/apply', ['display_name' => "Shop {$mode}"])
                ->assertCreated();
        }
    }

    public function test_in_a_vendors_only_store_the_owners_own_shop_is_hidden(): void
    {
        $house = SellerFactory::house();
        $vendor = $this->shop(['display_name' => 'Sharma Kirana']);
        $own = $this->product($house);
        $theirs = $this->product($vendor);
        $this->mode('multi');

        $ids = collect($this->getJson('/api/v1/products?per_page=100')->json('data'))->pluck('id');
        $this->assertTrue($ids->contains($theirs->id));
        $this->assertFalse($ids->contains($own->id), 'the owner sells nothing here');

        $this->getJson("/api/v1/products/{$own->id}")->assertNotFound();
        $this->getJson("/api/v1/products/{$theirs->id}")->assertOk();
        $this->assertNotContains('house', collect($this->getJson('/api/v1/shops')->json('data'))->pluck('slug')->all());
    }

    public function test_in_the_other_modes_the_owners_shop_shows_normally(): void
    {
        $house = SellerFactory::house();
        $own = $this->product($house);

        foreach (['single', 'hybrid'] as $mode) {
            $this->mode($mode);

            $this->getJson("/api/v1/products/{$own->id}")->assertOk();
        }
    }

    public function test_a_basket_cannot_hold_the_hidden_owners_goods(): void
    {
        $house = SellerFactory::house();
        $own = $this->product($house);
        $this->mode('multi');

        $this->expectException(ValidationException::class);
        $this->price([$this->line($own)]);
    }

    // ── One shop per basket ──────────────────────────────────────────────

    public function test_with_the_one_shop_rule_a_basket_cannot_mix_shops(): void
    {
        config(['marketplace.cart_rule' => 'one_shop']);
        $a = $this->shop(['display_name' => 'Sharma Kirana']);
        $b = $this->shop(['display_name' => 'Fresh Mart']);

        try {
            $this->price([$this->line($this->product($a)), $this->line($this->product($b))]);
            $this->fail('two shops in one basket should be refused');
        } catch (ValidationException $e) {
            $message = $e->errors()['shops'][0];
            $this->assertStringContainsString('different shops', $message);
            $this->assertStringContainsString('one shop at a time', $message);
        }
    }

    public function test_one_shop_with_several_items_is_fine(): void
    {
        config(['marketplace.cart_rule' => 'one_shop']);
        $a = $this->shop();

        $this->price([$this->line($this->product($a)), $this->line($this->product($a), 3)]);

        $this->assertTrue(true, 'priced without complaint');
    }

    public function test_the_mixed_rule_allows_several_shops(): void
    {
        config(['marketplace.cart_rule' => 'mixed']);
        $a = $this->shop();
        $b = $this->shop();

        $this->price([$this->line($this->product($a)), $this->line($this->product($b))]);

        $this->assertTrue(true);
    }

    public function test_a_single_business_store_never_applies_the_basket_rule(): void
    {
        $this->mode('single');
        config(['marketplace.cart_rule' => 'one_shop']);

        $this->assertFalse(StoreMode::oneShopPerCart());
    }

    // ── Opening hours ────────────────────────────────────────────────────

    private function at(string $iso): CarbonImmutable
    {
        return CarbonImmutable::parse($iso, 'Asia/Kolkata');
    }

    public function test_a_shop_with_no_hours_is_always_open(): void
    {
        $this->assertTrue($this->shop()->isOpenNow($this->at('2026-10-14 03:00')));
    }

    public function test_hours_open_and_close_the_shop(): void
    {
        $hours = ['wed' => ['open' => '09:00', 'close' => '21:00']];
        $shop = $this->shop(['opening_hours' => $hours]);

        $this->assertTrue($shop->isOpenNow($this->at('2026-10-14 09:00')), 'opens on the dot');   // a Wednesday
        $this->assertTrue($shop->isOpenNow($this->at('2026-10-14 20:59')));
        $this->assertFalse($shop->isOpenNow($this->at('2026-10-14 21:00')), 'closed on the dot');
        $this->assertFalse($shop->isOpenNow($this->at('2026-10-14 08:59')));
        $this->assertFalse($shop->isOpenNow($this->at('2026-10-15 12:00')), 'no hours listed for Thursday, so closed');
    }

    public function test_a_late_night_shop_stays_open_past_midnight(): void
    {
        $shop = $this->shop(['opening_hours' => ['fri' => ['open' => '18:00', 'close' => '02:00']]]);

        $this->assertTrue($shop->isOpenNow($this->at('2026-10-16 23:00')), 'Friday night');
        $this->assertTrue($shop->isOpenNow($this->at('2026-10-17 01:30')), 'still Friday\'s shift, early Saturday');
        $this->assertFalse($shop->isOpenNow($this->at('2026-10-17 02:00')));
        $this->assertFalse($shop->isOpenNow($this->at('2026-10-16 17:59')));
    }

    public function test_pausing_orders_closes_the_shop_whatever_the_hours(): void
    {
        $shop = $this->shop(['accepting_orders' => false]);

        $this->assertFalse($shop->isOpenNow($this->at('2026-10-14 12:00')));
        $this->assertSame('Not taking orders right now', $shop->closedText($this->at('2026-10-14 12:00')));
    }

    public function test_a_closed_shop_says_when_it_next_opens(): void
    {
        $shop = $this->shop(['opening_hours' => [
            'wed' => ['open' => '09:00', 'close' => '21:00'],
            'thu' => ['open' => '10:00', 'close' => '20:00'],
            'sat' => ['open' => '11:00', 'close' => '18:00'],
        ]]);

        $this->assertSame('Opens today at 9:00 AM', $shop->closedText($this->at('2026-10-14 07:00')));
        $this->assertSame('Opens tomorrow at 10:00 AM', $shop->closedText($this->at('2026-10-14 22:00')));
        $this->assertSame('Opens Sat at 11:00 AM', $shop->closedText($this->at('2026-10-15 21:00')));
    }

    public function test_hours_are_stored_tidied(): void
    {
        $fields = Seller::cleanShopFields(['opening_hours' => [
            'mon' => ['open' => '09:00', 'close' => '21:00'],
            'tue' => ['open' => '09:00', 'close' => null],     // half a day: closed
            'wed' => ['open' => '10:00', 'close' => '10:00'],  // opens and closes together: closed
            'bogus' => ['open' => '09:00', 'close' => '21:00'],
        ]]);

        $this->assertSame(['open' => '09:00', 'close' => '21:00'], $fields['opening_hours']['mon']);
        $this->assertNull($fields['opening_hours']['tue']);
        $this->assertNull($fields['opening_hours']['wed']);
        $this->assertArrayNotHasKey('bogus', $fields['opening_hours']);
        $this->assertNull(Seller::cleanShopFields(['opening_hours' => []])['opening_hours'], 'no hours at all means always open');
    }

    // ── What a shop asks of an order ─────────────────────────────────────

    public function test_a_closed_shop_will_not_take_an_order_but_will_let_you_browse_and_build_a_basket(): void
    {
        $shop = $this->shop(['accepting_orders' => false, 'display_name' => 'Sharma Kirana']);
        $items = [$this->line($this->product($shop))];

        $this->price($items);   // building a basket: fine
        $this->assertTrue(true);

        try {
            $this->price($items, ['payment_method' => 'COD', 'pincode' => '560038']);
            $this->fail('ordering from a closed shop must be refused');
        } catch (ValidationException $e) {
            $this->assertStringContainsString('Sharma Kirana is closed right now', $e->errors()['shops'][0]);
        }
    }

    public function test_the_minimum_order_is_enforced_and_says_how_much_more_to_add(): void
    {
        $shop = $this->shop(['min_order_amount' => 300, 'display_name' => 'Fresh Mart']);
        $items = [$this->line($this->product($shop, 120), 2)];   // Rs 240

        try {
            $this->price($items, ['payment_method' => 'COD', 'pincode' => '560038']);
            $this->fail('below the minimum');
        } catch (ValidationException $e) {
            $this->assertSame('The minimum order for Fresh Mart is ₹300. Add ₹60 more.', $e->errors()['shops'][0]);
        }

        $this->price([$this->line($this->product($shop, 150), 2)], ['payment_method' => 'COD', 'pincode' => '560038']);   // Rs 300
        $this->assertTrue(true, 'exactly the minimum is enough');
    }

    public function test_a_shop_only_delivers_to_its_own_pincodes(): void
    {
        $shop = $this->shop(['service_pincodes' => ['560038', '560034'], 'display_name' => 'Fresh Mart']);
        $items = [$this->line($this->product($shop))];

        $this->price($items, ['payment_method' => 'COD', 'pincode' => '560034']);

        try {
            $this->price($items, ['payment_method' => 'COD', 'pincode' => '110001']);
            $this->fail('outside the area');
        } catch (ValidationException $e) {
            $this->assertSame('Fresh Mart does not deliver to 110001.', $e->errors()['shops'][0]);
        }
    }

    public function test_the_delivery_quote_says_so_when_the_shop_does_not_reach_the_address(): void
    {
        $shop = $this->shop(['service_pincodes' => ['560038'], 'display_name' => 'Fresh Mart']);
        $product = $this->product($shop);

        $this->postJson('/api/v1/delivery/quote', ['pincode' => '110001', 'items' => [['product_id' => $product->id, 'quantity' => 1]]])
            ->assertOk()
            ->assertJsonPath('data.serviceable', false)
            ->assertJsonPath('data.message', 'Fresh Mart does not deliver to 110001.')
            ->assertJsonPath('data.options', []);
    }

    public function test_a_shop_with_no_area_list_delivers_wherever_a_courier_can(): void
    {
        $this->assertTrue($this->shop()->servesPincode('110001'));
        $this->assertTrue($this->shop(['service_pincodes' => []])->servesPincode('110001'));
    }

    // ── The shop list ────────────────────────────────────────────────────

    public function test_the_shop_list_shows_active_shops_with_something_on_sale(): void
    {
        $open = $this->shop(['display_name' => 'Sharma Kirana', 'slug' => 'sharma-kirana', 'tagline' => 'Groceries since 1990', 'min_order_amount' => 99, 'prep_minutes' => 20]);
        $this->product($open);
        $empty = $this->shop(['display_name' => 'Empty Shop']);
        $suspended = $this->shop(['display_name' => 'Gone Shop', 'status' => 'SUSPENDED']);
        $this->product($suspended);

        $rows = collect($this->getJson('/api/v1/shops')->assertOk()->json('data'));

        $this->assertSame(['Sharma Kirana'], $rows->pluck('name')->all());
        $row = $rows->first();
        $this->assertSame('sharma-kirana', $row['slug']);
        $this->assertSame('Groceries since 1990', $row['tagline']);
        $this->assertEquals(99, $row['min_order_amount']);
        $this->assertSame(20, $row['prep_minutes']);
        $this->assertTrue($row['is_open']);
        $this->assertSame(1, $row['product_count']);
    }

    public function test_the_shop_list_never_leaks_private_fields(): void
    {
        $shop = $this->shop();
        $this->product($shop);

        $row = $this->getJson('/api/v1/shops')->json('data.0');

        foreach (['commission_rate', 'payout_balance', 'user_id', 'legal_name', 'support_email', 'pickup_line1', 'pickup_phone', 'status'] as $private) {
            $this->assertArrayNotHasKey($private, $row, "{$private} is not for shoppers");
        }
    }

    public function test_open_shops_come_first_then_the_best_rated(): void
    {
        $closed = $this->shop(['display_name' => 'AAA Closed', 'accepting_orders' => false]);
        $plain = $this->shop(['display_name' => 'BBB Plain']);
        $loved = $this->shop(['display_name' => 'CCC Loved']);
        foreach ([$closed, $plain, $loved] as $s) {
            $this->product($s);
        }
        $lovedProduct = Product::where('seller_id', $loved->id)->first();
        Review::create(['product_id' => $lovedProduct->id, 'user_id' => User::factory()->create()->id, 'rating' => 5, 'status' => 'APPROVED', 'verified_purchase' => true]);

        $names = collect($this->getJson('/api/v1/shops')->json('data'))->pluck('name')->all();

        $this->assertSame(['CCC Loved', 'BBB Plain', 'AAA Closed'], $names);
    }

    public function test_shops_can_be_filtered_by_search_pincode_category_and_open(): void
    {
        $dairy = Category::factory()->create(['name' => 'Dairy', 'slug' => 'dairy']);
        $a = $this->shop(['display_name' => 'Sharma Kirana', 'service_pincodes' => ['560038']]);
        $b = $this->shop(['display_name' => 'Fresh Mart', 'accepting_orders' => false]);
        $this->product($a);
        $this->product($b, 100, $dairy);

        $names = fn (string $query) => collect($this->getJson("/api/v1/shops?{$query}")->json('data'))->pluck('name')->sort()->values()->all();

        $this->assertSame(['Sharma Kirana'], $names('search=sharma'));
        $this->assertSame(['Fresh Mart'], $names('category=dairy'));
        $this->assertSame(['Fresh Mart'], $names('pincode=110001'), 'Sharma only serves 560038');
        $this->assertSame(['Fresh Mart', 'Sharma Kirana'], $names('pincode=560038'));
        $this->assertSame(['Sharma Kirana'], $names('open=1'));
    }

    public function test_the_category_filters_come_from_whatever_the_shops_sell(): void
    {
        // Nothing here is about food: a grocer, a clothing shop and a pharmacy.
        $groceries = Category::factory()->create(['name' => 'Groceries', 'slug' => 'groceries']);
        $clothing = Category::factory()->create(['name' => 'Clothing', 'slug' => 'clothing']);
        $medicine = Category::factory()->create(['name' => 'Medicines', 'slug' => 'medicines']);
        $a = $this->shop(['display_name' => 'Sharma Kirana']);
        $b = $this->shop(['display_name' => 'Style Corner']);
        $c = $this->shop(['display_name' => 'City Pharmacy']);
        $this->product($a, 100, $groceries);
        $this->product($a, 100, $medicine);
        $this->product($b, 100, $clothing);
        $this->product($c, 100, $medicine);

        $response = $this->getJson('/api/v1/shops')->assertOk();
        $facets = collect($response->json('facets.categories'));

        $this->assertEqualsCanonicalizing(['Groceries', 'Clothing', 'Medicines'], $facets->pluck('name')->all());
        $this->assertSame('Medicines', $facets->first()['name'], 'sold by two shops, so it leads');
        $this->assertSame(2, $facets->first()['shops']);
        $this->assertSame(1, $facets->firstWhere('slug', 'clothing')['shops']);

        // Choosing one narrows the shops but keeps every chip on offer.
        $narrow = $this->getJson('/api/v1/shops?category=medicines')->assertOk();
        $this->assertEqualsCanonicalizing(['Sharma Kirana', 'City Pharmacy'], collect($narrow->json('data'))->pluck('name')->all());
        $this->assertCount(3, $narrow->json('facets.categories'));
    }

    public function test_the_category_filters_only_count_shops_that_deliver_to_the_address(): void
    {
        $groceries = Category::factory()->create(['name' => 'Groceries', 'slug' => 'groceries']);
        $clothing = Category::factory()->create(['name' => 'Clothing', 'slug' => 'clothing']);
        $near = $this->shop(['service_pincodes' => ['560038']]);
        $far = $this->shop(['service_pincodes' => ['110001']]);
        $this->product($near, 100, $groceries);
        $this->product($far, 100, $clothing);

        $facets = collect($this->getJson('/api/v1/shops?pincode=560038')->json('facets.categories'))->pluck('slug')->all();

        $this->assertSame(['groceries'], $facets, 'no point offering a filter that shows nothing');
    }

    public function test_a_shops_page_by_slug_or_id_and_its_items_by_the_seller_filter(): void
    {
        $shop = $this->shop(['display_name' => 'Sharma Kirana', 'slug' => 'sharma-kirana', 'about' => 'Family run.', 'opening_hours' => ['wed' => ['open' => '09:00', 'close' => '21:00']]]);
        $mine = $this->product($shop);
        $other = $this->product($this->shop());

        $this->getJson('/api/v1/shops/sharma-kirana')->assertOk()
            ->assertJsonPath('data.name', 'Sharma Kirana')
            ->assertJsonPath('data.about', 'Family run.')
            ->assertJsonPath('data.opening_hours.wed.open', '09:00');
        $this->getJson("/api/v1/shops/{$shop->id}")->assertOk()->assertJsonPath('data.slug', 'sharma-kirana');

        $ids = collect($this->getJson('/api/v1/products?seller=sharma-kirana')->json('data'))->pluck('id');
        $this->assertSame([$mine->id], $ids->all());
        $ids = collect($this->getJson("/api/v1/products?seller={$shop->id}")->json('data'))->pluck('id');
        $this->assertSame([$mine->id], $ids->all());
        $this->assertNotContains($other->id, $ids->all());
    }

    public function test_an_unknown_or_suspended_shop_is_not_found(): void
    {
        $gone = $this->shop(['slug' => 'gone', 'status' => 'SUSPENDED']);

        $this->getJson('/api/v1/shops/gone')->assertNotFound();
        $this->getJson('/api/v1/shops/nothing-here')->assertNotFound();
    }

    // ── Editing the shop ─────────────────────────────────────────────────

    private function seller(): Seller
    {
        $user = User::factory()->create(['role' => User::ROLE_SELLER, 'status' => 'ACTIVE']);

        return Seller::factory()->create(['user_id' => $user->id]);
    }

    public function test_a_seller_sets_up_their_shop(): void
    {
        $seller = $this->seller();

        $this->actingAs($seller->user, 'sanctum')->putJson('/api/v1/seller/me', [
            'tagline' => 'Fresh every morning',
            'about' => 'Family run since 1990.',
            'logo_url' => 'https://img.test/logo.png',
            'min_order_amount' => 199,
            'prep_minutes' => 25,
            'accepting_orders' => true,
            'service_pincodes' => ['560038', '560034', '560038'],
            'opening_hours' => ['mon' => ['open' => '08:00', 'close' => '22:00'], 'sun' => null],
        ])->assertOk();

        $seller = $seller->fresh();
        $this->assertSame('Fresh every morning', $seller->tagline);
        $this->assertSame(199.0, (float) $seller->min_order_amount);
        $this->assertSame(['560038', '560034'], $seller->service_pincodes, 'duplicates dropped');
        $this->assertSame(['open' => '08:00', 'close' => '22:00'], $seller->opening_hours['mon']);
        $this->assertNull($seller->opening_hours['sun']);

        $this->actingAs($seller->user, 'sanctum')->getJson('/api/v1/seller/me')
            ->assertJsonPath('data.tagline', 'Fresh every morning')
            ->assertJsonPath('data.accepting_orders', true)
            ->assertJsonPath('data.min_order_amount', 199);
    }

    public function test_a_seller_can_pause_orders_and_resume(): void
    {
        $seller = $this->seller();

        $this->actingAs($seller->user, 'sanctum')->putJson('/api/v1/seller/me', ['accepting_orders' => false])->assertOk();
        $this->assertFalse($seller->fresh()->accepting_orders);

        $this->actingAs($seller->user, 'sanctum')->putJson('/api/v1/seller/me', ['accepting_orders' => true])->assertOk();
        $this->assertTrue($seller->fresh()->accepting_orders);
    }

    public function test_bad_shop_details_are_refused(): void
    {
        $seller = $this->seller();
        $put = fn (array $body) => $this->actingAs($seller->user, 'sanctum')->putJson('/api/v1/seller/me', $body);

        $put(['service_pincodes' => ['12345']])->assertStatus(422)->assertJsonValidationErrors('service_pincodes.0');
        $put(['opening_hours' => ['mon' => ['open' => '25:00', 'close' => '21:00']]])->assertStatus(422);
        $put(['min_order_amount' => -5])->assertStatus(422)->assertJsonValidationErrors('min_order_amount');
        $put(['prep_minutes' => 5000])->assertStatus(422)->assertJsonValidationErrors('prep_minutes');
    }

    public function test_the_admin_can_edit_any_shops_profile(): void
    {
        $admin = User::factory()->create(['role' => User::ROLE_ADMIN, 'status' => 'ACTIVE']);
        $shop = $this->shop();

        $this->actingAs($admin, 'sanctum')->putJson("/api/v1/admin/sellers/{$shop->id}", [
            'tagline' => 'Edited by admin', 'min_order_amount' => 50, 'service_pincodes' => ['400050'],
        ])->assertOk();

        $this->assertSame('Edited by admin', $shop->fresh()->tagline);
        $this->assertSame(['400050'], $shop->fresh()->service_pincodes);
    }
}
