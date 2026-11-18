<?php

namespace Tests\Feature;

use App\Models\Category;
use App\Models\Product;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/** The veg / non-veg mark: stored, returned to shoppers, and refused when it is not a real value. */
class ProductDietTest extends TestCase
{
    use RefreshDatabase;

    private function admin(): User
    {
        return User::factory()->create(['role' => 'ADMIN', 'status' => 'ACTIVE']);
    }

    private function body(array $extra = []): array
    {
        return array_merge([
            'title' => 'Paneer Tikka',
            'category_id' => Category::factory()->create()->id,
            'price' => 220,
            'mrp' => 220,
            'status' => 'DRAFT',
            'variants' => [['stock' => 10]],
        ], $extra);
    }

    public function test_a_dish_can_be_marked_veg_and_shoppers_see_the_mark(): void
    {
        $res = $this->actingAs($this->admin(), 'sanctum')->postJson('/api/v1/products', $this->body(['diet' => 'veg']));
        $res->assertCreated()->assertJsonPath('data.diet', 'veg');

        $this->assertSame('veg', Product::first()->diet);
    }

    public function test_the_mark_is_optional_and_can_be_cleared(): void
    {
        $admin = $this->admin();
        $id = $this->actingAs($admin, 'sanctum')->postJson('/api/v1/products', $this->body(['diet' => 'non_veg']))->json('data.id');

        $this->actingAs($admin, 'sanctum')->putJson("/api/v1/products/$id", $this->body(['diet' => null]))
            ->assertOk()->assertJsonPath('data.diet', null);
    }

    public function test_only_veg_non_veg_or_egg_are_accepted(): void
    {
        $this->actingAs($this->admin(), 'sanctum')->postJson('/api/v1/products', $this->body(['diet' => 'vegan-ish']))
            ->assertStatus(422)->assertJsonValidationErrors('diet');
    }
}
