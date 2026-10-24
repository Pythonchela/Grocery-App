<?php

namespace Tests\Feature;

use App\Models\Product;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Cache;
use Tests\TestCase;

class ProductFacetCacheTest extends TestCase
{
    use RefreshDatabase;

    public function test_brand_facets_survive_database_cache_round_trip(): void
    {
        config(['cache.default' => 'database']);
        Cache::forget('products.facets');
        Product::factory()->create(['brand' => 'Deployment Test Brand']);

        $this->getJson('/api/v1/products')
            ->assertOk()
            ->assertJsonPath('facets.brands', ['Deployment Test Brand']);

        $this->getJson('/api/v1/products?search=Deployment')
            ->assertOk()
            ->assertJsonPath('facets.brands', ['Deployment Test Brand']);
    }
}
