<?php

namespace App\Console\Commands;

use App\Services\SellerOrderDesk;
use Illuminate\Console\Command;

class ExpireUnacceptedOrders extends Command
{
    protected $signature = 'orders:expire-unaccepted';

    protected $description = 'Turn down order lines a shop did not accept in time, and refund the customer';

    public function handle(SellerOrderDesk $desk): int
    {
        $count = $desk->expireUnanswered();

        if ($count > 0) {
            $this->info("Turned down {$count} unanswered order line(s).");
        }

        return self::SUCCESS;
    }
}
