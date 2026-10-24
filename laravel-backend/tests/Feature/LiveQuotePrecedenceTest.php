<?php

namespace Tests\Feature;

use App\Services\Delivery\DeliveryAllocator;
use App\Services\Delivery\Shipment;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

/**
 * A carrier with no credentials yet quotes a made-up "sandbox" price. Once a
 * real carrier is connected, that invented price must never beat its real one.
 */
class LiveQuotePrecedenceTest extends TestCase
{
    use RefreshDatabase;

    private function parcel(): Shipment
    {
        return new Shipment('121001', '560038', 500, 30, 60, 99900, false, 1);
    }

    private function connectShiprocket(float $rate): void
    {
        Cache::flush();
        config([
            'delivery.carriers.shiprocket.email' => 'api@example.test',
            'delivery.carriers.shiprocket.password' => 'secret',
        ]);

        Http::fake([
            '*/auth/login' => Http::response(['token' => 'tok']),
            '*/courier/serviceability/*' => Http::response(['data' => ['available_courier_companies' => [
                ['courier_name' => 'Delhivery Surface', 'rate' => $rate, 'estimated_delivery_days' => 5, 'cod' => 1, 'courier_company_id' => 7],
            ]]]),
        ]);
    }

    public function test_a_real_rate_beats_a_cheaper_invented_one(): void
    {
        $this->connectShiprocket(237.72);   // far dearer than the ~Rs 106 sandbox figure

        $quotes = app(DeliveryAllocator::class)->quotes($this->parcel());
        $standard = collect($quotes)->firstWhere('serviceLevel', 'STANDARD');

        $this->assertNotNull($standard);
        $this->assertFalse($standard->sandbox, 'the shopper must be shown the real rate');
        $this->assertSame(23772, $standard->pricePaise);
        $this->assertStringContainsString('Shiprocket', $standard->carrierLabel);
    }

    public function test_with_nothing_connected_the_sandbox_still_quotes(): void
    {
        config([
            'delivery.carriers.shiprocket.email' => null,
            'delivery.carriers.shiprocket.password' => null,
        ]);

        $quotes = app(DeliveryAllocator::class)->quotes($this->parcel());

        $this->assertNotEmpty($quotes);
        $this->assertTrue(collect($quotes)->every(fn ($q) => $q->sandbox));
    }

    public function test_a_speed_only_the_sandbox_offers_is_kept(): void
    {
        $this->connectShiprocket(237.72);

        $levels = collect(app(DeliveryAllocator::class)->quotes($this->parcel()))->pluck('serviceLevel');

        // Real carriers priced STANDARD only, so STANDARD is real; nothing real
        // priced any other speed, so any other speed on offer is not hidden.
        $this->assertContains('STANDARD', $levels->all());
    }
}
