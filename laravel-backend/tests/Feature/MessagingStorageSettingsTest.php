<?php

namespace Tests\Feature;

use App\Integrations\IntegrationSettings;
use App\Integrations\Registry;
use App\Models\IntegrationAuditLog;
use App\Models\IntegrationSetting;
use App\Models\User;
use Illuminate\Console\Events\CommandStarting;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Event;
use Illuminate\Support\Facades\Http;
use PHPUnit\Framework\Attributes\DataProvider;
use Symfony\Component\Console\Input\ArrayInput;
use Symfony\Component\Console\Output\NullOutput;
use Tests\TestCase;

/**
 * Email, SMS and storage managed from the admin panel: what can be saved, what is
 * refused, what takes effect, and that no credential ever comes back out.
 */
class MessagingStorageSettingsTest extends TestCase
{
    use RefreshDatabase;

    private const PASSWORD = 'correct-horse-battery';

    private const SMTP_PASSWORD = 'smtp-Secret-Pass-4471';

    private const MSG91_KEY = 'msg91-auth-key-0123456789';

    private const TWILIO_TOKEN = 'twilio-token-0123456789abcdef';

    private const ACCESS_KEY = 'AKIAEXAMPLEKEY123456';

    private const SECRET_KEY = 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY';

    private function admin(): User
    {
        return User::factory()->create(['role' => User::ROLE_ADMIN, 'password' => self::PASSWORD]);
    }

    private function save(User $as, string $group, array $values)
    {
        return $this->actingAs($as, 'sanctum')->putJson("/api/v1/admin/integrations/{$group}", [
            'current_password' => self::PASSWORD,
            'values' => $values,
        ]);
    }

    private function smtp(array $over = []): array
    {
        return array_merge([
            'mailer' => 'smtp', 'from_address' => 'orders@shop.in', 'smtp_host' => '8.8.8.8',
            'smtp_port' => 587, 'smtp_username' => 'apikey', 'smtp_password' => self::SMTP_PASSWORD,
        ], $over);
    }

    private function s3(array $over = []): array
    {
        return array_merge([
            'driver' => 's3', 'bucket' => 'shop-media',
            'public_url' => 'https://cdn.shop.in', 'region' => 'ap-south-1',
            'access_key' => self::ACCESS_KEY, 'secret_key' => self::SECRET_KEY,
        ], $over);
    }

    // ── Email ───────────────────────────────────────────────────────────

    public function test_smtp_settings_are_saved_and_take_effect(): void
    {
        $this->save($this->admin(), 'email', $this->smtp())->assertOk();

        $this->assertSame('smtp', config('mail.default'));
        $this->assertSame('8.8.8.8', config('mail.mailers.smtp.host'));
        $this->assertSame(587, config('mail.mailers.smtp.port'));
        $this->assertSame('orders@shop.in', config('mail.from.address'));
        $this->assertSame(self::SMTP_PASSWORD, config('mail.mailers.smtp.password'));
    }

    public function test_the_mailer_is_rebuilt_after_a_change_so_the_old_credentials_are_not_kept(): void
    {
        $admin = $this->admin();
        $before = app('mail.manager');

        $this->save($admin, 'email', $this->smtp())->assertOk();

        $this->assertNotSame($before, app('mail.manager'));
    }

    public function test_choosing_smtp_requires_what_smtp_needs(): void
    {
        $this->save($this->admin(), 'email', ['mailer' => 'smtp'])
            ->assertStatus(422)
            ->assertJsonValidationErrors(['values.smtp_host', 'values.from_address']);

        $this->assertSame(0, IntegrationSetting::count());
    }

    public function test_the_log_mailer_needs_nothing(): void
    {
        $this->save($this->admin(), 'email', ['mailer' => 'log'])->assertOk();
    }

    public function test_an_unrelated_edit_is_not_blocked_by_an_old_half_configured_choice(): void
    {
        $admin = $this->admin();
        config(['mail.default' => 'smtp', 'mail.mailers.smtp.host' => null]);

        $this->save($admin, 'email', ['from_name' => 'The Shop'])->assertOk();
    }

    public function test_the_username_and_password_come_as_a_pair(): void
    {
        $this->save($this->admin(), 'email', $this->smtp(['smtp_password' => '']))
            ->assertStatus(422)->assertJsonValidationErrors('values.smtp_password');
    }

    #[DataProvider('privateHosts')]
    public function test_an_smtp_host_on_a_private_network_is_refused(string $host): void
    {
        $this->save($this->admin(), 'email', $this->smtp(['smtp_host' => $host]))
            ->assertStatus(422)->assertJsonValidationErrors('values.smtp_host');

        $this->assertSame(0, IntegrationSetting::count());
    }

    public static function privateHosts(): array
    {
        return [['127.0.0.1'], ['localhost'], ['10.1.2.3'], ['192.168.0.9'], ['169.254.169.254'], ['not a host'], ['smtp.example.com/x']];
    }

    public function test_the_mailer_must_be_one_we_know(): void
    {
        $this->save($this->admin(), 'email', ['mailer' => 'sendmail'])->assertStatus(422)->assertJsonValidationErrors('values.mailer');
    }

    public function test_the_smtp_password_is_never_returned_or_audited(): void
    {
        $admin = $this->admin();
        $put = $this->save($admin, 'email', $this->smtp())->assertOk()->getContent();
        $get = $this->actingAs($admin, 'sanctum')->getJson('/api/v1/admin/integrations')->getContent();
        $audit = $this->actingAs($admin, 'sanctum')->getJson('/api/v1/admin/integrations/audit')->getContent();

        foreach ([$put, $get, $audit, json_encode(IntegrationAuditLog::all())] as $body) {
            $this->assertStringNotContainsString(self::SMTP_PASSWORD, $body);
        }
    }

    public function test_an_email_test_with_the_log_mailer_sends_nothing(): void
    {
        $this->actingAs($this->admin(), 'sanctum')->postJson('/api/v1/admin/integrations/email/test', ['values' => ['mailer' => 'log']])
            ->assertOk()->assertJsonPath('data.status', 'unavailable');
    }

    public function test_an_email_test_to_a_private_host_is_refused_before_connecting(): void
    {
        // The same rule as saving applies to a test: the form's host is validated first.
        $this->actingAs($this->admin(), 'sanctum')->postJson('/api/v1/admin/integrations/email/test', [
            'values' => $this->smtp(['smtp_host' => '127.0.0.1']),
        ])->assertStatus(422)->assertJsonValidationErrors('values.smtp_host');

        // And the tester re-checks on its own, in case it is ever called another way.
        $result = (new \App\Integrations\Testers\EmailTester)->test($this->smtp(['smtp_host' => '10.0.0.5']), 'admin@shop.in');
        $this->assertSame('failed', $result->status);
        $this->assertStringContainsString('private', $result->message);
    }

    public function test_an_email_test_failure_never_echoes_the_password(): void
    {
        // The operator switch lets the test reach a closed local port, so this
        // really does attempt a connection and really does fail.
        config(['integrations.allow_private_hosts' => true]);

        $response = $this->actingAs($this->admin(), 'sanctum')->postJson('/api/v1/admin/integrations/email/test', [
            'values' => $this->smtp(['smtp_host' => '127.0.0.1', 'smtp_port' => 1]),
        ])->assertOk()->assertJsonPath('data.status', 'failed');

        $this->assertStringNotContainsString(self::SMTP_PASSWORD, $response->getContent());
    }

    public function test_the_email_test_always_goes_to_the_admin_not_to_anyone_named_in_the_request(): void
    {
        $tester = new \App\Integrations\Testers\EmailTester;

        $result = $tester->test($this->smtp(), 'not-an-email');

        $this->assertSame('incomplete', $result->status);
    }

    // ── SMS ─────────────────────────────────────────────────────────────

    public function test_choosing_msg91_requires_its_key_and_template(): void
    {
        $this->save($this->admin(), 'sms', ['driver' => 'msg91'])
            ->assertStatus(422)
            ->assertJsonValidationErrors(['values.msg91_authkey', 'values.msg91_template_otp']);
    }

    public function test_choosing_twilio_requires_all_three(): void
    {
        $this->save($this->admin(), 'sms', ['driver' => 'twilio'])
            ->assertStatus(422)
            ->assertJsonValidationErrors(['values.twilio_sid', 'values.twilio_token', 'values.twilio_from']);
    }

    public function test_sms_settings_take_effect_for_the_next_message(): void
    {
        Http::fake(['control.msg91.com/*' => Http::response(['type' => 'success'])]);

        $this->save($this->admin(), 'sms', [
            'driver' => 'msg91', 'msg91_authkey' => self::MSG91_KEY, 'msg91_template_otp' => 'tpl_otp_9',
        ])->assertOk();

        $this->postJson('/api/v1/auth/otp/send', ['phone' => '9876543210'])->assertOk();

        Http::assertSent(fn ($r) => $r->hasHeader('authkey', self::MSG91_KEY) && $r['template_id'] === 'tpl_otp_9');
    }

    public function test_sms_values_are_validated(): void
    {
        $admin = $this->admin();

        $this->save($admin, 'sms', ['driver' => 'carrier-pigeon'])->assertStatus(422);
        $this->save($admin, 'sms', ['twilio_sid' => 'not-a-sid'])->assertStatus(422)->assertJsonValidationErrors('values.twilio_sid');
        $this->save($admin, 'sms', ['twilio_from' => '12345'])->assertStatus(422)->assertJsonValidationErrors('values.twilio_from');
        $this->save($admin, 'sms', ['msg91_template_otp' => 'has space'])->assertStatus(422);
        $this->save($admin, 'sms', ['order_updates' => 'maybe'])->assertStatus(422);
    }

    public function test_sms_secrets_are_never_returned_or_audited(): void
    {
        $admin = $this->admin();
        $this->save($admin, 'sms', ['driver' => 'msg91', 'msg91_authkey' => self::MSG91_KEY, 'msg91_template_otp' => 'tpl_1'])->assertOk();
        $this->save($admin, 'sms', ['twilio_token' => self::TWILIO_TOKEN])->assertOk();

        $all = $this->actingAs($admin, 'sanctum')->getJson('/api/v1/admin/integrations')->getContent()
            .$this->actingAs($admin, 'sanctum')->getJson('/api/v1/admin/integrations/audit')->getContent()
            .json_encode(IntegrationAuditLog::all());

        $this->assertStringNotContainsString(self::MSG91_KEY, $all);
        $this->assertStringNotContainsString(self::TWILIO_TOKEN, $all);
    }

    public function test_an_sms_test_sends_through_the_form_values_without_saving_them(): void
    {
        Http::fake(['control.msg91.com/*' => Http::response(['type' => 'success'])]);

        $this->actingAs($this->admin(), 'sanctum')->postJson('/api/v1/admin/integrations/sms/test', [
            'target' => '9876543210',
            'values' => ['driver' => 'msg91', 'msg91_authkey' => self::MSG91_KEY, 'msg91_template_otp' => 'tpl_otp_9'],
        ])->assertOk()->assertJsonPath('data.status', 'ok');

        Http::assertSent(fn ($r) => $r['recipients'][0]['mobiles'] === '919876543210' && $r->hasHeader('authkey', self::MSG91_KEY));
        $this->assertSame(0, IntegrationSetting::count());
    }

    public function test_an_sms_test_needs_a_ten_digit_number_and_a_real_provider(): void
    {
        Http::fake();
        $admin = $this->admin();
        $values = ['driver' => 'msg91', 'msg91_authkey' => self::MSG91_KEY, 'msg91_template_otp' => 'tpl_1'];

        foreach (['', '12345', '98765432101', 'abc'] as $bad) {
            $this->actingAs($admin, 'sanctum')->postJson('/api/v1/admin/integrations/sms/test', ['target' => $bad, 'values' => $values])
                ->assertOk()->assertJsonPath('data.status', 'incomplete');
        }

        $this->actingAs($admin, 'sanctum')->postJson('/api/v1/admin/integrations/sms/test', ['target' => '9876543210', 'values' => ['driver' => 'log']])
            ->assertOk()->assertJsonPath('data.status', 'unavailable');

        Http::assertNothingSent();
    }

    public function test_the_phone_number_typed_for_a_test_is_never_written_to_the_audit_log(): void
    {
        Http::fake(['*' => Http::response(['type' => 'success'])]);
        $admin = $this->admin();

        $this->actingAs($admin, 'sanctum')->postJson('/api/v1/admin/integrations/sms/test', [
            'target' => '9876543210',
            'values' => ['driver' => 'msg91', 'msg91_authkey' => self::MSG91_KEY, 'msg91_template_otp' => 'tpl_1'],
        ])->assertOk();

        $this->assertSame(1, IntegrationAuditLog::where('action', 'TEST')->where('group', 'sms')->count());
        $this->assertStringNotContainsString('9876543210', json_encode(IntegrationAuditLog::all()));
    }

    // ── Storage ─────────────────────────────────────────────────────────

    public function test_with_nothing_set_storage_is_the_server_disk_exactly_as_before(): void
    {
        $this->assertSame('local', config('filesystems.disks.media.driver'));
        $this->assertSame('public', config('filesystems.disks.media.visibility'));
        $this->assertStringEndsWith('/storage', config('filesystems.disks.media.url'));
    }

    public function test_choosing_s3_requires_everything_it_needs(): void
    {
        $this->save($this->admin(), 'storage', ['driver' => 's3'])
            ->assertStatus(422)
            ->assertJsonValidationErrors([
                'values.bucket', 'values.public_url', 'values.region', 'values.access_key', 'values.secret_key',
            ]);

        $this->assertSame(0, IntegrationSetting::count());
    }

    public function test_s3_settings_reach_the_disk(): void
    {
        $this->save($this->admin(), 'storage', $this->s3(['endpoint' => 'https://8.8.8.8']))->assertOk();

        $this->assertSame('s3', config('filesystems.disks.media.driver'));
        $this->assertSame('shop-media', config('filesystems.disks.media.bucket'));
        $this->assertSame('https://cdn.shop.in', config('filesystems.disks.media.url'));
        $this->assertSame(self::ACCESS_KEY, config('filesystems.disks.media.key'));
        $this->assertSame(self::SECRET_KEY, config('filesystems.disks.media.secret'));
        $this->assertSame('https://8.8.8.8', config('filesystems.disks.media.endpoint'));
    }

    public function test_on_s3_no_visibility_is_requested_because_new_buckets_reject_public_acls(): void
    {
        $this->save($this->admin(), 'storage', $this->s3())->assertOk();

        $this->assertNull(config('filesystems.disks.media.visibility'));
    }

    public function test_path_style_follows_an_endpoint_being_set(): void
    {
        $admin = $this->admin();

        $this->save($admin, 'storage', $this->s3())->assertOk();
        $this->assertFalse(config('filesystems.disks.media.use_path_style_endpoint'));

        $this->save($admin, 'storage', ['endpoint' => 'https://8.8.8.8'])->assertOk();
        $this->assertTrue(config('filesystems.disks.media.use_path_style_endpoint'));
    }

    public function test_switching_back_to_local_restores_the_server_disk_and_its_url(): void
    {
        $admin = $this->admin();
        $this->save($admin, 'storage', $this->s3())->assertOk();

        $this->save($admin, 'storage', ['driver' => 'local'])->assertOk();

        $this->assertSame('local', config('filesystems.disks.media.driver'));
        $this->assertSame('public', config('filesystems.disks.media.visibility'));
        $this->assertStringEndsWith('/storage', config('filesystems.disks.media.url'), 'the CDN address must not leak onto the server disk');
    }

    public function test_the_disks_are_rebuilt_after_a_change(): void
    {
        $admin = $this->admin();
        $before = app('filesystem')->disk('media');

        $this->save($admin, 'storage', $this->s3())->assertOk();

        $this->assertNotSame($before, app('filesystem')->disk('media'));
    }

    #[DataProvider('badEndpoints')]
    public function test_an_endpoint_must_be_https_and_public(string $endpoint): void
    {
        $this->save($this->admin(), 'storage', $this->s3(['endpoint' => $endpoint]))
            ->assertStatus(422)->assertJsonValidationErrors('values.endpoint');
    }

    public static function badEndpoints(): array
    {
        return [
            ['http://8.8.8.8'],
            ['https://127.0.0.1'],
            ['https://localhost:9000'],
            ['https://169.254.169.254'],
            ['https://10.0.0.7'],
            ['ftp://8.8.8.8'],
            ['8.8.8.8'],
        ];
    }

    public function test_bucket_names_and_the_public_url_are_validated(): void
    {
        $admin = $this->admin();

        $this->save($admin, 'storage', ['bucket' => 'Has Spaces'])->assertStatus(422);
        $this->save($admin, 'storage', ['bucket' => '../etc'])->assertStatus(422);
        $this->save($admin, 'storage', ['public_url' => 'http://cdn.shop.in'])->assertStatus(422)->assertJsonValidationErrors('values.public_url');
        $this->save($admin, 'storage', ['region' => 'AP South'])->assertStatus(422);
    }

    public function test_storage_credentials_are_never_returned_or_audited(): void
    {
        $admin = $this->admin();
        $put = $this->save($admin, 'storage', $this->s3())->assertOk()->getContent();
        $get = $this->actingAs($admin, 'sanctum')->getJson('/api/v1/admin/integrations')->getContent();
        $audit = $this->actingAs($admin, 'sanctum')->getJson('/api/v1/admin/integrations/audit')->getContent();

        foreach ([$put, $get, $audit, json_encode(IntegrationAuditLog::all())] as $body) {
            $this->assertStringNotContainsString(self::ACCESS_KEY, $body);
            $this->assertStringNotContainsString(self::SECRET_KEY, $body);
        }
    }

    public function test_the_status_badges_reflect_what_is_set_up(): void
    {
        $admin = $this->admin();
        $status = fn (string $id) => collect($this->actingAs($admin, 'sanctum')->getJson('/api/v1/admin/integrations')->json('data.groups'))->firstWhere('id', $id)['status'];

        $this->assertSame('missing', $status('email'));
        $this->assertSame('missing', $status('sms'));
        $this->assertSame('local', $status('storage'));

        $this->save($admin, 'email', $this->smtp())->assertOk();
        $this->save($admin, 'sms', ['driver' => 'msg91', 'msg91_authkey' => self::MSG91_KEY, 'msg91_template_otp' => 'tpl_1'])->assertOk();
        $this->save($admin, 'storage', $this->s3())->assertOk();

        $this->assertSame('configured', $status('email'));
        $this->assertSame('configured', $status('sms'));
        $this->assertSame('configured', $status('storage'));
    }

    public function test_the_monitoring_status_is_read_only_and_reveals_no_dsn(): void
    {
        config(['sentry.dsn' => 'https://abc123secretkey@o1.ingest.sentry.io/42']);

        $response = $this->actingAs($this->admin(), 'sanctum')->getJson('/api/v1/admin/integrations')->assertOk();

        $response->assertJsonPath('data.monitoring.configured', true)->assertJsonPath('data.monitoring.managed_here', false);
        $this->assertStringNotContainsString('abc123secretkey', $response->getContent());
    }

    // ── Console processes ───────────────────────────────────────────────

    public function test_console_commands_get_the_admin_settings_too(): void
    {
        $this->save($this->admin(), 'email', $this->smtp())->assertOk();
        config(['mail.default' => 'log']); // what a fresh scheduler process would see

        // A real `php artisan` bridges Symfony's command events to Laravel's; the test
        // kernel skips that, so switch it on to exercise the real path.
        app(\Illuminate\Contracts\Console\Kernel::class)->rerouteSymfonyCommandEvents();
        $this->artisan('inspire')->assertSuccessful();

        $this->assertSame('smtp', config('mail.default'));
    }

    public function test_config_compiling_commands_never_get_the_overlay(): void
    {
        $this->save($this->admin(), 'email', $this->smtp())->assertOk();

        foreach (['config:cache', 'optimize', 'migrate'] as $command) {
            config(['mail.default' => 'log', 'mail.mailers.smtp.password' => null]);

            Event::dispatch(new CommandStarting($command, new ArrayInput([]), new NullOutput));

            $this->assertSame('log', config('mail.default'), "{$command} must not see admin settings");
            $this->assertNull(config('mail.mailers.smtp.password'), "{$command} must not see secrets");
        }

        // and an ordinary command does
        Event::dispatch(new CommandStarting('schedule:run', new ArrayInput([]), new NullOutput));
        $this->assertSame('smtp', config('mail.default'));
    }

    public function test_a_console_process_survives_an_unreadable_settings_table(): void
    {
        \Illuminate\Support\Facades\Schema::dropIfExists('integration_settings');
        app(IntegrationSettings::class)->forgetRows();

        $this->artisan('inspire')->assertSuccessful();
    }

    // ── Every secret, generically ───────────────────────────────────────

    public function test_no_secret_field_anywhere_in_the_registry_ever_comes_back_out(): void
    {
        $admin = $this->admin();
        $planted = [];

        foreach (Registry::fields() as $field) {
            if ($field->isSecret()) {
                $planted[$field->key()] = 'PLANTED-'.strtoupper(bin2hex(random_bytes(10)));
                app(IntegrationSettings::class)->set($field, $planted[$field->key()], $admin->id);
            }
        }

        $this->assertNotEmpty($planted);

        $everything = $this->actingAs($admin, 'sanctum')->getJson('/api/v1/admin/integrations')->getContent()
            .$this->actingAs($admin, 'sanctum')->getJson('/api/v1/admin/integrations/audit')->getContent();

        foreach ($planted as $key => $secret) {
            $this->assertStringNotContainsString($secret, $everything, "{$key} leaked");
            $this->assertStringNotContainsString($secret, \App\Logging\SecretScrubber::scrub("error calling provider with {$secret}"), "{$key} survives log scrubbing");
        }
    }

    public function test_every_secret_field_is_covered_by_the_log_scrubber(): void
    {
        foreach (Registry::fields() as $field) {
            if (! $field->isSecret()) {
                continue;
            }

            $value = 'SCRUB-'.strtoupper(bin2hex(random_bytes(10)));
            config([$field->config[0] => $value]);

            $this->assertStringNotContainsString($value, \App\Logging\SecretScrubber::scrub("x {$value} y"), $field->key());
        }
    }
}
