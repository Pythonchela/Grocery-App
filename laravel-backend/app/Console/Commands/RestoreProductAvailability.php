<?php

namespace App\Console\Commands;

use App\Models\Product;
use Illuminate\Console\Command;

class RestoreProductAvailability extends Command
{
    protected $signature = 'catalog:restore-availability';

    protected $description = 'Switch items back on once their "unavailable until" time has passed';

    public function handle(): int
    {
        $count = Product::where('status', 'OUT_OF_STOCK')
            ->whereNotNull('available_again_at')
            ->where('available_again_at', '<=', now())
            ->update(['status' => 'ACTIVE', 'available_again_at' => null]);

        if ($count > 0) {
            $this->info("Switched {$count} item(s) back on.");
        }

        return self::SUCCESS;
    }
}
