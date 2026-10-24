<?php

namespace Tests\Feature;

use App\Models\Order;
use App\Models\Product;
use App\Models\ProductVariant;
use App\Models\User;
use App\Services\AIService;
use App\Services\Contracts\ProductParser;
use App\Services\Import\GeminiProductParser;
use App\Services\Import\HeuristicProductParser;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

/**
 * The AI features must degrade to their built-in behaviour when no Gemini key is
 * configured — which is the normal state of a fresh deployment.
 *
 * Regression: the `gemini` config block defines the key as null, and a config
 * default only applies to a *missing* key, so AIService's constructor received
 * null for its typed property and threw. Every route that resolves the service
 * (the product reviews page, review submission) then returned a 500.
 */
class AiServiceWithoutKeyTest extends TestCase
{
    use RefreshDatabase;

    private function withKey(mixed $key): void
    {
        config(['services.gemini.key' => $key]);
        $this->app->forgetInstance(AIService::class);
        $this->app->forgetInstance(ProductParser::class);
    }

    public function test_the_service_builds_when_the_key_is_null(): void
    {
        $this->withKey(null);

        $this->assertInstanceOf(AIService::class, app(AIService::class));
    }

    public function test_the_service_builds_for_every_kind_of_missing_key(): void
    {
        foreach ([null, '', '   ', false, []] as $missing) {
            $this->withKey($missing);

            $this->assertInstanceOf(AIService::class, app(AIService::class), var_export($missing, true));
        }
    }

    public function test_search_intent_falls_back_to_the_built_in_answer_without_calling_google(): void
    {
        Http::fake();
        $this->withKey(null);

        $intent = app(AIService::class)->extractSearchIntent('a gift for my mother');

        $this->assertTrue($intent['is_gift']);
        Http::assertNothingSent();
    }

    public function test_the_product_parser_uses_the_built_in_one_without_a_key(): void
    {
        $this->withKey(null);
        $this->assertInstanceOf(HeuristicProductParser::class, app(ProductParser::class));

        $this->withKey('');
        $this->assertInstanceOf(HeuristicProductParser::class, app(ProductParser::class));
    }

    public function test_the_product_parser_uses_gemini_once_a_key_is_present(): void
    {
        $this->withKey('a-test-key');

        $this->assertInstanceOf(GeminiProductParser::class, app(ProductParser::class));
    }

    // ── The routes that used to crash ───────────────────────────────────

    public function test_the_product_reviews_page_loads_with_no_key(): void
    {
        $this->withKey(null);
        $product = Product::factory()->create();

        $this->getJson("/api/v1/products/{$product->id}/reviews")
            ->assertOk()
            ->assertJsonPath('summary.total', 0)
            ->assertJsonPath('summary.is_ai_generated', false);
    }

    public function test_the_reviews_page_still_loads_for_a_product_that_has_reviews(): void
    {
        $this->withKey(null);
        [$user, $product, $order] = $this->deliveredPurchase();

        $this->actingAs($user, 'sanctum')->postJson("/api/v1/products/{$product->id}/reviews", [
            'order_id' => $order->id, 'rating' => 5, 'title' => 'Lovely', 'body' => 'Beautiful work, arrived well packed.',
        ])->assertCreated();
        \App\Models\Review::query()->update(['status' => 'APPROVED']);

        $this->getJson("/api/v1/products/{$product->id}/reviews")
            ->assertOk()
            ->assertJsonPath('summary.total', 1);
    }

    public function test_submitting_a_review_works_with_no_key_and_still_gets_a_fraud_score(): void
    {
        $this->withKey(null);
        [$user, $product, $order] = $this->deliveredPurchase();

        $response = $this->actingAs($user, 'sanctum')->postJson("/api/v1/products/{$product->id}/reviews", [
            'order_id' => $order->id, 'rating' => 4, 'body' => 'Good quality for the price.',
        ])->assertCreated();

        $this->assertNotNull($response->json('data.ai_fraud_score'), 'the built-in screen still runs');
    }

    /** @return array{0: User, 1: Product, 2: Order} */
    private function deliveredPurchase(): array
    {
        $user = User::factory()->create(['role' => 'CUSTOMER', 'status' => 'ACTIVE']);
        $product = Product::factory()->pricedAt(500)->create();
        ProductVariant::factory()->withStock(5)->create(['product_id' => $product->id]);
        $product = $product->fresh('variants');

        $this->actingAs($user, 'sanctum')->postJson('/api/v1/orders/checkout', [
            'items' => [['product_id' => $product->id, 'variant_id' => $product->variants->first()->id, 'quantity' => 1]],
            'shipping_address' => ['name' => 'P', 'phone' => '9876543210', 'line1' => 'x', 'city' => 'B', 'state' => 'K', 'pincode' => '560038'],
            'payment_method' => 'COD',
        ])->assertCreated();

        $order = Order::firstOrFail();
        $order->update(['status' => 'DELIVERED', 'delivered_at' => now()->subDay()]);

        return [$user, $product, $order];
    }
}
