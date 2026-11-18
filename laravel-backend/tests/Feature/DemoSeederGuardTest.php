<?php

namespace Tests\Feature;

use App\Models\Category;
use App\Models\Product;
use App\Models\User;
use Database\Seeders\DatabaseSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/** The demo seeder publishes admin passwords, so it must not run on a live site. */
class DemoSeederGuardTest extends TestCase
{
    use RefreshDatabase;

    public function test_it_refuses_to_run_in_production_and_creates_no_admin(): void
    {
        $this->app['env'] = 'production';

        try {
            (new DatabaseSeeder)->run();
            $this->fail('The seeder ran in production.');
        } catch (\RuntimeException $e) {
            $this->assertStringContainsString('Refusing to run the demo seeder in production', $e->getMessage());
        }

        $this->assertSame(0, User::where('email', 'admin@haatvia.test')->count());
        $this->assertSame(0, User::where('email', 'admin@example.com')->count());
    }

    public function test_the_demo_catalogue_is_this_apps_own_kind_of_item(): void
    {
        (new DatabaseSeeder)->run();

        $this->assertGreaterThan(0, Product::count());
        $this->assertSame(['instant'], Category::pluck('delivery_profile')->unique()->values()->all());
    }
}
