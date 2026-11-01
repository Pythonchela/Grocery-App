<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Third Party Services
    |--------------------------------------------------------------------------
    |
    | This file is for storing the credentials for third party services such
    | as Mailgun, Postmark, AWS and more. This file provides the de facto
    | location for this type of information, allowing packages to have
    | a conventional file to locate the various service credentials.
    |
    */

    'postmark' => [
        'key' => env('POSTMARK_API_KEY'),
    ],

    /*
    | Google Sign-In. Every platform gets its own OAuth client id from the
    | Google Cloud console — Android is keyed to the signing certificate's
    | SHA-1, iOS to the bundle id, web to the origin — and a token minted for
    | any one of them must be accepted here, so all four are audiences.
    |
    | The `client_id` (a Web client) is what the Android app requests an ID
    | token *for*; without it google_sign_in returns an access token only and
    | the server has nothing to verify.
    */
    'google' => [
        'client_id' => env('GOOGLE_CLIENT_ID'),
        'android_client_id' => env('GOOGLE_ANDROID_CLIENT_ID'),
        'ios_client_id' => env('GOOGLE_IOS_CLIENT_ID'),
        'web_client_id' => env('GOOGLE_WEB_CLIENT_ID'),
    ],

    /*
    | Razorpay. With both keys set the app charges through Razorpay; with
    | either missing it falls back to the sandbox gateway that moves no money.
    | `rzp_test_…` keys are Test Mode, `rzp_live_…` keys take real payments.
    */
    'razorpay' => [
        'key_id' => env('RAZORPAY_KEY_ID'),
        'key_secret' => env('RAZORPAY_KEY_SECRET'),
        'webhook_secret' => env('RAZORPAY_WEBHOOK_SECRET'),
    ],

    /*
    | Gemini powers AI search intent, review summaries and smart product import.
    | The code reads `services.gemini.key`, but this block did not exist, so the
    | key could never be picked up — everything silently ran in its mock mode.
    */
    'gemini' => [
        'key' => env('GEMINI_API_KEY'),
        // Left empty, the newest flash model the key can see is used (see GeminiClient).
        'model' => env('GEMINI_MODEL'),
    ],

    /*
    | Firebase Cloud Messaging for push notifications. The value is the whole
    | service-account JSON document; push stays off while it is empty.
    */
    'fcm' => [
        'service_account' => env('FCM_SERVICE_ACCOUNT'),
    ],

    'resend' => [
        'key' => env('RESEND_API_KEY'),
    ],

    'ses' => [
        'key' => env('AWS_ACCESS_KEY_ID'),
        'secret' => env('AWS_SECRET_ACCESS_KEY'),
        'region' => env('AWS_DEFAULT_REGION', 'us-east-1'),
    ],

    'slack' => [
        'notifications' => [
            'bot_user_oauth_token' => env('SLACK_BOT_USER_OAUTH_TOKEN'),
            'channel' => env('SLACK_BOT_USER_DEFAULT_CHANNEL'),
        ],
    ],

];
