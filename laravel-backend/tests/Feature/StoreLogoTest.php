<?php

namespace Tests\Feature;

use App\Models\AuditLog;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

/** The store logo: staff set it once, shoppers' apps read it from the public theme. */
class StoreLogoTest extends TestCase
{
    use RefreshDatabase;

    private function staff(string $role = 'ADMIN'): User
    {
        return User::factory()->create(['role' => $role, 'status' => 'ACTIVE']);
    }

    private function upload(User $user, UploadedFile $file)
    {
        return $this->actingAs($user, 'sanctum')
            ->post('/api/v1/admin/theme/logo', ['file' => $file], ['Accept' => 'application/json']);
    }

    public function test_there_is_no_logo_until_one_is_uploaded(): void
    {
        $this->getJson('/api/v1/theme')->assertOk()->assertJsonPath('data.logo_url', null);
    }

    public function test_staff_can_upload_a_logo_and_anyone_can_read_it(): void
    {
        Storage::fake('media');
        $staff = $this->staff();

        $this->upload($staff, UploadedFile::fake()->image('logo.png', 400, 400))
            ->assertOk()
            ->assertJsonPath('status', 'success');

        $url = $this->getJson('/api/v1/theme')->json('data.logo_url');
        $this->assertStringContainsString('/storage/branding/', $url);
        $this->assertCount(1, Storage::disk('media')->files('branding'));
        $this->assertSame(1, AuditLog::where('action', 'theme.logo_changed')->count());
    }

    public function test_a_sub_admin_can_change_it_too(): void
    {
        Storage::fake('media');

        $this->upload($this->staff('SUB_ADMIN'), UploadedFile::fake()->image('logo.webp', 200, 200))->assertOk();
    }

    public function test_replacing_the_logo_removes_the_old_file(): void
    {
        Storage::fake('media');
        $staff = $this->staff();

        $this->upload($staff, UploadedFile::fake()->image('one.png', 300, 300))->assertOk();
        $this->upload($staff, UploadedFile::fake()->image('two.png', 300, 300))->assertOk();

        $this->assertCount(1, Storage::disk('media')->files('branding'));
    }

    public function test_removing_the_logo_returns_to_the_shipped_mark(): void
    {
        Storage::fake('media');
        $staff = $this->staff();
        $this->upload($staff, UploadedFile::fake()->image('logo.png', 300, 300))->assertOk();

        $this->actingAs($staff, 'sanctum')->deleteJson('/api/v1/admin/theme/logo')
            ->assertOk()
            ->assertJsonPath('data.logo_url', null);

        $this->assertCount(0, Storage::disk('media')->files('branding'));
        $this->getJson('/api/v1/theme')->assertJsonPath('data.logo_url', null);
    }

    public function test_resetting_everything_also_clears_the_logo(): void
    {
        Storage::fake('media');
        $staff = $this->staff();
        $this->upload($staff, UploadedFile::fake()->image('logo.png', 300, 300))->assertOk();

        $this->actingAs($staff, 'sanctum')->postJson('/api/v1/admin/theme/reset', ['scope' => 'all'])
            ->assertOk()
            ->assertJsonPath('data.logo_url', null);
    }

    public function test_shoppers_sellers_and_visitors_cannot_change_it(): void
    {
        Storage::fake('media');
        $file = fn () => UploadedFile::fake()->image('logo.png', 300, 300);

        $this->post('/api/v1/admin/theme/logo', ['file' => $file()], ['Accept' => 'application/json'])->assertUnauthorized();

        $this->deleteJson('/api/v1/admin/theme/logo')->assertUnauthorized();

        foreach (['CUSTOMER', 'SELLER'] as $role) {
            $this->upload(User::factory()->create(['role' => $role, 'status' => 'ACTIVE']), $file())->assertForbidden();
        }
    }

    public function test_only_ordinary_images_are_accepted(): void
    {
        Storage::fake('media');
        $staff = $this->staff();

        $svg = UploadedFile::fake()->createWithContent('logo.svg', '<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>');
        $this->upload($staff, $svg)->assertStatus(422);
        $this->upload($staff, UploadedFile::fake()->create('logo.pdf', 10, 'application/pdf'))->assertStatus(422);
        $this->upload($staff, UploadedFile::fake()->image('tiny.png', 16, 16))->assertStatus(422)
            ->assertJsonValidationErrors('file');
        $this->upload($staff, UploadedFile::fake()->image('huge.png', 400, 400)->size(3000))->assertStatus(422);

        $this->assertCount(0, Storage::disk('media')->files('branding'));
    }
}
