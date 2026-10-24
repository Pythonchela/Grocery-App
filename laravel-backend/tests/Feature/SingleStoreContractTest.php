<?php

namespace Tests\Feature;

use App\Models\Seller;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Schema;
use Tests\TestCase;

/**
 * This installation is one business. These tests pin that down: if a vendor
 * feature ever comes back (a route, a table, a setting), one of them fails.
 */
class SingleStoreContractTest extends TestCase
{
    use RefreshDatabase;

    private function admin(): User
    {
        return User::factory()->create(['role' => 'ADMIN', 'status' => 'ACTIVE']);
    }

    public function test_the_apps_are_told_this_is_a_single_business(): void
    {
        $this->getJson('/api/v1/config')->assertOk()
            ->assertJsonPath('data.mode', 'single')
            ->assertJsonPath('data.vendors_enabled', false)
            ->assertJsonPath('data.shows_shops', false)
            ->assertJsonPath('data.shops_first', false)
            ->assertJsonPath('data.one_shop_per_cart', false);
    }

    public function test_there_is_no_way_to_apply_to_sell_or_to_run_a_shop_through_the_api(): void
    {
        $customer = User::factory()->create(['role' => 'CUSTOMER', 'status' => 'ACTIVE']);

        foreach ([
            ['post', '/api/v1/sellers/apply'],
            ['get', '/api/v1/seller/onboarding'],
            ['get', '/api/v1/seller/overview'],
            ['get', '/api/v1/seller/order-items'],
            ['get', '/api/v1/seller/money'],
            ['get', '/api/v1/shops'],
        ] as [$method, $url]) {
            $this->actingAs($customer, 'sanctum')->json($method, $url)->assertNotFound();
        }
    }

    public function test_staff_have_no_vendor_screens_either(): void
    {
        $admin = $this->admin();

        foreach ([
            '/api/v1/admin/sellers',
            '/api/v1/admin/sellers/applications',
            '/api/v1/admin/payouts',
            '/api/v1/admin/payout-requests',
            '/api/v1/admin/bank-changes',
            '/api/v1/admin/category-requests',
        ] as $url) {
            $this->actingAs($admin, 'sanctum')->getJson($url)->assertNotFound();
        }
    }

    public function test_the_tables_only_vendors_needed_are_gone(): void
    {
        foreach (['payout_requests', 'seller_ledger_entries', 'seller_documents', 'seller_kyc_profiles', 'category_requests'] as $table) {
            $this->assertFalse(Schema::hasTable($table), $table);
        }
    }

    public function test_the_store_itself_is_the_only_shop(): void
    {
        $this->assertSame(1, Seller::count());
        $this->assertTrue(Seller::first()->is_house);
    }

    public function test_the_owner_has_a_store_profile_to_edit(): void
    {
        $this->actingAs($this->admin(), 'sanctum')->getJson('/api/v1/admin/store')->assertOk()
            ->assertJsonPath('data.slug', 'house');
    }

    public function test_the_integrations_screen_has_no_marketplace_settings(): void
    {
        $groups = $this->actingAs($this->admin(), 'sanctum')->getJson('/api/v1/admin/integrations')->assertOk()->json('data.groups');

        $this->assertNotContains('marketplace', array_column($groups, 'id'));
    }

    public function test_only_staff_can_change_the_catalogue(): void
    {
        $customer = User::factory()->create(['role' => 'CUSTOMER', 'status' => 'ACTIVE']);

        $this->actingAs($customer, 'sanctum')->postJson('/api/v1/products', ['title' => 'x'])->assertForbidden();
    }
}
