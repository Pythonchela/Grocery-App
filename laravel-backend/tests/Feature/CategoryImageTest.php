<?php

namespace Tests\Feature;

use App\Models\Category;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class CategoryImageTest extends TestCase
{
    use RefreshDatabase;

    private function admin(): User
    {
        return User::factory()->create(['role' => User::ROLE_ADMIN, 'status' => 'ACTIVE']);
    }

    public function test_an_admin_can_give_a_category_a_picture_and_the_public_list_shows_it(): void
    {
        $this->actingAs($this->admin(), 'sanctum')->postJson('/api/v1/categories', [
            'name' => 'Fresh Produce',
            'slug' => 'fresh-produce',
            'icon_url' => 'Leaf',
            'image_url' => 'https://cdn.example.com/produce.jpg',
        ])->assertCreated();

        $this->getJson('/api/v1/categories')
            ->assertOk()
            ->assertJsonPath('data.0.image_url', 'https://cdn.example.com/produce.jpg')
            ->assertJsonPath('data.0.icon_url', 'Leaf');
    }

    public function test_the_picture_is_optional_and_can_be_removed(): void
    {
        $admin = $this->admin();
        $category = Category::factory()->create(['image_url' => 'https://cdn.example.com/a.jpg']);

        $this->actingAs($admin, 'sanctum')
            ->putJson("/api/v1/categories/{$category->id}", ['image_url' => null])
            ->assertOk();

        $this->assertNull($category->fresh()->image_url);
    }

    public function test_customers_cannot_change_a_categorys_picture(): void
    {
        $category = Category::factory()->create();

        $this->actingAs(User::factory()->create(['role' => 'CUSTOMER']), 'sanctum')
            ->putJson("/api/v1/categories/{$category->id}", ['image_url' => 'https://x.test/y.jpg'])
            ->assertForbidden();
    }

    public function test_a_category_without_a_picture_shows_a_photo_of_something_in_it(): void
    {
        $withPicture = Category::factory()->create(['image_url' => 'https://cdn.example.com/a.jpg', 'sort_order' => 1]);
        $without = Category::factory()->create(['image_url' => null, 'sort_order' => 2]);
        $empty = Category::factory()->create(['image_url' => null, 'sort_order' => 3]);

        \App\Models\Product::factory()->create([
            'category_id' => $without->id, 'status' => 'ACTIVE', 'images' => ['https://cdn.example.com/p1.jpg'],
        ]);
        \App\Models\Product::factory()->create([
            'category_id' => $without->id, 'status' => 'DRAFT', 'images' => ['https://cdn.example.com/draft.jpg'],
        ]);

        $rows = collect($this->getJson('/api/v1/categories')->assertOk()->json('data'))->keyBy('id');

        // The uploaded picture always wins.
        $this->assertSame('https://cdn.example.com/a.jpg', $rows[$withPicture->id]['cover_image_url']);
        // Otherwise a live product's photo - never a draft's.
        $this->assertSame('https://cdn.example.com/p1.jpg', $rows[$without->id]['cover_image_url']);
        // Nothing to show: null, and the app falls back to the icon.
        $this->assertNull($rows[$empty->id]['cover_image_url']);
    }
}
