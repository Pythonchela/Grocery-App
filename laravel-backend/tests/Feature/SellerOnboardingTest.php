<?php

namespace Tests\Feature;

use App\Models\Category;
use App\Models\Seller;
use App\Models\SellerDocument;
use App\Models\SellerKycProfile;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

/**
 * Applying to sell, and the verification that stands between an application and
 * a working shop.
 *
 * Public signup is only defensible because of that gate, so most of what's here
 * asserts the gate holds: an unverified account cannot list, cannot be switched
 * on, and cannot talk its way past review.
 */
class SellerOnboardingTest extends TestCase
{
    use RefreshDatabase;

    private const VALID_KYC = [
        'business_type' => 'PROPRIETORSHIP',
        'legal_name' => 'Jaipur Handicrafts',
        'pan' => 'ABCDE1234F',
        'registered_line1' => '12 MI Road',
        'registered_city' => 'Jaipur',
        'registered_state' => 'Rajasthan',
        'registered_pincode' => '302001',
        'bank_account_holder' => 'Jaipur Handicrafts',
        'bank_account_number' => '123456789012',
        'bank_ifsc' => 'HDFC0001234',
    ];

    private function customer(): User
    {
        return User::factory()->create(['role' => 'CUSTOMER', 'status' => 'ACTIVE']);
    }

    private function admin(): User
    {
        return User::factory()->create(['role' => 'ADMIN', 'status' => 'ACTIVE']);
    }

    private function apply(User $user, string $name = 'Jaipur Handicrafts')
    {
        return $this->actingAs($user, 'sanctum')
            ->postJson('/api/v1/sellers/apply', ['display_name' => $name]);
    }

    /** Applies, fills everything in, uploads both required documents. */
    private function completeApplication(User $user): Seller
    {
        Storage::fake('private');

        $this->apply($user)->assertCreated();
        $this->actingAs($user, 'sanctum')
            ->putJson('/api/v1/seller/onboarding/kyc', self::VALID_KYC)->assertOk();

        foreach (SellerDocument::REQUIRED_KINDS as $kind) {
            $this->actingAs($user, 'sanctum')->postJson('/api/v1/seller/onboarding/documents', [
                'kind' => $kind,
                'file' => UploadedFile::fake()->image("{$kind}.jpg"),
            ])->assertCreated();
        }

        return $user->fresh()->seller;
    }

    // ── Applying ────────────────────────────────────────────────────────

    public function test_a_customer_can_apply_and_lands_in_pending(): void
    {
        $user = $this->customer();

        $this->apply($user)->assertCreated()
            ->assertJsonPath('data.seller.status', 'PENDING');

        $seller = $user->fresh()->seller;
        $this->assertSame(User::ROLE_SELLER, $user->fresh()->role);
        $this->assertSame('PENDING', $seller->status);
        $this->assertSame('DRAFT', $seller->kyc->status);
    }

    public function test_an_applicant_cannot_choose_their_own_commission_or_status(): void
    {
        $user = $this->customer();

        $this->actingAs($user, 'sanctum')->postJson('/api/v1/sellers/apply', [
            'display_name' => 'Sneaky Shop',
            'commission_rate' => 0,
            'status' => 'ACTIVE',
        ])->assertCreated();

        $seller = $user->fresh()->seller;
        $this->assertSame('PENDING', $seller->status);
        $this->assertGreaterThan(0, (float) $seller->commission_rate);
    }

    public function test_applying_twice_is_refused(): void
    {
        $user = $this->customer();

        $this->apply($user)->assertCreated();
        $this->apply($user)->assertStatus(409);

        $this->assertSame(1, Seller::where('user_id', $user->id)->count());
    }

    public function test_a_staff_account_cannot_apply(): void
    {
        $this->apply($this->admin())->assertStatus(422);
        $this->assertSame(0, Seller::whereNotNull('user_id')->count());
    }

    public function test_applying_requires_authentication(): void
    {
        $this->postJson('/api/v1/sellers/apply', ['display_name' => 'Anon Shop'])
            ->assertUnauthorized();
    }

    // ── The gate ────────────────────────────────────────────────────────

    public function test_a_pending_seller_cannot_list_products(): void
    {
        $user = $this->customer();
        $this->apply($user)->assertCreated();

        $this->actingAs($user->fresh(), 'sanctum')->postJson('/api/v1/products', [
            'title' => 'Too early',
            'category_id' => Category::factory()->create()->id,
            'price' => 100,
            'mrp' => 200,
        ])->assertForbidden();
    }

    public function test_a_pending_seller_cannot_reach_the_active_seller_area(): void
    {
        $user = $this->customer();
        $this->apply($user)->assertCreated();

        $this->actingAs($user->fresh(), 'sanctum')
            ->getJson('/api/v1/seller/ledger')->assertForbidden();
    }

    public function test_a_pending_seller_can_reach_onboarding(): void
    {
        $user = $this->customer();
        $this->apply($user)->assertCreated();

        $this->actingAs($user->fresh(), 'sanctum')
            ->getJson('/api/v1/seller/onboarding')->assertOk()
            ->assertJsonPath('data.kyc.status', 'DRAFT');
    }

    public function test_a_shop_made_without_an_application_still_opens_onboarding(): void
    {
        // The owner's own shop never applied, so it has no KYC row.
        $user = User::factory()->create(['role' => User::ROLE_SELLER, 'status' => 'ACTIVE']);
        Seller::factory()->create(['user_id' => $user->id, 'status' => 'ACTIVE']);
        $this->assertNull($user->fresh()->seller->kyc);

        $this->actingAs($user->fresh(), 'sanctum')
            ->getJson('/api/v1/seller/onboarding')->assertOk()
            ->assertJsonPath('data.kyc.status', 'DRAFT');
    }

    public function test_an_admin_cannot_activate_a_seller_without_approved_kyc(): void
    {
        $user = $this->customer();
        $this->apply($user)->assertCreated();
        $seller = $user->fresh()->seller;

        $this->actingAs($this->admin(), 'sanctum')
            ->putJson("/api/v1/admin/sellers/{$seller->id}", ['status' => 'ACTIVE'])
            ->assertStatus(422);

        $this->assertSame('PENDING', $seller->fresh()->status);
    }

    // ── Validation ──────────────────────────────────────────────────────

    public function test_indian_identifier_formats_are_enforced(): void
    {
        $user = $this->customer();
        $this->apply($user)->assertCreated();

        $this->actingAs($user->fresh(), 'sanctum')->putJson('/api/v1/seller/onboarding/kyc', [
            'pan' => 'NOTAPAN',
            'bank_ifsc' => 'BAD',
            'bank_account_number' => '12',
            'registered_pincode' => '0123',
        ])->assertStatus(422)
            ->assertJsonValidationErrors(['pan', 'bank_ifsc', 'bank_account_number', 'registered_pincode']);
    }

    public function test_identifiers_are_normalised_to_uppercase(): void
    {
        $user = $this->customer();
        $this->apply($user)->assertCreated();

        $this->actingAs($user->fresh(), 'sanctum')->putJson('/api/v1/seller/onboarding/kyc', [
            'pan' => 'abcde1234f',
            'bank_ifsc' => 'hdfc0001234',
        ])->assertOk();

        $kyc = $user->fresh()->seller->kyc;
        $this->assertSame('ABCDE1234F', $kyc->pan);
        $this->assertSame('HDFC0001234', $kyc->bank_ifsc);
    }

    public function test_one_pan_cannot_register_two_seller_accounts(): void
    {
        $first = $this->customer();
        $this->apply($first)->assertCreated();
        $this->actingAs($first->fresh(), 'sanctum')
            ->putJson('/api/v1/seller/onboarding/kyc', ['pan' => 'ABCDE1234F'])->assertOk();

        $second = $this->customer();
        $this->apply($second, 'Second Shop')->assertCreated();

        $this->actingAs($second->fresh(), 'sanctum')
            ->putJson('/api/v1/seller/onboarding/kyc', ['pan' => 'ABCDE1234F'])
            ->assertStatus(422)
            ->assertJsonValidationErrors('pan');
    }

    // ── Storage and disclosure ──────────────────────────────────────────

    public function test_identity_numbers_are_encrypted_at_rest(): void
    {
        $user = $this->customer();
        $this->apply($user)->assertCreated();
        $this->actingAs($user->fresh(), 'sanctum')
            ->putJson('/api/v1/seller/onboarding/kyc', self::VALID_KYC)->assertOk();

        $raw = \Illuminate\Support\Facades\DB::table('seller_kyc_profiles')->first();

        $this->assertNotSame('ABCDE1234F', $raw->pan);
        $this->assertNotSame('123456789012', $raw->bank_account_number);
        // And still readable through the model.
        $this->assertSame('ABCDE1234F', $user->fresh()->seller->kyc->pan);
    }

    public function test_the_seller_sees_only_masked_identity_numbers(): void
    {
        $user = $this->customer();
        $this->apply($user)->assertCreated();
        $this->actingAs($user->fresh(), 'sanctum')
            ->putJson('/api/v1/seller/onboarding/kyc', self::VALID_KYC)->assertOk();

        $kyc = $this->actingAs($user->fresh(), 'sanctum')
            ->getJson('/api/v1/seller/onboarding')->assertOk()->json('data.kyc');

        $this->assertSame('••••••234F', $kyc['pan']);
        $this->assertSame('••••••••9012', $kyc['bank_account_number']);
        $this->assertStringNotContainsString('ABCDE1234F', json_encode($kyc));
    }

    public function test_documents_are_stored_privately_and_need_authorisation_to_read(): void
    {
        Storage::fake('private');
        Storage::fake('media');

        $user = $this->customer();
        $this->apply($user)->assertCreated();

        $this->actingAs($user->fresh(), 'sanctum')->postJson('/api/v1/seller/onboarding/documents', [
            'kind' => 'PAN_CARD',
            'file' => UploadedFile::fake()->image('pan.jpg'),
        ])->assertCreated();

        $document = SellerDocument::firstOrFail();

        $this->assertSame('private', $document->disk);
        Storage::disk('private')->assertExists($document->path);
        // Never on the disk that product images are served from.
        Storage::disk('media')->assertMissing($document->path);

        // The path itself is not handed out.
        $listed = $this->actingAs($user->fresh(), 'sanctum')
            ->getJson('/api/v1/seller/onboarding')->json('data.documents.0');
        $this->assertArrayNotHasKey('path', $listed);

        // The owner may read it; an unrelated user may not.
        $this->actingAs($user->fresh(), 'sanctum')
            ->get("/api/v1/seller/documents/{$document->id}/download")->assertOk();
        $this->actingAs($this->customer(), 'sanctum')
            ->getJson("/api/v1/seller/documents/{$document->id}/download")->assertForbidden();
        $this->actingAs($this->admin(), 'sanctum')
            ->get("/api/v1/seller/documents/{$document->id}/download")->assertOk();
    }

    public function test_another_seller_cannot_read_someone_elses_documents(): void
    {
        $owner = $this->customer();
        $this->completeApplication($owner);
        $document = SellerDocument::firstOrFail();

        $stranger = $this->customer();
        $this->apply($stranger, 'Other Shop')->assertCreated();

        $this->actingAs($stranger->fresh(), 'sanctum')
            ->getJson("/api/v1/seller/documents/{$document->id}/download")
            ->assertForbidden();
    }

    public function test_executables_are_rejected_as_documents(): void
    {
        Storage::fake('private');
        $user = $this->customer();
        $this->apply($user)->assertCreated();

        $this->actingAs($user->fresh(), 'sanctum')->postJson('/api/v1/seller/onboarding/documents', [
            'kind' => 'PAN_CARD',
            'file' => UploadedFile::fake()->create('payload.php', 12, 'application/x-httpd-php'),
        ])->assertStatus(422);

        $this->assertSame(0, SellerDocument::count());
    }

    // ── Submission ──────────────────────────────────────────────────────

    public function test_an_incomplete_application_cannot_be_submitted(): void
    {
        $user = $this->customer();
        $this->apply($user)->assertCreated();

        $this->actingAs($user->fresh(), 'sanctum')
            ->postJson('/api/v1/seller/onboarding/submit')
            ->assertStatus(422)
            ->assertJsonValidationErrors(['missing_fields', 'missing_documents']);

        $this->assertSame('DRAFT', $user->fresh()->seller->kyc->status);
    }

    public function test_a_complete_application_submits_and_locks(): void
    {
        $user = $this->customer();
        $this->completeApplication($user);

        $this->actingAs($user->fresh(), 'sanctum')
            ->postJson('/api/v1/seller/onboarding/submit')->assertOk()
            ->assertJsonPath('data.kyc.status', 'SUBMITTED');

        // Locked while a reviewer has it.
        $this->actingAs($user->fresh(), 'sanctum')
            ->putJson('/api/v1/seller/onboarding/kyc', ['legal_name' => 'Changed'])
            ->assertStatus(422);
    }

    public function test_a_gst_registered_seller_must_supply_the_certificate(): void
    {
        $user = $this->customer();
        $this->completeApplication($user);

        $this->actingAs($user->fresh(), 'sanctum')->putJson('/api/v1/seller/onboarding/kyc', [
            'gstin' => '08ABCDE1234F1Z5',
        ])->assertOk();

        $this->actingAs($user->fresh(), 'sanctum')
            ->postJson('/api/v1/seller/onboarding/submit')
            ->assertStatus(422)
            ->assertJsonPath('errors.missing_documents.0', 'GST_CERTIFICATE');
    }

    // ── Review ──────────────────────────────────────────────────────────

    public function test_approval_activates_the_shop(): void
    {
        $user = $this->customer();
        $seller = $this->completeApplication($user);
        $this->actingAs($user->fresh(), 'sanctum')->postJson('/api/v1/seller/onboarding/submit')->assertOk();

        $this->actingAs($this->admin(), 'sanctum')
            ->postJson("/api/v1/admin/sellers/{$seller->id}/kyc/approve")->assertOk();

        $this->assertSame('ACTIVE', $seller->fresh()->status);
        $this->assertSame('APPROVED', $seller->fresh()->kyc->status);

        // The applicant is told, in the app, without having to keep reopening the page.
        $told = \App\Models\AppNotification::where('user_id', $user->id)->where('type', 'SELLER_APPLICATION')->first();
        $this->assertNotNull($told);
        $this->assertSame('Your shop is approved', $told->title);

        // And the shop now works.
        $this->actingAs($user->fresh(), 'sanctum')->postJson('/api/v1/products', [
            'title' => 'First listing',
            'category_id' => Category::factory()->create()->id,
            'price' => 500,
            'mrp' => 900,
        ])->assertCreated();
    }

    public function test_rejection_reopens_the_form_with_a_reason(): void
    {
        $user = $this->customer();
        $seller = $this->completeApplication($user);
        $this->actingAs($user->fresh(), 'sanctum')->postJson('/api/v1/seller/onboarding/submit')->assertOk();

        $this->actingAs($this->admin(), 'sanctum')
            ->postJson("/api/v1/admin/sellers/{$seller->id}/kyc/reject", [
                'reason' => 'The cancelled cheque is unreadable.',
            ])->assertOk();

        $this->assertSame('PENDING', $seller->fresh()->status);
        $this->assertSame('REJECTED', $seller->fresh()->kyc->status);

        $told = \App\Models\AppNotification::where('user_id', $user->id)->where('type', 'SELLER_APPLICATION')->first();
        $this->assertNotNull($told);
        $this->assertSame('Your application needs changes', $told->title);
        $this->assertStringContainsString('The cancelled cheque is unreadable.', $told->body);

        // Editable again, and the reason is visible to the applicant.
        $overview = $this->actingAs($user->fresh(), 'sanctum')
            ->getJson('/api/v1/seller/onboarding')->assertOk()->json('data');
        $this->assertTrue($overview['checklist']['editable']);
        $this->assertSame('The cancelled cheque is unreadable.', $overview['kyc']['rejection_reason']);

        // Resubmitting clears the old reason.
        $this->actingAs($user->fresh(), 'sanctum')->postJson('/api/v1/seller/onboarding/submit')->assertOk();
        $this->assertNull($seller->fresh()->kyc->rejection_reason);
    }

    public function test_rejection_requires_a_reason(): void
    {
        $user = $this->customer();
        $seller = $this->completeApplication($user);
        $this->actingAs($user->fresh(), 'sanctum')->postJson('/api/v1/seller/onboarding/submit')->assertOk();

        $this->actingAs($this->admin(), 'sanctum')
            ->postJson("/api/v1/admin/sellers/{$seller->id}/kyc/reject", [])
            ->assertStatus(422)->assertJsonValidationErrors('reason');
    }

    public function test_only_a_submitted_application_can_be_decided(): void
    {
        $user = $this->customer();
        $seller = $this->completeApplication($user);

        $this->actingAs($this->admin(), 'sanctum')
            ->postJson("/api/v1/admin/sellers/{$seller->id}/kyc/approve")->assertStatus(422);

        $this->assertSame('PENDING', $seller->fresh()->status);
    }

    public function test_the_review_queue_masks_identity_numbers(): void
    {
        $user = $this->customer();
        $this->completeApplication($user);
        $this->actingAs($user->fresh(), 'sanctum')->postJson('/api/v1/seller/onboarding/submit')->assertOk();

        $body = $this->actingAs($this->admin(), 'sanctum')
            ->getJson('/api/v1/admin/sellers/applications')->assertOk()->json();

        $this->assertSame(1, $body['count']);
        $this->assertStringNotContainsString('ABCDE1234F', json_encode($body));
    }

    public function test_a_reviewer_opening_one_application_sees_the_real_numbers(): void
    {
        $user = $this->customer();
        $seller = $this->completeApplication($user);
        $this->actingAs($user->fresh(), 'sanctum')->postJson('/api/v1/seller/onboarding/submit')->assertOk();

        $kyc = $this->actingAs($this->admin(), 'sanctum')
            ->getJson("/api/v1/admin/sellers/{$seller->id}/review")->assertOk()->json('data.kyc');

        $this->assertSame('ABCDE1234F', $kyc['pan']);
        $this->assertSame('123456789012', $kyc['bank_account_number']);
    }

    public function test_a_seller_cannot_review_applications(): void
    {
        $user = $this->customer();
        $seller = $this->completeApplication($user);

        $this->actingAs($user->fresh(), 'sanctum')
            ->getJson('/api/v1/admin/sellers/applications')->assertForbidden();
        $this->actingAs($user->fresh(), 'sanctum')
            ->getJson("/api/v1/admin/sellers/{$seller->id}/review")->assertForbidden();
        $this->actingAs($user->fresh(), 'sanctum')
            ->postJson("/api/v1/admin/sellers/{$seller->id}/kyc/approve")->assertForbidden();
    }
}
