<?php

namespace Tests\Feature;

use App\Models\AuditLog;
use App\Models\PayoutRequest;
use App\Models\Seller;
use App\Models\User;
use App\Services\Audit;
use App\Services\SellerPayoutService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/** The audit trail: sensitive staff actions leave a row, and only full admins can read them. */
class AuditLogTest extends TestCase
{
    use RefreshDatabase;

    private function admin(string $role = 'ADMIN'): User
    {
        return User::factory()->create(['role' => $role, 'status' => 'ACTIVE']);
    }

    private function seller(): Seller
    {
        $user = User::factory()->create(['role' => User::ROLE_SELLER, 'status' => 'ACTIVE']);
        $seller = Seller::factory()->create(['user_id' => $user->id, 'status' => 'ACTIVE', 'commission_rate' => 10]);
        $kyc = $seller->kyc()->create(['business_type' => 'INDIVIDUAL', 'legal_name' => 'A', 'bank_account_holder' => 'A', 'bank_account_number' => '123456789012', 'bank_ifsc' => 'HDFC0001234']);
        $kyc->forceFill(['status' => 'APPROVED'])->save();

        return $seller->fresh();
    }

    public function test_recording_never_throws_and_keeps_what_it_is_told(): void
    {
        $admin = $this->admin();

        Audit::record($admin, 'test.thing', ['Thing', '42'], 'Did a thing', ['k' => 'v']);
        Audit::record(null, 'test.system', null, 'The system did one');

        $row = AuditLog::where('action', 'test.thing')->firstOrFail();
        $this->assertSame($admin->id, $row->actor_id);
        $this->assertSame('Thing', $row->subject_type);
        $this->assertSame('42', $row->subject_id);
        $this->assertSame(['k' => 'v'], $row->meta);
        $this->assertNull(AuditLog::where('action', 'test.system')->first()->actor_id);
    }

    public function test_access_changes_are_recorded_and_never_contain_a_password(): void
    {
        $admin = $this->admin();
        $staff = User::factory()->create(['role' => 'SUB_ADMIN', 'status' => 'ACTIVE']);

        $this->actingAs($admin, 'sanctum')->putJson("/api/v1/admin/users/{$staff->id}/status", ['status' => 'BLOCKED'])->assertOk();
        $this->actingAs($admin, 'sanctum')->putJson("/api/v1/admin/users/{$staff->id}/password", ['password' => 'a-very-long-password-1'])->assertOk();

        $this->assertTrue(AuditLog::where('action', 'user.blocked')->exists());
        $this->assertTrue(AuditLog::where('action', 'staff.password_reset')->exists());
        $this->assertStringNotContainsString('a-very-long-password-1', json_encode(AuditLog::all()->toArray()));
    }

    public function test_only_full_admins_can_read_the_trail_and_it_can_be_filtered(): void
    {
        $admin = $this->admin();
        Audit::record($admin, 'payout.paid', ['PayoutRequest', 'a'], 'Paid ₹500');
        Audit::record($admin, 'user.blocked', ['User', 'b'], 'Blocked Someone');

        $all = $this->actingAs($admin, 'sanctum')->getJson('/api/v1/admin/audit-logs')->assertOk();
        $this->assertCount(2, $all->json('data'));
        $this->assertSame($admin->name, $all->json('data.0.actor'));

        $this->assertCount(1, $this->actingAs($admin, 'sanctum')->getJson('/api/v1/admin/audit-logs?action=payout')->json('data'));
        $this->assertCount(1, $this->actingAs($admin, 'sanctum')->getJson('/api/v1/admin/audit-logs?q=Blocked')->json('data'));
        $this->assertCount(0, $this->actingAs($admin, 'sanctum')->getJson('/api/v1/admin/audit-logs?from='.now()->addDay()->toDateString())->json('data'));

        $this->actingAs($this->admin('SUB_ADMIN'), 'sanctum')->getJson('/api/v1/admin/audit-logs')->assertForbidden();
        $this->actingAs(User::factory()->create(['role' => 'CUSTOMER', 'status' => 'ACTIVE']), 'sanctum')->getJson('/api/v1/admin/audit-logs')->assertForbidden();
    }
}
