<?php

namespace Tests\Feature;

use App\Models\Category;
use App\Models\Product;
use App\Models\ProductVariant;
use App\Models\Seller;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

/**
 * What a seller can do to their own catalogue: create, edit, publish, withdraw,
 * add photos. Ownership across sellers is covered in SellerMarketplaceTest; this
 * is the write path itself.
 */
class SellerProductWriteTest extends TestCase
{
    use RefreshDatabase;

    private function seller(string $status = 'ACTIVE'): Seller
    {
        $user = User::factory()->create(['role' => User::ROLE_SELLER, 'status' => 'ACTIVE']);

        return Seller::factory()->create(['user_id' => $user->id, 'status' => $status]);
    }

    private function payload(array $overrides = []): array
    {
        // Real SKUs are unique across the catalogue, so each call gets its own.
        $tag = strtoupper(\Illuminate\Support\Str::random(6));

        return array_merge([
            'title' => 'Handcrafted Brass Lamp',
            'description' => 'Hand-finished in Moradabad.',
            'category_id' => Category::factory()->create()->id,
            'brand' => 'Asha Crafts',
            'mrp' => 2999,
            'price' => 2499,
            'status' => 'DRAFT',
            'images' => ['https://example.com/a.jpg'],
            'variants' => [
                ['color' => 'Gold', 'size' => 'M', 'sku' => "LAMP-G-{$tag}", 'stock' => 5, 'price' => 2499, 'mrp' => 2999],
                ['color' => 'Silver', 'size' => 'M', 'sku' => "LAMP-S-{$tag}", 'stock' => 3, 'price' => 2499, 'mrp' => 2999],
            ],
        ], $overrides);
    }

    private function create(Seller $seller, array $overrides = [])
    {
        return $this->actingAs($seller->user, 'sanctum')->postJson('/api/v1/products', $this->payload($overrides));
    }

    // ── Creating ────────────────────────────────────────────────────────

    public function test_a_seller_can_list_a_product_with_variants(): void
    {
        $seller = $this->seller();

        $response = $this->create($seller)->assertCreated();

        $product = Product::findOrFail($response->json('data.id'));
        $this->assertSame($seller->id, $product->seller_id, 'listed under their own shop');
        $this->assertSame('Handcrafted Brass Lamp', $product->title);
        $this->assertSame(['https://example.com/a.jpg'], $product->images);
        $this->assertCount(2, $product->variants);
        $this->assertEqualsCanonicalizing([5, 3], $product->variants->pluck('stock')->all());
    }

    public function test_two_products_with_the_same_title_do_not_collide(): void
    {
        $seller = $this->seller();

        $first = $this->create($seller)->assertCreated()->json('data.slug');
        $second = $this->create($seller)->assertCreated()->json('data.slug');
        $third = $this->create($seller, ['title' => 'handcrafted BRASS lamp!'])->assertCreated()->json('data.slug');

        $this->assertSame('handcrafted-brass-lamp', $first);
        $this->assertNotSame($first, $second);
        $this->assertCount(3, array_unique([$first, $second, $third]));
        $this->assertStringStartsWith('handcrafted-brass-lamp', $second);
    }

    public function test_a_title_with_nothing_sluggable_still_gets_a_slug(): void
    {
        $seller = $this->seller();

        $slug = $this->create($seller, ['title' => '!!!'])->assertCreated()->json('data.slug');

        $this->assertNotEmpty($slug);
    }

    public function test_a_product_with_no_variants_gets_a_default_one_so_it_can_be_sold(): void
    {
        $seller = $this->seller();

        $id = $this->create($seller, ['variants' => null])->assertCreated()->json('data.id');

        $this->assertSame(1, ProductVariant::where('product_id', $id)->count());
    }

    public function test_required_fields_are_enforced_with_field_level_errors(): void
    {
        $seller = $this->seller();

        $this->actingAs($seller->user, 'sanctum')->postJson('/api/v1/products', [])
            ->assertStatus(422)
            ->assertJsonValidationErrors(['title', 'category_id', 'mrp', 'price']);

        $this->create($seller, ['price' => -1])->assertStatus(422)->assertJsonValidationErrors('price');
        $this->create($seller, ['status' => 'LIVE'])->assertStatus(422)->assertJsonValidationErrors('status');
        $this->create($seller, ['category_id' => '11111111-1111-1111-1111-111111111111'])->assertStatus(422)->assertJsonValidationErrors('category_id');
        $this->create($seller, ['variants' => [['color' => 'Gold', 'stock' => -5]]])->assertStatus(422);
    }

    public function test_a_pending_seller_cannot_list_products(): void
    {
        $this->create($this->seller('PENDING'))->assertForbidden();
        $this->assertSame(0, Product::count());
    }

    public function test_a_customer_cannot_list_products(): void
    {
        $customer = User::factory()->create(['role' => 'CUSTOMER', 'status' => 'ACTIVE']);

        $this->actingAs($customer, 'sanctum')->postJson('/api/v1/products', $this->payload())->assertForbidden();
    }

    // ── SKUs ────────────────────────────────────────────────────────────

    public function test_a_duplicate_sku_is_a_field_error_not_a_server_crash(): void
    {
        $seller = $this->seller();
        $this->create($seller, ['variants' => [['color' => 'Gold', 'sku' => 'DUP-1', 'stock' => 1]]])->assertCreated();

        $this->create($seller, ['variants' => [['color' => 'Gold', 'sku' => 'DUP-1', 'stock' => 1]]])
            ->assertStatus(422)
            ->assertJsonValidationErrors('variants.0.sku');

        $this->assertSame(1, Product::count(), 'nothing half-created');
    }

    public function test_another_sellers_sku_cannot_be_reused_either(): void
    {
        $this->create($this->seller(), ['variants' => [['color' => 'Gold', 'sku' => 'SHARED', 'stock' => 1]]])->assertCreated();

        $this->create($this->seller(), ['variants' => [['color' => 'Gold', 'sku' => 'SHARED', 'stock' => 1]]])
            ->assertStatus(422)->assertJsonValidationErrors('variants.0.sku');
    }

    public function test_two_variants_in_one_submission_cannot_share_a_sku(): void
    {
        $this->create($this->seller(), ['variants' => [
            ['color' => 'Gold', 'sku' => 'SAME', 'stock' => 1],
            ['color' => 'Silver', 'sku' => 'SAME', 'stock' => 1],
        ]])->assertStatus(422)->assertJsonValidationErrors(['variants.0.sku', 'variants.1.sku']);
    }

    public function test_saving_an_edit_does_not_trip_over_the_variants_own_sku(): void
    {
        $seller = $this->seller();
        $product = Product::findOrFail($this->create($seller, ['variants' => [['color' => 'Gold', 'sku' => 'MINE', 'stock' => 1]]])->json('data.id'));
        $variant = $product->variants->first();

        $this->actingAs($seller->user, 'sanctum')->putJson("/api/v1/products/{$product->id}", [
            'variants' => [['id' => $variant->id, 'sku' => 'MINE', 'stock' => 20]],
        ])->assertOk();

        $this->assertSame(20, $variant->fresh()->stock);
    }

    public function test_an_edit_cannot_take_a_sku_that_belongs_to_another_variant(): void
    {
        $seller = $this->seller();
        $this->create($seller, ['variants' => [['color' => 'Gold', 'sku' => 'TAKEN', 'stock' => 1]]])->assertCreated();
        $product = Product::findOrFail($this->create($seller, ['variants' => [['color' => 'Gold', 'sku' => 'OTHER', 'stock' => 1]]])->json('data.id'));

        $this->actingAs($seller->user, 'sanctum')->putJson("/api/v1/products/{$product->id}", [
            'variants' => [['id' => $product->variants->first()->id, 'sku' => 'TAKEN']],
        ])->assertStatus(422)->assertJsonValidationErrors('variants.0.sku');
    }

    public function test_variants_without_a_sku_are_fine(): void
    {
        $seller = $this->seller();

        $this->create($seller, ['variants' => [['color' => 'Gold', 'stock' => 1], ['color' => 'Silver', 'stock' => 1]]])->assertCreated();
        $this->create($seller, ['variants' => [['color' => 'Gold', 'sku' => '', 'stock' => 1]]])->assertCreated();
    }

    // ── Editing ─────────────────────────────────────────────────────────

    public function test_a_seller_can_change_price_stock_and_status(): void
    {
        $seller = $this->seller();
        $product = Product::findOrFail($this->create($seller)->json('data.id'));
        $variant = $product->variants->first();

        $this->actingAs($seller->user, 'sanctum')->putJson("/api/v1/products/{$product->id}", [
            'price' => 1999,
            'status' => 'ACTIVE',
            'variants' => [
                ['id' => $variant->id, 'stock' => 42, 'price' => 1999],
                ['id' => $product->variants->last()->id, 'stock' => 3],
            ],
        ])->assertOk();

        $this->assertEquals(1999.0, (float) $product->fresh()->price);
        $this->assertSame('ACTIVE', $product->fresh()->status);
        $this->assertSame(42, $variant->fresh()->stock);
    }

    public function test_editing_variants_keeps_their_identity(): void
    {
        $seller = $this->seller();
        $product = Product::findOrFail($this->create($seller)->json('data.id'));
        $ids = $product->variants->pluck('id')->sort()->values()->all();

        $this->actingAs($seller->user, 'sanctum')->putJson("/api/v1/products/{$product->id}", [
            'variants' => $product->variants->map(fn ($v) => ['id' => $v->id, 'stock' => 9])->all(),
        ])->assertOk();

        $this->assertSame($ids, $product->fresh('variants')->variants->pluck('id')->sort()->values()->all(),
            'past orders stay attached to the variant they were placed against');
    }

    public function test_a_seller_can_add_a_variant_and_remove_one_nobody_has_bought(): void
    {
        $seller = $this->seller();
        $product = Product::findOrFail($this->create($seller)->json('data.id'));
        $keep = $product->variants->first();

        $this->actingAs($seller->user, 'sanctum')->putJson("/api/v1/products/{$product->id}", [
            'variants' => [
                ['id' => $keep->id, 'stock' => 5],
                ['color' => 'Bronze', 'size' => 'L', 'stock' => 8],
            ],
        ])->assertOk();

        $variants = $product->fresh('variants')->variants;
        $this->assertCount(2, $variants);
        $this->assertTrue($variants->contains('color', 'Bronze'));
        $this->assertFalse($variants->contains('color', 'Silver'), 'the dropped one, never sold, is gone');
    }

    public function test_a_variant_that_has_been_sold_is_zeroed_not_deleted_when_removed(): void
    {
        $seller = $this->seller();
        $product = Product::findOrFail($this->create($seller, ['status' => 'ACTIVE'])->json('data.id'));
        $sold = $product->variants->first();
        $buyer = User::factory()->create(['role' => 'CUSTOMER', 'status' => 'ACTIVE']);

        $this->actingAs($buyer, 'sanctum')->postJson('/api/v1/orders/checkout', [
            'items' => [['product_id' => $product->id, 'variant_id' => $sold->id, 'quantity' => 1]],
            'shipping_address' => ['name' => 'P', 'phone' => '9876543210', 'line1' => 'x', 'city' => 'B', 'state' => 'K', 'pincode' => '560038'],
            'payment_method' => 'COD',
        ])->assertCreated();

        $this->actingAs($seller->user, 'sanctum')->putJson("/api/v1/products/{$product->id}", [
            'variants' => [['id' => $product->variants->last()->id, 'stock' => 3]],
        ])->assertOk();

        $this->assertNotNull(ProductVariant::find($sold->id), 'order history still points at it');
        $this->assertSame(0, ProductVariant::find($sold->id)->stock);
    }

    public function test_a_draft_stays_off_the_storefront_until_it_is_published(): void
    {
        $seller = $this->seller();
        $product = Product::findOrFail($this->create($seller, ['status' => 'DRAFT'])->json('data.id'));

        $this->assertNotContains($product->id, collect($this->getJson('/api/v1/products?per_page=100')->json('data'))->pluck('id')->all());

        $this->actingAs($seller->user, 'sanctum')->putJson("/api/v1/products/{$product->id}", ['status' => 'ACTIVE'])->assertOk();

        $this->assertContains($product->id, collect($this->getJson('/api/v1/products?per_page=100')->json('data'))->pluck('id')->all());
    }

    public function test_the_seller_sees_their_drafts_in_their_own_list(): void
    {
        $seller = $this->seller();
        $this->create($seller, ['status' => 'DRAFT'])->assertCreated();

        $this->actingAs($seller->user, 'sanctum')->getJson('/api/v1/seller/products?status=DRAFT')
            ->assertOk()->assertJsonPath('count', 1);
    }

    // ── Removing ────────────────────────────────────────────────────────

    public function test_a_product_nobody_has_bought_can_be_deleted(): void
    {
        $seller = $this->seller();
        $id = $this->create($seller)->json('data.id');

        $this->actingAs($seller->user, 'sanctum')->deleteJson("/api/v1/products/{$id}")->assertOk();

        $this->assertNull(Product::find($id));
        $this->assertSame(0, ProductVariant::where('product_id', $id)->count());
    }

    public function test_a_product_that_has_been_bought_is_discontinued_not_deleted(): void
    {
        $seller = $this->seller();
        $product = Product::findOrFail($this->create($seller, ['status' => 'ACTIVE'])->json('data.id'));
        $buyer = User::factory()->create(['role' => 'CUSTOMER', 'status' => 'ACTIVE']);

        $this->actingAs($buyer, 'sanctum')->postJson('/api/v1/orders/checkout', [
            'items' => [['product_id' => $product->id, 'variant_id' => $product->variants->first()->id, 'quantity' => 1]],
            'shipping_address' => ['name' => 'P', 'phone' => '9876543210', 'line1' => 'x', 'city' => 'B', 'state' => 'K', 'pincode' => '560038'],
            'payment_method' => 'COD',
        ])->assertCreated();

        $this->actingAs($seller->user, 'sanctum')->deleteJson("/api/v1/products/{$product->id}")
            ->assertStatus(422)
            ->assertJsonPath('message', fn ($m) => str_contains($m, 'DISCONTINUED'));

        $this->actingAs($seller->user, 'sanctum')->putJson("/api/v1/products/{$product->id}", ['status' => 'DISCONTINUED'])->assertOk();
        $this->assertSame('DISCONTINUED', $product->fresh()->status);
    }

    // ── Photos ──────────────────────────────────────────────────────────

    public function test_a_seller_can_upload_a_photo_and_get_a_url_to_attach(): void
    {
        Storage::fake('media');
        $seller = $this->seller();

        $response = $this->actingAs($seller->user, 'sanctum')
            ->post('/api/v1/uploads', ['file' => UploadedFile::fake()->image('lamp.jpg', 800, 800)], ['Accept' => 'application/json'])
            ->assertCreated();

        $this->assertNotEmpty($response->json('data.url'));
        Storage::disk('media')->assertExists($response->json('data.path'));
    }

    public function test_only_images_and_video_are_accepted(): void
    {
        Storage::fake('media');
        $seller = $this->seller();

        $this->actingAs($seller->user, 'sanctum')
            ->post('/api/v1/uploads', ['file' => UploadedFile::fake()->create('notes.txt', 5, 'text/plain')], ['Accept' => 'application/json'])
            ->assertStatus(422)->assertJsonValidationErrors('file');

        $this->actingAs($seller->user, 'sanctum')
            ->post('/api/v1/uploads', ['file' => UploadedFile::fake()->create('big.jpg', 11 * 1024, 'image/jpeg')], ['Accept' => 'application/json'])
            ->assertStatus(422)->assertJsonValidationErrors('file');
    }

    public function test_a_pending_seller_and_a_customer_cannot_upload(): void
    {
        Storage::fake('media');
        $file = ['file' => UploadedFile::fake()->image('a.jpg')];

        $this->actingAs($this->seller('PENDING')->user, 'sanctum')->post('/api/v1/uploads', $file, ['Accept' => 'application/json'])->assertForbidden();

        $customer = User::factory()->create(['role' => 'CUSTOMER', 'status' => 'ACTIVE']);
        $this->actingAs($customer, 'sanctum')->post('/api/v1/uploads', $file, ['Accept' => 'application/json'])->assertForbidden();
    }

    // ── Saving as you go ────────────────────────────────────────────────

    public function test_a_draft_can_be_saved_with_only_a_name_and_a_category(): void
    {
        $seller = $this->seller();

        $response = $this->actingAs($seller->user, 'sanctum')->postJson('/api/v1/products', [
            'title' => 'Half done lamp',
            'category_id' => Category::factory()->create()->id,
            'mrp' => 0,
            'price' => 0,
            'status' => 'DRAFT',
            'variants' => [['color' => 'Standard', 'size' => 'Free Size', 'stock' => 0]],
        ])->assertCreated();

        $this->assertSame('DRAFT', $response->json('data.status'));
        $this->assertSame(0, (int) $response->json('data.variants.0.stock'), 'no invented stock');
    }

    public function test_a_product_cannot_go_live_without_a_real_price(): void
    {
        $seller = $this->seller();

        $this->create($seller, ['status' => 'ACTIVE', 'price' => 0, 'mrp' => 0])
            ->assertStatus(422)->assertJsonValidationErrors('price');

        $id = $this->create($seller, ['status' => 'DRAFT', 'price' => 0, 'mrp' => 0])->assertCreated()->json('data.id');
        $this->actingAs($seller->user, 'sanctum')->putJson("/api/v1/products/{$id}", ['status' => 'ACTIVE'])
            ->assertStatus(422)->assertJsonValidationErrors('price');

        $this->actingAs($seller->user, 'sanctum')->putJson("/api/v1/products/{$id}", ['status' => 'ACTIVE', 'price' => 499, 'mrp' => 599])
            ->assertOk();
        $this->assertSame('ACTIVE', \App\Models\Product::find($id)->status);
    }

    public function test_a_draft_stays_hidden_from_shoppers_while_it_is_being_filled_in(): void
    {
        $seller = $this->seller();
        $this->create($seller, ['status' => 'DRAFT', 'title' => 'Not ready yet', 'price' => 0, 'mrp' => 0])->assertCreated();

        $titles = collect($this->getJson('/api/v1/products')->json('data'))->pluck('title');
        $this->assertNotContains('Not ready yet', $titles);
    }

}
