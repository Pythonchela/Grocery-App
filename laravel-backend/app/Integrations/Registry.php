<?php

namespace App\Integrations;

use App\Integrations\Testers\CourierTester;
use App\Integrations\Testers\EmailTester;
use App\Integrations\Testers\GeminiTester;
use App\Integrations\Testers\PushTester;
use App\Integrations\Testers\SmsTester;
use App\Integrations\Testers\StorageTester;
use Closure;

/**
 * Everything an admin may manage, and exactly what a valid value looks like.
 *
 * A PHP class rather than a config file on purpose: it names tester classes, and
 * anything non-scalar in a config file breaks `php artisan config:cache`.
 *
 * What is deliberately NOT here:
 *  - payment credentials (Razorpay keys, webhook secret, gateway and sandbox
 *    flags) — they stay in the server environment;
 *  - carrier `base_url`s — a base URL is where credentials get sent, so letting a
 *    stolen admin session change one would let it redirect them elsewhere;
 *  - APP_KEY, database, redis and domains — the application cannot start without
 *    them, so they cannot live in the database it would have to connect to.
 */
final class Registry
{
    /** The carriers the allocator knows about (config/delivery.php). */
    public const CARRIERS = ['porter', 'rapido', 'ola', 'shiprocket', 'delhivery'];

    /** @var list<Group>|null */
    private static ?array $groups = null;

    /** @return list<Group> */
    public static function groups(): array
    {
        return self::$groups ??= [
            self::gemini(),
            self::google(),
            self::push(),
            self::email(),
            self::sms(),
            self::storage(),
            self::couriers(),
            self::shipping(),
        ];
    }

    public static function group(string $id): ?Group
    {
        foreach (self::groups() as $group) {
            if ($group->id === $id) {
                return $group;
            }
        }

        return null;
    }

    /** @return list<Field> */
    public static function fields(): array
    {
        return array_merge(...array_map(fn (Group $g) => $g->fields, self::groups()));
    }

    public static function field(string $key): ?Field
    {
        foreach (self::fields() as $field) {
            if ($field->key() === $key) {
                return $field;
            }
        }

        return null;
    }

    // ── Groups ──────────────────────────────────────────────────────────

    private static function gemini(): Group
    {
        return new Group(
            'gemini',
            'Gemini AI',
            'Powers AI search, review summaries and smart product import. Without a key the app uses its built-in behaviour.',
            [
                new Field('gemini', 'api_key', 'API key', Field::SECRET, ['services.gemini.key'],
                    ['string', 'min:20', 'max:200', 'regex:/^\S+$/'],
                    'From Google AI Studio. Keep it private.', 'AIza…', env: 'GEMINI_API_KEY'),
            ],
            tester: GeminiTester::class,
        );
    }

    private static function push(): Group
    {
        return new Group(
            'push',
            'Push notifications',
            'Sends order and refund updates to shoppers\' phones through Firebase Cloud Messaging. Without it the app still shows every update inside the Notifications screen.',
            [
                new Field('push', 'service_account', 'Firebase service account (JSON)', Field::SECRET, ['services.fcm.service_account'],
                    [
                        'string', 'max:8000',
                        function (string $attribute, mixed $value, Closure $fail): void {
                            if (\App\Services\Push\FcmClient::parseServiceAccount((string) $value) === null) {
                                $fail('That is not a Firebase service account file. It must contain project_id, client_email and private_key.');
                            }
                        },
                    ],
                    'Firebase console > Project settings > Service accounts > Generate new private key. Paste the whole file.',
                    '{"type":"service_account", ...}', env: 'FCM_SERVICE_ACCOUNT'),
            ],
            tester: PushTester::class,
        );
    }

    private static function google(): Group
    {
        $clientId = ['string', 'max:200', 'regex:/^[0-9]+-[A-Za-z0-9_\-]+\.apps\.googleusercontent\.com$/'];

        return new Group(
            'google',
            'Google sign-in',
            'Lets shoppers sign in with their Google account. In Google Cloud (APIs & Services, Credentials) create a Web application client and an Android client for the app\'s package name and signing key, then paste the IDs here. They are public identifiers, not secrets, and the website and app pick them up within a minute with no rebuild.',
            [
                new Field('google', 'client_id', 'Web client ID', Field::TEXT, ['services.google.client_id'], $clientId,
                    'The Web application client. The website and the app both use it.', '1234-abc.apps.googleusercontent.com', env: 'GOOGLE_CLIENT_ID'),
                new Field('google', 'web_client_id', 'Web client ID (storefront)', Field::TEXT, ['services.google.web_client_id'], $clientId,
                    'Only if the storefront uses a different web client.', '', env: 'GOOGLE_WEB_CLIENT_ID'),
                new Field('google', 'android_client_id', 'Android client ID', Field::TEXT, ['services.google.android_client_id'], $clientId,
                    'The Android client for the app\'s package name and the SHA-1 of the key that signs it. Create one for the debug key and one for the release key.', '', env: 'GOOGLE_ANDROID_CLIENT_ID'),
                new Field('google', 'ios_client_id', 'iOS client ID', Field::TEXT, ['services.google.ios_client_id'], $clientId,
                    'Tied to the app\'s bundle ID.', '', env: 'GOOGLE_IOS_CLIENT_ID'),
            ],
        );
    }

    /**
     * A rule that refuses a host resolving to a private or reserved address. Mail
     * and storage endpoints are hosts an admin types in and the server then connects
     * to with credentials; see HostGuard.
     */
    private static function publicHost(bool $isUrl = false): Closure
    {
        return function (string $attribute, mixed $value, Closure $fail) use ($isUrl): void {
            $host = $isUrl ? parse_url((string) $value, PHP_URL_HOST) : (string) $value;

            if (! is_string($host) || ($problem = HostGuard::problem($host)) !== null) {
                $fail($problem ?? 'That does not look like a valid address.');
            }
        };
    }

    private static function email(): Group
    {
        return new Group(
            'email',
            'Email',
            'Order and account emails. Works with any SMTP provider (Amazon SES, Brevo, Mailgun, Resend, Gmail...). With the mailer set to Log nothing is sent.',
            [
                new Field('email', 'mailer', 'Mailer', Field::SELECT, ['mail.default'],
                    ['string', 'in:log,smtp'], 'Log writes emails to the server log instead of sending them.',
                    options: ['log', 'smtp'], env: 'MAIL_MAILER'),
                new Field('email', 'from_address', 'From address', Field::TEXT, ['mail.from.address'],
                    ['email', 'max:150'], 'Must be an address your provider has verified, or mail is rejected or lands in spam.',
                    'orders@yourshop.in', env: 'MAIL_FROM_ADDRESS'),
                new Field('email', 'from_name', 'From name', Field::TEXT, ['mail.from.name'],
                    ['string', 'max:80'], env: 'MAIL_FROM_NAME'),
                new Field('email', 'smtp_host', 'SMTP host', Field::TEXT, ['mail.mailers.smtp.host'],
                    ['string', 'max:200', 'regex:/^[A-Za-z0-9.\-]+$/', self::publicHost()],
                    'e.g. email-smtp.ap-south-1.amazonaws.com. Must be a public address.', 'smtp.provider.com', env: 'MAIL_HOST'),
                new Field('email', 'smtp_port', 'SMTP port', Field::NUMBER, ['mail.mailers.smtp.port'],
                    ['integer', 'between:1,65535'], '587 (STARTTLS) for most providers; 465 uses SSL automatically.',
                    cast: 'int', env: 'MAIL_PORT'),
                new Field('email', 'smtp_username', 'SMTP username', Field::TEXT, ['mail.mailers.smtp.username'],
                    ['string', 'max:200'], env: 'MAIL_USERNAME'),
                new Field('email', 'smtp_password', 'SMTP password', Field::SECRET, ['mail.mailers.smtp.password'],
                    ['string', 'min:1', 'max:300'], env: 'MAIL_PASSWORD'),
            ],
            together: [['smtp_username', 'smtp_password']],
            tester: EmailTester::class,
            requiredWhen: ['mailer' => ['smtp' => ['smtp_host', 'smtp_port', 'from_address']]],
        );
    }

    private static function sms(): Group
    {
        return new Group(
            'sms',
            'SMS & login OTP',
            'Sends the phone sign-in code, and optionally order updates. With no provider, sign-in by phone is switched off in production rather than pretending to send.',
            [
                new Field('sms', 'driver', 'SMS provider', Field::SELECT, ['messaging.sms.driver'],
                    ['string', 'in:log,msg91,twilio'], 'MSG91 suits Indian numbers (DLT templates); Twilio sends free text and works worldwide.',
                    options: ['log', 'msg91', 'twilio'], env: 'SMS_DRIVER'),
                new Field('sms', 'order_updates', 'Also text order updates', Field::SELECT, ['messaging.sms.order_updates'],
                    ['string', 'in:off,on'], 'Every text costs money, and on MSG91 each needs an approved template. The login code is always sent.',
                    options: ['off', 'on'], env: 'SMS_ORDER_UPDATES'),
                new Field('sms', 'msg91_authkey', 'MSG91 auth key', Field::SECRET, ['messaging.sms.msg91.authkey'],
                    ['string', 'min:10', 'max:200', 'regex:/^\S+$/'], env: 'MSG91_AUTHKEY'),
                new Field('sms', 'msg91_template_otp', 'MSG91 OTP template ID', Field::TEXT, ['messaging.sms.msg91.template_otp'],
                    ['string', 'max:60', 'regex:/^[A-Za-z0-9_\-]+$/'], 'The Flow template, approved on your DLT entity, with one variable named otp.', env: 'MSG91_TEMPLATE_OTP'),
                new Field('sms', 'msg91_template_order', 'MSG91 order template ID', Field::TEXT, ['messaging.sms.msg91.template_order'],
                    ['string', 'max:60', 'regex:/^[A-Za-z0-9_\-]+$/'], 'Only needed for order texts. One variable named message.', env: 'MSG91_TEMPLATE_ORDER'),
                new Field('sms', 'twilio_sid', 'Twilio account SID', Field::TEXT, ['messaging.sms.twilio.sid'],
                    ['string', 'regex:/^AC[0-9a-fA-F]{32}$/'], 'Starts with AC.', 'AC…', env: 'TWILIO_SID'),
                new Field('sms', 'twilio_token', 'Twilio auth token', Field::SECRET, ['messaging.sms.twilio.token'],
                    ['string', 'min:16', 'max:100', 'regex:/^\S+$/'], env: 'TWILIO_TOKEN'),
                new Field('sms', 'twilio_from', 'Twilio sender', Field::TEXT, ['messaging.sms.twilio.from'],
                    ['string', 'regex:/^(\+[0-9]{8,15}|MG[0-9a-fA-F]{32})$/'], 'A number like +14155550123, or a Messaging Service SID (starts with MG).', env: 'TWILIO_FROM'),
            ],
            tester: SmsTester::class,
            requiredWhen: [
                'driver' => [
                    'msg91' => ['msg91_authkey', 'msg91_template_otp'],
                    'twilio' => ['twilio_sid', 'twilio_token', 'twilio_from'],
                ],
            ],
        );
    }

    private static function storage(): Group
    {
        $bucket = ['string', 'min:3', 'max:63', 'regex:/^[a-z0-9][a-z0-9.\-]+[a-z0-9]$/'];

        return new Group(
            'storage',
            'Image & file storage',
            'Where uploaded product images and seller documents are kept. On the server disk they are lost if you ever move servers; in a bucket they are not. Works with Amazon S3 and any S3-compatible service (Cloudflare R2, Backblaze B2, DigitalOcean Spaces...).',
            [
                new Field('storage', 'driver', 'Storage', Field::SELECT,
                    ['filesystems.disks.media.driver', 'filesystems.disks.private.driver'],
                    ['string', 'in:local,s3'], 'Switching only affects NEW uploads. Use the media:migrate command to move existing files.',
                    options: ['local', 's3'], env: 'STORAGE_DRIVER'),
                new Field('storage', 'bucket', 'Public bucket', Field::TEXT, ['filesystems.disks.media.bucket'],
                    $bucket, 'Holds product images. It must allow public reads (through a public bucket policy, r2.dev or a CDN).', env: 'AWS_BUCKET'),
                new Field('storage', 'private_bucket', 'Private bucket', Field::TEXT, ['filesystems.disks.private.bucket'],
                    $bucket, 'Holds seller KYC documents. A DIFFERENT bucket from the public one, and it must NOT allow public reads.', env: 'AWS_PRIVATE_BUCKET'),
                new Field('storage', 'public_url', 'Public URL', Field::TEXT, ['filesystems.disks.media.public_url'],
                    ['url:https', 'max:200'], 'The address images are served from, e.g. https://cdn.yourshop.in', env: 'AWS_URL'),
                new Field('storage', 'region', 'Region', Field::TEXT,
                    ['filesystems.disks.media.region', 'filesystems.disks.private.region'],
                    ['string', 'max:40', 'regex:/^[a-z0-9\-]+$/'], 'e.g. ap-south-1. Use auto for Cloudflare R2.', 'ap-south-1', env: 'AWS_DEFAULT_REGION'),
                new Field('storage', 'endpoint', 'Endpoint', Field::TEXT,
                    ['filesystems.disks.media.endpoint', 'filesystems.disks.private.endpoint'],
                    ['url:https', 'max:200', self::publicHost(true)], 'Leave empty for Amazon S3. For R2: https://<account-id>.r2.cloudflarestorage.com', env: 'AWS_ENDPOINT'),
                new Field('storage', 'access_key', 'Access key ID', Field::SECRET,
                    ['filesystems.disks.media.key', 'filesystems.disks.private.key'],
                    ['string', 'min:8', 'max:200', 'regex:/^\S+$/'], env: 'AWS_ACCESS_KEY_ID'),
                new Field('storage', 'secret_key', 'Secret access key', Field::SECRET,
                    ['filesystems.disks.media.secret', 'filesystems.disks.private.secret'],
                    ['string', 'min:16', 'max:200', 'regex:/^\S+$/'], env: 'AWS_SECRET_ACCESS_KEY'),
            ],
            together: [['access_key', 'secret_key']],
            tester: StorageTester::class,
            requiredWhen: ['driver' => ['s3' => ['bucket', 'private_bucket', 'public_url', 'region', 'access_key', 'secret_key']]],
            // Seller identity documents in a bucket that allows public reads would be a
            // breach waiting for a guessable URL.
            distinct: [['bucket', 'private_bucket']],
        );
    }

    private static function couriers(): Group
    {
        $token = ['string', 'min:8', 'max:300', 'regex:/^\S+$/'];
        $id = ['string', 'max:150', 'regex:/^\S+$/'];

        return new Group(
            'couriers',
            'Delivery partners',
            'Credentials for each courier. A courier with no credentials quotes in sandbox mode and ships nothing.',
            [
                new Field('couriers', 'enabled', 'Couriers to offer', Field::LIST, ['delivery.enabled'],
                    ['array', 'min:1'], 'Shoppers are only quoted these.', options: self::CARRIERS, cast: 'list', env: 'DELIVERY_CARRIERS'),

                new Field('couriers', 'shiprocket_email', 'Shiprocket email', Field::TEXT, ['delivery.carriers.shiprocket.email'],
                    ['email', 'max:150'], 'The API user\'s login email.', env: 'SHIPROCKET_EMAIL'),
                new Field('couriers', 'shiprocket_password', 'Shiprocket password', Field::SECRET, ['delivery.carriers.shiprocket.password'],
                    ['string', 'min:6', 'max:200'], 'The API user\'s password.', env: 'SHIPROCKET_PASSWORD'),
                new Field('couriers', 'shiprocket_pickup_location', 'Shiprocket pickup location', Field::TEXT, ['delivery.carriers.shiprocket.pickup_location'],
                    ['string', 'max:80'], 'The pickup location name as set up in Shiprocket.', 'Primary', env: 'SHIPROCKET_PICKUP_LOCATION'),

                new Field('couriers', 'delhivery_api_token', 'Delhivery API token', Field::SECRET, ['delivery.carriers.delhivery.api_token'],
                    $token, env: 'DELHIVERY_API_TOKEN'),
                new Field('couriers', 'delhivery_client_name', 'Delhivery client name', Field::TEXT, ['delivery.carriers.delhivery.client_name'],
                    ['string', 'max:80'], env: 'DELHIVERY_CLIENT_NAME'),

                new Field('couriers', 'ola_client_id', 'Ola client ID', Field::TEXT, ['delivery.carriers.ola.client_id'], $id, env: 'OLA_CLIENT_ID'),
                new Field('couriers', 'ola_client_secret', 'Ola client secret', Field::SECRET, ['delivery.carriers.ola.client_secret'], $token, env: 'OLA_CLIENT_SECRET'),

                new Field('couriers', 'rapido_client_id', 'Rapido client ID', Field::TEXT, ['delivery.carriers.rapido.client_id'], $id, env: 'RAPIDO_CLIENT_ID'),
                new Field('couriers', 'rapido_client_secret', 'Rapido client secret', Field::SECRET, ['delivery.carriers.rapido.client_secret'], $token, env: 'RAPIDO_CLIENT_SECRET'),

                new Field('couriers', 'porter_api_key', 'Porter API key', Field::SECRET, ['delivery.carriers.porter.api_key'], $token, env: 'PORTER_API_KEY'),
            ],
            together: [
                ['shiprocket_email', 'shiprocket_password'],
                ['ola_client_id', 'ola_client_secret'],
                ['rapido_client_id', 'rapido_client_secret'],
            ],
            tester: CourierTester::class,
        );
    }

    private static function shipping(): Group
    {
        return new Group(
            'shipping',
            'Shipping & pickup',
            'Where orders ship from, and the shipping rules shoppers see.',
            [
                new Field('shipping', 'pickup_name', 'Pickup name', Field::TEXT, ['delivery.pickup_address.name'], ['string', 'max:120'], env: 'DELIVERY_PICKUP_NAME'),
                new Field('shipping', 'pickup_phone', 'Pickup phone', Field::TEXT, ['delivery.pickup_address.phone'], ['string', 'regex:/^[0-9+\-\s]{7,20}$/'], env: 'DELIVERY_PICKUP_PHONE'),
                new Field('shipping', 'pickup_line1', 'Pickup address', Field::TEXT, ['delivery.pickup_address.line1'], ['string', 'max:200'], env: 'DELIVERY_PICKUP_LINE1'),
                new Field('shipping', 'pickup_city', 'City', Field::TEXT, ['delivery.pickup_address.city'], ['string', 'max:80'], env: 'DELIVERY_PICKUP_CITY'),
                new Field('shipping', 'pickup_state', 'State', Field::TEXT, ['delivery.pickup_address.state'], ['string', 'max:80'], env: 'DELIVERY_PICKUP_STATE'),
                new Field('shipping', 'pickup_pincode', 'PIN code', Field::TEXT,
                    ['delivery.pickup_address.pincode', 'delivery.pickup_pincode'],
                    ['string', 'regex:/^[1-9][0-9]{5}$/'], 'Intracity rules are decided against this.', env: 'DELIVERY_PICKUP_PINCODE'),
                new Field('shipping', 'pickup_lat', 'Latitude', Field::NUMBER, ['delivery.pickup_address.lat'],
                    ['numeric', 'between:-90,90'], cast: 'float', env: 'DELIVERY_PICKUP_LAT'),
                new Field('shipping', 'pickup_lng', 'Longitude', Field::NUMBER, ['delivery.pickup_address.lng'],
                    ['numeric', 'between:-180,180'], cast: 'float', env: 'DELIVERY_PICKUP_LNG'),
                new Field('shipping', 'auto_book', 'Book couriers automatically', Field::SELECT, ['delivery.auto_book'],
                    ['string', 'in:on,off'], 'On: marking an order shipped books the courier for the seller, and the carrier charges for it. Off: sellers type the courier and tracking number themselves.',
                    options: ['on', 'off'], env: 'DELIVERY_AUTO_BOOK'),
                new Field('shipping', 'free_above', 'Free shipping above (₹)', Field::NUMBER, ['delivery.free_above'],
                    ['integer', 'between:0,1000000'], 'Applied after discounts.', cast: 'int', env: 'DELIVERY_FREE_ABOVE'),
                new Field('shipping', 'default_item_weight_grams', 'Default item weight (g)', Field::NUMBER, ['delivery.default_item_weight_grams'],
                    ['integer', 'between:1,100000'], 'Used when a product has no weight. Err high.', cast: 'int', env: 'DELIVERY_DEFAULT_ITEM_WEIGHT_G'),
            ],
        );
    }

}
