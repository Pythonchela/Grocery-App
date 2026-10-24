<?php

return [

    /*
    |--------------------------------------------------------------------------
    | First-response targets
    |--------------------------------------------------------------------------
    |
    | Hours within which the team should first answer a ticket, by priority. A
    | ticket not answered by then is flagged overdue on the support inbox.
    |
    */

    'first_response_hours' => [
        'URGENT' => (int) env('SUPPORT_SLA_URGENT', 2),
        'HIGH' => (int) env('SUPPORT_SLA_HIGH', 8),
        'NORMAL' => (int) env('SUPPORT_SLA_NORMAL', 24),
        'LOW' => (int) env('SUPPORT_SLA_LOW', 48),
    ],

    /*
    | Days a resolved ticket waits for a reply before it closes by itself.
    */

    'auto_close_days' => (int) env('SUPPORT_AUTO_CLOSE_DAYS', 7),

];
