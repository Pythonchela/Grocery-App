<?php

return [

    /*
    |--------------------------------------------------------------------------
    | The clock the shop's opening hours are written in
    |--------------------------------------------------------------------------
    */

    'timezone' => env('MARKETPLACE_TIMEZONE', 'Asia/Kolkata'),

    /*
    |--------------------------------------------------------------------------
    | Minutes the shop has to confirm a new order
    |--------------------------------------------------------------------------
    |
    | Only matters if the shop is set to confirm each order by hand (it takes
    | orders automatically by default). An order nobody answers in time is
    | cancelled and the customer refunded.
    */

    'accept_window_minutes' => (int) env('MARKETPLACE_ACCEPT_WINDOW', 15),
];
