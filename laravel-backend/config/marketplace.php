<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Default commission rate
    |--------------------------------------------------------------------------
    |
    | Percent of each sale the platform keeps from a newly onboarded seller.
    | Applies at application time only — an individual seller's rate is
    | negotiable afterwards from the admin area, and every order line snapshots
    | the rate it was sold under, so changing this never rewrites history.
    |
    */

    'default_commission_rate' => (float) env('MARKETPLACE_DEFAULT_COMMISSION', 10),

    /*
    |--------------------------------------------------------------------------
    | Review turnaround
    |--------------------------------------------------------------------------
    |
    | Advertised to applicants after they submit. Copy only — nothing enforces
    | it, so keep it honest.
    |
    */

    'review_turnaround_days' => (int) env('MARKETPLACE_REVIEW_DAYS', 2),

    /*
    |--------------------------------------------------------------------------
    | Store mode
    |--------------------------------------------------------------------------
    |
    | single : one business selling its own goods; no vendors.
    | hybrid : the owner's shop sells next to approved vendors.
    | multi  : vendors only; the owner's own shop is hidden from shoppers.
    |
    | Admin can change it in Integrations. See App\Support\StoreMode.
    |
    */

    'mode' => env('MARKETPLACE_MODE', 'hybrid'),

    /*
    | one_shop : a basket holds one shop's goods at a time (food and grocery apps).
    | mixed    : a basket may hold several shops' goods.
    */

    'cart_rule' => env('MARKETPLACE_CART_RULE', 'one_shop'),

    /*
    | What the home page leads with, in a store that has shops.
    |
    | auto     : a vendors-only store opens on its shops; any other shows a row of
    |            shops among the products.
    | products : the home lists products directly, with no shops on it. Shops stay
    |            one tap away on their own page.
    | shops    : the home opens on the shops, whatever the store type.
    */

    'home_layout' => env('MARKETPLACE_HOME_LAYOUT', 'auto'),

    /*
    | The clock shops' opening hours are written in.
    */

    'timezone' => env('MARKETPLACE_TIMEZONE', 'Asia/Kolkata'),

    /*
    | Minutes a shop that confirms orders by hand has to answer a new order.
    | After that the order line is turned down and the customer refunded.
    */

    'accept_window_minutes' => (int) env('MARKETPLACE_ACCEPT_WINDOW', 15),

    /*
    | Deductions from a seller's sale, besides the commission, as percentages.
    | All zero until the business sets them. The statements show them line by
    | line; they are estimates from the rates set here, not tax advice.
    |
    |  commission_gst_percent : GST charged on the commission (18 is usual)
    |  tcs_percent            : tax collected at source, on what the seller sold
    |  tds_percent            : tax deducted at source, on what the seller sold
    */

    'commission_gst_percent' => (float) env('MARKETPLACE_COMMISSION_GST', 0),
    'tcs_percent' => (float) env('MARKETPLACE_TCS', 0),
    'tds_percent' => (float) env('MARKETPLACE_TDS', 0),

    /*
    | Smallest amount (₹) a seller may ask to be paid out at once.
    */

    'min_payout_amount' => (float) env('MARKETPLACE_MIN_PAYOUT', 100),

];
