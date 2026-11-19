<?php

namespace Tests\Feature;

use App\Models\Category;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/** The text a seller writes for search results is saved, returned, and kept within what search engines show. */
class ProductSearchTextTest extends TestCase
{
    use RefreshDatabase;

    private function body(array $extra = []): array
    {
        return array_merge([
            'title' => 'Handwoven Cotton Dupatta',
            'category_id' => Category::factory()->create()->id,
            'price' => 899,
            'mrp' => 899,
            'status' => 'ACTIVE',
            'variants' => [['stock' => 5]],
        ], $extra);
    }

    public function test_the_search_text_is_saved_and_comes_back_on_the_product(): void
    {
        $admin = User::factory()->create(['role' => 'ADMIN', 'status' => 'ACTIVE']);

        $created = $this->actingAs($admin, 'sanctum')->postJson('/api/v1/products', $this->body([
            'meta_title' => 'Handwoven dupatta',
            'meta_description' => 'Handwoven cotton dupatta with a zari border, 2.25 m long.',
        ]))->assertCreated();

        $this->getJson('/api/v1/products/'.$created->json('data.id'))
            ->assertOk()
            ->assertJsonPath('data.meta_description', 'Handwoven cotton dupatta with a zari border, 2.25 m long.')
            ->assertJsonPath('data.meta_title', 'Handwoven dupatta');
    }

    public function test_text_longer_than_the_column_is_refused_not_cut_off_by_the_database(): void
    {
        $admin = User::factory()->create(['role' => 'ADMIN', 'status' => 'ACTIVE']);

        $this->actingAs($admin, 'sanctum')->postJson('/api/v1/products', $this->body(['meta_description' => str_repeat('a', 300)]))
            ->assertStatus(422)->assertJsonValidationErrors('meta_description');
    }
}
