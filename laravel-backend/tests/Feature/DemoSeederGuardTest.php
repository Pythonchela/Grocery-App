<?php

namespace Tests\Feature;

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

        $this->assertSame(0, User::where('email', 'admin@bazaarx.com')->count());
        $this->assertSame(0, User::where('email', 'admin@example.com')->count());
    }
}
