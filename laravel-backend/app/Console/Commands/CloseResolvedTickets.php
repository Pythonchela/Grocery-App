<?php

namespace App\Console\Commands;

use App\Services\SupportService;
use Illuminate\Console\Command;

class CloseResolvedTickets extends Command
{
    protected $signature = 'support:close-resolved';

    protected $description = 'Close resolved support tickets that nobody replied to for a few days';

    public function handle(SupportService $support): int
    {
        $count = $support->closeStaleResolved();

        if ($count > 0) {
            $this->info("Closed {$count} resolved ticket(s).");
        }

        return self::SUCCESS;
    }
}
