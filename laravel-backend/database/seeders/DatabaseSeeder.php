<?php

namespace Database\Seeders;

use App\Models\Category;
use App\Models\Coupon;
use App\Models\Order;
use App\Models\Product;
use App\Models\Review;
use App\Models\User;
use App\Models\WalletTransaction;
use Illuminate\Database\Console\Seeds\WithoutModelEvents;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;

class DatabaseSeeder extends Seeder
{
    use WithoutModelEvents;

    public function run(): void
    {
        // This seeder creates admin accounts with passwords that are published in
        // the README, and updateOrCreate() resets them on every run. On a live site
        // that is an open door, so it refuses to run there. Set DEMO_SEED_CONFIRM=yes
        // only for a throwaway production-like environment.
        if (app()->environment('production') && env('DEMO_SEED_CONFIRM') !== 'yes') {
            throw new \RuntimeException(
                'Refusing to run the demo seeder in production: it creates admin logins with published passwords. '
                .'Create your first admin with `php artisan haatvia:admin` instead.'
            );
        }

        // ── Users ────────────────────────────────────────────────────────
        // No published password: use DEMO_ADMIN_PASSWORD, or a random one shown once.
        $demoPassword = env('DEMO_ADMIN_PASSWORD') ?: \Illuminate\Support\Str::password(20, symbols: false);
        $this->command?->info('Demo admin admin@haatvia.test, password: '.$demoPassword);

        $admin1 = User::updateOrCreate(
            ['email' => 'admin@haatvia.test'],
            [
                'name' => 'Haatvia Admin',
                'password' => Hash::make($demoPassword),
                'role' => 'ADMIN',
                'status' => 'ACTIVE',
            ]
        );

        $admin2 = User::updateOrCreate(
            ['email' => 'admin@example.com'],
            [
                'name' => 'Store Admin',
                'password' => Hash::make('AdminPassword123!'),
                'role' => 'ADMIN',
                'status' => 'ACTIVE',
            ]
        );

        $customer = User::updateOrCreate(
            ['email' => 'priya.sharma@example.com'],
            [
                'name' => 'Priya Sharma',
                'phone' => '+919899911223',
                'password' => Hash::make('Password@123'),
                'role' => 'CUSTOMER',
                'status' => 'ACTIVE',
            ]
        );

        // ── Catalogue ────────────────────────────────────────────────────
        // This app's own sample categories and items; see StarterCatalogSeeder.
        $this->call(StarterCatalogSeeder::class);

        // ── Coupons ──────────────────────────────────────────────────────
        Coupon::updateOrCreate(
            ['code' => 'BHARAT15'],
            [
                'description' => '15% off on food & grocery',
                'type' => 'PERCENT',
                'value' => 15,
                'min_order' => 299,
                'max_discount' => 100,
                'usage_limit' => 1000,
                'per_user_limit' => 3,
                'target_type' => 'ALL',
                'expires_at' => now()->addMonths(3),
                'is_active' => true,
            ]
        );
    }
}
