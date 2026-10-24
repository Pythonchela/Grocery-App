<?php

use Illuminate\Foundation\Inspiring;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Schedule;

// Paid but never ordered → refunded. Needs `php artisan schedule:run` every minute.
Schedule::command('payments:refund-unclaimed')->everyTenMinutes()->withoutOverlapping();

// Orders a shop never answered are turned down; items switched off "until 6pm" come back.
Schedule::command('catalog:restore-availability')->everyMinute()->withoutOverlapping();

// Resolved support tickets nobody replied to close by themselves.
Schedule::command('support:close-resolved')->daily();

Artisan::command('inspire', function () {
    $this->comment(Inspiring::quote());
})->purpose('Display an inspiring quote');
