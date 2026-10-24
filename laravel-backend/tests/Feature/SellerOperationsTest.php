<?php

namespace Tests\Feature;

use App\Models\Product;
use App\Models\Category;
use App\Models\CategoryRequest;
use App\Models\ProductQuestion;
use App\Models\ProductVariant;
use App\Models\Order;
use App\Models\OrderItem;
use App\Models\ReturnRequest;
use App\Models\Review;
use App\Models\Seller;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class SellerOperationsTest extends TestCase
{
    use RefreshDatabase;

    private function seller(): Seller
    {
        $user = User::factory()->create(['role' => User::ROLE_SELLER, 'status' => 'ACTIVE']);

        return Seller::factory()->create(['user_id' => $user->id, 'status' => 'ACTIVE']);
    }

    public function test_feedback_and_insights_are_scoped_to_the_sellers_own_products(): void
    {
        $mine = $this->seller();
        $other = $this->seller();
        $myProduct = Product::factory()->soldBy($mine)->create();
        $otherProduct = Product::factory()->soldBy($other)->create();
        $review = Review::create(['product_id' => $myProduct->id, 'rating' => 4, 'body' => 'Good', 'status' => 'APPROVED']);
        $otherReview = Review::create(['product_id' => $otherProduct->id, 'rating' => 1, 'body' => 'Other', 'status' => 'APPROVED']);
        $question = ProductQuestion::create(['product_id' => $myProduct->id, 'body' => 'How big?', 'status' => 'APPROVED']);
        ProductQuestion::create(['product_id' => $otherProduct->id, 'body' => 'Other question', 'status' => 'APPROVED']);

        $this->actingAs($mine->user, 'sanctum')
            ->getJson('/api/v1/seller/reviews')->assertOk()->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.id', $review->id);
        $this->getJson('/api/v1/seller/questions')->assertOk()->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.id', $question->id);
        $this->getJson('/api/v1/seller/overview')->assertOk()->assertJsonPath('data.questions_open', 1);

        $this->putJson("/api/v1/seller/reviews/{$otherReview->id}/reply", ['reply' => 'Wrong shop'])
            ->assertNotFound();
        $this->putJson("/api/v1/seller/reviews/{$review->id}/reply", ['reply' => 'Thank you'])
            ->assertOk();
        $this->assertSame('Thank you', $review->fresh()->admin_reply);

        $this->postJson("/api/v1/questions/{$question->id}/answer", ['body' => '20 cm'])
            ->assertCreated()->assertJsonPath('data.is_official', true);
        $this->getJson('/api/v1/seller/overview')->assertOk()->assertJsonPath('data.questions_open', 0);
    }

    public function test_bulk_import_cannot_assign_products_to_another_shop(): void
    {
        $mine = $this->seller();
        $other = $this->seller();
        $category = \App\Models\Category::factory()->create();

        $response = $this->actingAs($mine->user, 'sanctum')->postJson('/api/v1/seller/products/import/commit', [
            'seller_id' => $other->id,
            'status' => 'DRAFT',
            'rows' => [[
                'title' => 'Imported mug', 'price' => 200, 'mrp' => 250,
                'category_id' => $category->id,
            ]],
        ])->assertCreated();

        $this->assertSame($mine->id, Product::findOrFail($response->json('data.products.0.id'))->seller_id);
    }

    public function test_category_requests_are_private_and_admin_can_approve_them(): void
    {
        $mine = $this->seller();
        $other = $this->seller();
        $request = $this->actingAs($mine->user, 'sanctum')
            ->postJson('/api/v1/seller/category-requests', ['name' => 'Board games', 'reason' => 'Family games'])
            ->assertCreated()->json('data');

        $this->postJson('/api/v1/seller/category-requests', ['name' => 'board games'])
            ->assertUnprocessable();
        $this->actingAs($other->user, 'sanctum')->getJson('/api/v1/seller/category-requests')
            ->assertOk()->assertJsonCount(0, 'data');
        $this->getJson('/api/v1/admin/category-requests')->assertForbidden();

        $admin = User::factory()->create(['role' => 'ADMIN', 'status' => 'ACTIVE']);
        $this->actingAs($admin, 'sanctum')->getJson('/api/v1/admin/category-requests?status=PENDING')
            ->assertOk()->assertJsonCount(1, 'data');
        $this->putJson("/api/v1/admin/category-requests/{$request['id']}", ['decision' => 'APPROVED'])
            ->assertOk()->assertJsonPath('data.status', 'APPROVED');
        $this->assertSame('Board games', Category::where('slug', 'board-games')->firstOrFail()->name);
        $this->assertSame($mine->id, CategoryRequest::findOrFail($request['id'])->seller_id);
        $this->putJson("/api/v1/admin/category-requests/{$request['id']}", ['decision' => 'REJECTED'])
            ->assertUnprocessable();
    }

    public function test_seller_offers_are_scoped_to_their_shop_and_catalog(): void
    {
        $mine = $this->seller();
        $other = $this->seller();
        $myProduct = Product::factory()->pricedAt(1000)->soldBy($mine)->create();
        $otherProduct = Product::factory()->pricedAt(2000)->soldBy($other)->create();
        $myVariant = ProductVariant::factory()->withStock(10)->create(['product_id' => $myProduct->id]);
        $otherVariant = ProductVariant::factory()->withStock(10)->create(['product_id' => $otherProduct->id]);

        $coupon = $this->actingAs($mine->user, 'sanctum')->postJson('/api/v1/seller/coupons', [
            'code' => 'MYSHOP10', 'type' => 'PERCENT', 'value' => 10, 'min_order' => 500,
            'seller_id' => $other->id, 'target_type' => 'ALL',
        ])->assertCreated()->json('data');
        $this->assertSame($mine->id, $coupon['seller_id']);
        $this->getJson('/api/v1/seller/coupons')->assertOk()->assertJsonCount(1, 'data');

        $this->actingAs($other->user, 'sanctum')->getJson('/api/v1/seller/coupons')
            ->assertOk()->assertJsonCount(0, 'data');
        $this->putJson("/api/v1/seller/coupons/{$coupon['id']}", ['is_active' => false])->assertNotFound();

        $customer = User::factory()->create(['role' => 'CUSTOMER', 'status' => 'ACTIVE']);
        $this->actingAs($customer, 'sanctum')->postJson('/api/v1/coupons/preview', [
            'code' => 'MYSHOP10', 'items' => [['product_id' => $otherProduct->id, 'variant_id' => $otherVariant->id, 'quantity' => 1]],
        ])->assertUnprocessable();
        $this->postJson('/api/v1/coupons/preview', [
            'code' => 'MYSHOP10', 'items' => [['product_id' => $myProduct->id, 'variant_id' => $myVariant->id, 'quantity' => 1]],
        ])->assertOk()->assertJsonPath('data.discount', 100);
    }

    public function test_seller_can_review_only_their_own_open_return_without_deciding_refund(): void
    {
        $mine = $this->seller();
        $other = $this->seller();
        $buyer = User::factory()->create();
        $order = Order::create([
            'order_number' => 'BX-RETURN-1', 'user_id' => $buyer->id, 'status' => 'DELIVERED',
            'payment_status' => 'PAID', 'payment_method' => 'COD', 'subtotal' => 100,
            'discount' => 0, 'shipping_charge' => 0, 'total_amount' => 100,
            'shipping_address' => ['name' => 'Buyer', 'line1' => 'Street', 'city' => 'Delhi', 'state' => 'Delhi', 'pincode' => '110001'],
        ]);
        $myProduct = Product::factory()->soldBy($mine)->create();
        $otherProduct = Product::factory()->soldBy($other)->create();
        $myItem = OrderItem::create(['order_id' => $order->id, 'product_id' => $myProduct->id, 'seller_id' => $mine->id, 'quantity' => 1, 'price' => 100]);
        $otherItem = OrderItem::create(['order_id' => $order->id, 'product_id' => $otherProduct->id, 'seller_id' => $other->id, 'quantity' => 1, 'price' => 100]);
        $mineReturn = ReturnRequest::create(['rma_number' => 'RMA-MINE', 'order_id' => $order->id, 'order_item_id' => $myItem->id, 'user_id' => $buyer->id, 'kind' => 'RETURN', 'reason' => 'Damaged', 'status' => 'REQUESTED']);
        $otherReturn = ReturnRequest::create(['rma_number' => 'RMA-OTHER', 'order_id' => $order->id, 'order_item_id' => $otherItem->id, 'user_id' => $buyer->id, 'kind' => 'RETURN', 'reason' => 'Damaged', 'status' => 'REQUESTED']);

        $this->actingAs($mine->user, 'sanctum')->putJson("/api/v1/seller/returns/{$otherReturn->id}/review", [
            'seller_recommendation' => 'REJECT', 'seller_note' => 'Wrong item',
        ])->assertNotFound();
        $this->putJson("/api/v1/seller/returns/{$mineReturn->id}/review", [
            'seller_recommendation' => 'ACCEPT', 'seller_note' => 'Damage confirmed', 'status' => 'REFUNDED',
        ])->assertOk()->assertJsonPath('data.status', 'REQUESTED');
        $this->assertSame('ACCEPT', $mineReturn->fresh()->seller_recommendation);
    }

    public function test_single_business_staff_can_run_the_house_shop_from_seller_dashboard(): void
    {
        config(['marketplace.mode' => 'single']);
        $house = \Database\Factories\SellerFactory::house();
        $product = Product::factory()->soldBy($house)->create();
        $admin = User::factory()->create(['role' => 'ADMIN', 'status' => 'ACTIVE']);

        $this->actingAs($admin, 'sanctum')->getJson('/api/v1/seller/me')
            ->assertOk()->assertJsonPath('data.id', $house->id);
        $this->getJson('/api/v1/seller/products')->assertOk()
            ->assertJsonPath('data.0.id', $product->id);

    }

    public function test_marketplace_admin_cannot_enter_a_sellers_shop(): void
    {
        config(['marketplace.mode' => 'hybrid']);
        $admin = User::factory()->create(['role' => 'ADMIN', 'status' => 'ACTIVE']);
        $this->actingAs($admin, 'sanctum')->getJson('/api/v1/seller/me')->assertForbidden();
    }

    public function test_product_search_finds_own_titles_and_skus_only(): void
    {
        $mine = $this->seller();
        $other = $this->seller();
        $product = Product::factory()->soldBy($mine)->create(['title' => 'Copper Kettle']);
        ProductVariant::factory()->create(['product_id' => $product->id, 'sku' => 'SHOP-123']);
        Product::factory()->soldBy($other)->create(['title' => 'Silver Kettle']);

        $this->actingAs($mine->user, 'sanctum')->getJson('/api/v1/seller/products?search=Copper')
            ->assertOk()->assertJsonCount(1, 'data');
        $this->getJson('/api/v1/seller/products?search=SHOP-123')
            ->assertOk()->assertJsonPath('data.0.id', $product->id);
        $this->getJson('/api/v1/seller/products?search=Silver')
            ->assertOk()->assertJsonCount(0, 'data');
    }
}
