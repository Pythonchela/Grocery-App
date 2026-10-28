<?php

namespace Tests\Feature;

use App\Integrations\Testers\StorageTester;
use App\Models\Category;
use App\Models\IntegrationSetting;
use App\Models\Product;
use App\Models\Seller;
use App\Models\SellerDocument;
use App\Models\User;
use Aws\Command;
use Aws\S3\Exception\S3Exception;
use Illuminate\Contracts\Filesystem\Filesystem;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

/**
 * Where uploaded files live: the upload endpoint, the connection test that proves a
 * bucket works before anything depends on it, and the commands that move files that
 * were uploaded before a bucket was chosen.
 */
class StorageTest extends TestCase
{
    use RefreshDatabase;

    private const ACCESS_KEY = 'AKIAEXAMPLEKEY123456';

    private const SECRET_KEY = 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY';

    private function admin(): User
    {
        return User::factory()->create(['role' => User::ROLE_ADMIN, 'password' => 'correct-horse-battery']);
    }

    private function s3Values(array $over = []): array
    {
        return array_merge([
            'driver' => 's3', 'bucket' => 'shop-media',
            'public_url' => 'https://8.8.8.8', 'region' => 'ap-south-1',
            'access_key' => self::ACCESS_KEY, 'secret_key' => self::SECRET_KEY,
        ], $over);
    }

    // ── Uploads ─────────────────────────────────────────────────────────

    public function test_an_upload_goes_to_the_media_disk_and_returns_a_url(): void
    {
        Storage::fake('media');

        $response = $this->actingAs($this->admin(), 'sanctum')
            ->post('/api/v1/uploads', ['file' => UploadedFile::fake()->image('lamp.jpg')], ['Accept' => 'application/json'])
            ->assertCreated();

        Storage::disk('media')->assertExists($response->json('data.path'));
        $this->assertStringContainsString('/storage/uploads/', $response->json('data.url'));
    }

    public function test_on_s3_the_url_is_the_buckets_public_address(): void
    {
        config(['filesystems.disks.media.driver' => 's3']);
        Storage::fake('media', ['url' => 'https://cdn.shop.in']);

        $response = $this->actingAs($this->admin(), 'sanctum')
            ->post('/api/v1/uploads', ['file' => UploadedFile::fake()->image('lamp.jpg')], ['Accept' => 'application/json'])
            ->assertCreated();

        $this->assertStringStartsWith('https://cdn.shop.in/uploads/', $response->json('data.url'));
    }

    public function test_a_failing_bucket_gives_a_plain_error_not_a_stack_trace(): void
    {
        $broken = \Mockery::mock(Filesystem::class);
        $broken->shouldReceive('putFileAs')->andThrow(new \RuntimeException('bucket shop-media down; key '.self::ACCESS_KEY));
        app('filesystem')->set('media', $broken);

        $response = $this->actingAs($this->admin(), 'sanctum')
            ->post('/api/v1/uploads', ['file' => UploadedFile::fake()->image('lamp.jpg')], ['Accept' => 'application/json'])
            ->assertStatus(503);

        $body = $response->getContent();
        $this->assertStringNotContainsString(self::ACCESS_KEY, $body);
        $this->assertStringNotContainsString('bucket shop-media', $body);
        $this->assertStringNotContainsString('RuntimeException', $body);
        $this->assertStringNotContainsString('#0', $body);
    }

    public function test_a_failed_upload_is_reported_so_it_reaches_the_error_tracker(): void
    {
        \Illuminate\Support\Facades\Exceptions::fake();

        $broken = \Mockery::mock(Filesystem::class);
        $broken->shouldReceive('putFileAs')->andThrow(new \RuntimeException('disk full'));
        app('filesystem')->set('media', $broken);

        $this->actingAs($this->admin(), 'sanctum')
            ->post('/api/v1/uploads', ['file' => UploadedFile::fake()->image('a.jpg')], ['Accept' => 'application/json'])
            ->assertStatus(503);

        \Illuminate\Support\Facades\Exceptions::assertReported(fn (\RuntimeException $e) => $e->getMessage() === 'disk full');
    }

    // ── The connection test ─────────────────────────────────────────────

    /** Point the tester's disk builder at a fake disk. */
    private function fakeBuckets(): array
    {
        $public = Storage::fake('t_public');
        Storage::shouldReceive('build')->andReturn($public);

        return [$public];
    }

    public function test_a_healthy_bucket_passes_and_leaves_nothing_behind(): void
    {
        [$public] = $this->fakeBuckets();
        Http::fake(fn ($r) => Http::response($public->get(ltrim((string) parse_url($r->url(), PHP_URL_PATH), '/'))));

        $result = (new StorageTester)->test($this->s3Values(), null);

        $this->assertSame('ok', $result->status, $result->message);
        $this->assertSame([], $public->allFiles());
    }

    public function test_a_bucket_that_is_not_publicly_readable_is_caught(): void
    {
        [$public] = $this->fakeBuckets();
        Http::fake(['*' => Http::response('AccessDenied', 403)]);

        $result = (new StorageTester)->test($this->s3Values(), null);

        $this->assertSame('failed', $result->status);
        $this->assertStringContainsString('not readable at the Public URL', $result->message);
        $this->assertSame([], $public->allFiles(), 'the probe file is removed even when the check fails');
    }

    public function test_the_public_url_must_not_point_at_a_private_address(): void
    {
        $this->fakeBuckets();
        Http::fake();

        $result = (new StorageTester)->test($this->s3Values(['public_url' => 'https://10.0.0.5']), null);

        $this->assertSame('failed', $result->status);
        Http::assertNothingSent();
    }

    public function test_a_bucket_that_returns_different_content_is_caught(): void
    {
        $bad = \Mockery::mock(Filesystem::class);
        $bad->shouldReceive('put')->andReturn(true);
        $bad->shouldReceive('get')->andReturn('something else');
        $bad->shouldReceive('delete')->andReturn(true);
        Storage::shouldReceive('build')->andReturn($bad);

        $result = (new StorageTester)->test($this->s3Values(), null);

        $this->assertSame('failed', $result->status);
        $this->assertStringContainsString('different content', $result->message);
    }

    public function test_a_denied_key_gets_a_specific_message_that_never_echoes_the_key(): void
    {
        $denied = \Mockery::mock(Filesystem::class);
        $denied->shouldReceive('put')->andThrow(new S3Exception('denied for '.self::ACCESS_KEY.' '.self::SECRET_KEY, new Command('PutObject'), ['code' => 'AccessDenied']));
        Storage::shouldReceive('build')->andReturn($denied);

        $result = (new StorageTester)->test($this->s3Values(), null);

        $this->assertSame('failed', $result->status);
        $this->assertStringContainsString('not allowed to write', $result->message);
        $this->assertStringNotContainsString(self::ACCESS_KEY, $result->message);
        $this->assertStringNotContainsString(self::SECRET_KEY, $result->message);
    }

    public function test_each_common_failure_has_its_own_plain_explanation(): void
    {
        $expected = [
            'InvalidAccessKeyId' => 'access key ID is not recognised',
            'SignatureDoesNotMatch' => 'secret access key is wrong',
            'NoSuchBucket' => 'does not exist',
            'PermanentRedirect' => 'region does not match',
        ];

        // One facade mock (Mockery cannot build the same mock class twice), handing out
        // whichever disk the current iteration set.
        $current = null;
        Storage::shouldReceive('build')->andReturnUsing(function () use (&$current) {
            return $current;
        });

        foreach ($expected as $code => $phrase) {
            $current = \Mockery::mock(Filesystem::class);
            $current->shouldReceive('put')->andThrow(new S3Exception('x', new Command('PutObject'), ['code' => $code]));

            $this->assertStringContainsString($phrase, (new StorageTester)->test($this->s3Values(), null)->message, $code);
        }
    }

    public function test_an_unreachable_service_is_reported_without_detail(): void
    {
        $disk = \Mockery::mock(Filesystem::class);
        $disk->shouldReceive('put')->andThrow(new \RuntimeException('cURL error 6: could not resolve host shop.r2.example'));
        Storage::shouldReceive('build')->andReturn($disk);

        $result = (new StorageTester)->test($this->s3Values(), null);

        $this->assertSame('failed', $result->status);
        $this->assertStringNotContainsString('cURL', $result->message);
    }

    public function test_the_local_disk_has_nothing_to_test_and_missing_settings_are_reported(): void
    {
        $this->assertSame('unavailable', (new StorageTester)->test(['driver' => 'local'], null)->status);
        $this->assertSame('incomplete', (new StorageTester)->test(['driver' => 's3', 'bucket' => 'x'], null)->status);
    }

    public function test_an_endpoint_on_a_private_network_is_refused_by_the_tester_too(): void
    {
        $result = (new StorageTester)->test($this->s3Values(['endpoint' => 'https://169.254.169.254']), null);

        $this->assertSame('failed', $result->status);
    }

    public function test_the_test_endpoint_tries_unsaved_values_and_saves_nothing(): void
    {
        [$public] = $this->fakeBuckets();
        Http::fake(fn ($r) => Http::response($public->get(ltrim((string) parse_url($r->url(), PHP_URL_PATH), '/'))));

        $response = $this->actingAs($this->admin(), 'sanctum')
            ->postJson('/api/v1/admin/integrations/storage/test', ['values' => $this->s3Values()])
            ->assertOk()
            ->assertJsonPath('data.status', 'ok');

        $this->assertStringNotContainsString(self::SECRET_KEY, $response->getContent());
        $this->assertSame(0, IntegrationSetting::count());
        $this->assertSame('local', config('filesystems.disks.media.driver'));
    }

    // ── Moving existing images ──────────────────────────────────────────

    /** @return array{0: Filesystem, 1: Filesystem} */
    private function migrationDisks(): array
    {
        config(['filesystems.disks.media.driver' => 's3', 'app.url' => 'http://localhost']);

        $old = Storage::fake('public');
        $new = Storage::fake('media', ['url' => 'https://cdn.shop.in']);

        $old->put('uploads/a.jpg', 'AAAA');
        $old->put('uploads/b.jpg', 'BBBBBB');

        return [$old, $new];
    }

    public function test_a_dry_run_reports_and_changes_nothing(): void
    {
        [, $new] = $this->migrationDisks();
        $category = Category::factory()->create(['banner_url' => 'http://localhost/storage/uploads/a.jpg']);

        $this->artisan('media:migrate')->assertSuccessful()->expectsOutputToContain('dry run');

        $this->assertSame([], $new->allFiles());
        $this->assertSame('http://localhost/storage/uploads/a.jpg', $category->fresh()->banner_url);
    }

    public function test_apply_copies_the_files_and_rewrites_the_urls_everywhere(): void
    {
        [, $new] = $this->migrationDisks();

        $category = Category::factory()->create(['banner_url' => 'http://localhost/storage/uploads/a.jpg']);
        $product = Product::factory()->create(['images' => [
            'http://localhost/storage/uploads/a.jpg', 'http://localhost/storage/uploads/b.jpg', 'https://elsewhere.test/keep.jpg',
        ]]);

        $this->artisan('media:migrate', ['--apply' => true])->assertSuccessful();

        $this->assertSame('AAAA', $new->get('uploads/a.jpg'));
        $this->assertSame('BBBBBB', $new->get('uploads/b.jpg'));

        $this->assertSame('https://cdn.shop.in/uploads/a.jpg', $category->fresh()->banner_url);
        $this->assertSame(
            ['https://cdn.shop.in/uploads/a.jpg', 'https://cdn.shop.in/uploads/b.jpg', 'https://elsewhere.test/keep.jpg'],
            $product->fresh()->images,
        );
    }

    public function test_rewriting_handles_json_with_escaped_slashes_too(): void
    {
        $this->migrationDisks();
        $product = Product::factory()->create(['images' => ['http://localhost/storage/uploads/a.jpg']]);

        // The raw stored text has its slashes escaped, exactly as a json column keeps them.
        // (MySQL's json type normalises them away, and the rewrite then simply matches the plain form.)
        if (! in_array(DB::connection()->getDriverName(), ['mysql', 'mariadb'], true)) {
            $this->assertStringContainsString('http:\\/\\/localhost', (string) DB::table('products')->where('id', $product->id)->value('images'));
        }

        $this->artisan('media:migrate', ['--apply' => true])->assertSuccessful();

        $this->assertSame(['https://cdn.shop.in/uploads/a.jpg'], $product->fresh()->images);
    }

    public function test_it_is_safe_to_run_twice(): void
    {
        $this->migrationDisks();
        $category = Category::factory()->create(['banner_url' => 'http://localhost/storage/uploads/a.jpg']);

        $this->artisan('media:migrate', ['--apply' => true])->assertSuccessful();
        $this->artisan('media:migrate', ['--apply' => true])->assertSuccessful();

        $this->assertSame('https://cdn.shop.in/uploads/a.jpg', $category->fresh()->banner_url);
    }

    public function test_nothing_is_deleted_from_the_server_disk(): void
    {
        [$old] = $this->migrationDisks();

        $this->artisan('media:migrate', ['--apply' => true])->assertSuccessful();

        $this->assertTrue($old->exists('uploads/a.jpg'));
        $this->assertTrue($old->exists('uploads/b.jpg'));
    }

    public function test_it_can_copy_without_touching_the_database(): void
    {
        [, $new] = $this->migrationDisks();
        $category = Category::factory()->create(['banner_url' => 'http://localhost/storage/uploads/a.jpg']);

        $this->artisan('media:migrate', ['--apply' => true, '--skip-rewrite' => true])->assertSuccessful();

        $this->assertTrue($new->exists('uploads/a.jpg'));
        $this->assertSame('http://localhost/storage/uploads/a.jpg', $category->fresh()->banner_url);
    }

    public function test_it_will_not_run_while_storage_is_still_the_server_disk(): void
    {
        $this->artisan('media:migrate', ['--apply' => true])->assertFailed()->expectsOutputToContain('still the server disk');
    }

    public function test_urls_are_not_rewritten_if_any_file_failed_to_copy(): void
    {
        [$old] = $this->migrationDisks();
        $category = Category::factory()->create(['banner_url' => 'http://localhost/storage/uploads/a.jpg']);

        $broken = \Mockery::mock(Filesystem::class);
        $broken->shouldReceive('exists')->andReturn(false);
        $broken->shouldReceive('writeStream')->andThrow(new \RuntimeException('bucket offline'));
        app('filesystem')->set('media', $broken);

        $this->artisan('media:migrate', ['--apply' => true])->assertFailed();

        $this->assertSame('http://localhost/storage/uploads/a.jpg', $category->fresh()->banner_url, 'a URL must never point at a file that is not there');
        $this->assertTrue($old->exists('uploads/a.jpg'));
    }

    // ── Moving seller documents ─────────────────────────────────────────

    private function document(string $path, string $disk = 'local'): SellerDocument
    {
        $seller = Seller::factory()->create();

        return $seller->documents()->create([
            'kind' => 'PAN_CARD', 'disk' => $disk, 'path' => $path, 'original_name' => 'pan.pdf',
            'mime' => 'application/pdf', 'size_bytes' => 4, 'uploaded_by' => User::factory()->create()->id,
        ]);
    }

}
