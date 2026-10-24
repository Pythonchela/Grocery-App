<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Seller;
use App\Models\SellerDocument;
use App\Models\SellerKycProfile;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

/**
 * Becoming a seller: apply, supply identity and settlement details, upload the
 * documents that back them, submit for review.
 *
 * Applying is open to any signed-in customer, but it only ever produces a
 * PENDING account. Nothing here can switch a seller on — that decision belongs
 * to a reviewer who has seen the documents, and is the reason a public signup
 * is safe to offer at all.
 */
class SellerOnboardingController extends Controller
{
    /** Indian formats, checked here so bad data never reaches a reviewer. */
    private const PAN_REGEX = '/^[A-Z]{5}[0-9]{4}[A-Z]$/';

    private const GSTIN_REGEX = '/^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][0-9A-Z]Z[0-9A-Z]$/';

    private const IFSC_REGEX = '/^[A-Z]{4}0[A-Z0-9]{6}$/';

    /** Apply to sell. Creates the merchant account in PENDING with a DRAFT KYC. */
    public function apply(Request $request)
    {
        $user = $request->user();

        // A single-business store has no vendors.
        if (! \App\Support\StoreMode::vendorsEnabled()) {
            return response()->json([
                'status' => 'error',
                'message' => 'This store does not take outside sellers.',
            ], 403);
        }

        if ($user->isAdmin()) {
            return response()->json([
                'status' => 'error',
                'message' => 'A staff account cannot also be a seller.',
            ], 422);
        }

        // Queried, not read from the cached relation — an instance loaded
        // before the account existed would answer null and let a second
        // application through.
        if (Seller::where('user_id', $user->id)->exists()) {
            return response()->json([
                'status' => 'error',
                'message' => 'You have already applied to sell.',
            ], 409);
        }

        $validated = $request->validate([
            'display_name' => 'required|string|max:120',
            'support_email' => 'nullable|email|max:150',
            'support_phone' => 'nullable|string|max:20',
        ]);

        $seller = DB::transaction(function () use ($validated, $user) {
            $seller = Seller::create([
                ...$validated,
                'user_id' => $user->id,
                'slug' => $this->uniqueSlug($validated['display_name']),
                // Terms are the platform's to set, never the applicant's.
                'commission_rate' => (float) config('marketplace.default_commission_rate', 10),
                'status' => 'PENDING',
            ]);

            $seller->kyc()->create([
                'business_type' => 'INDIVIDUAL',
                'legal_name' => $user->name,
            ]);

            // The role changes now so the onboarding area is reachable, but it
            // grants nothing on its own — every seller route also checks the
            // account's standing.
            $user->forceFill(['role' => User::ROLE_SELLER])->save();

            return $seller;
        });

        return response()->json([
            'status' => 'success',
            'message' => 'Application started. Complete your details to submit for review.',
            'data' => $this->overview($seller->fresh(['kyc', 'documents'])),
        ], 201);
    }

    /** Where the applicant is, and what is still missing. */
    public function show(Request $request)
    {
        return response()->json([
            'status' => 'success',
            'data' => $this->overview($this->sellerFor($request)),
        ]);
    }

    /** Save identity and settlement details while the form is still open. */
    public function saveKyc(Request $request)
    {
        $seller = $this->sellerFor($request);
        $kyc = $seller->kyc;

        if (! $kyc->isEditable()) {
            return response()->json([
                'status' => 'error',
                'message' => $kyc->isApproved()
                    ? 'Your details are verified and can no longer be edited here.'
                    : 'Your application is under review and cannot be edited right now.',
            ], 422);
        }

        // Normalised before validation, not after: a PAN typed in lower case is
        // a valid PAN, and rejecting it for the shift key is the kind of
        // friction that ends an onboarding. This also keeps the blind index
        // stable and stops a reviewer comparing "abcde1234f" against a document
        // that reads ABCDE1234F.
        foreach (['pan', 'gstin', 'bank_ifsc'] as $field) {
            if ($request->filled($field)) {
                $request->merge([$field => strtoupper(trim($request->input($field)))]);
            }
        }

        $validated = $request->validate([
            'business_type' => ['sometimes', Rule::in(SellerKycProfile::BUSINESS_TYPES)],
            'legal_name' => 'sometimes|string|max:200',
            'pan' => ['sometimes', 'nullable', 'string', 'regex:'.self::PAN_REGEX],
            'gstin' => ['sometimes', 'nullable', 'string', 'regex:'.self::GSTIN_REGEX],
            'registered_line1' => 'sometimes|nullable|string|max:255',
            'registered_line2' => 'sometimes|nullable|string|max:255',
            'registered_city' => 'sometimes|nullable|string|max:80',
            'registered_state' => 'sometimes|nullable|string|max:80',
            'registered_pincode' => ['sometimes', 'nullable', 'string', 'regex:/^[1-9][0-9]{5}$/'],
            'bank_account_holder' => 'sometimes|nullable|string|max:150',
            'bank_account_number' => ['sometimes', 'nullable', 'string', 'regex:/^[0-9]{9,18}$/'],
            'bank_ifsc' => ['sometimes', 'nullable', 'string', 'regex:'.self::IFSC_REGEX],
            'bank_name' => 'sometimes|nullable|string|max:120',
        ], [
            'pan.regex' => 'That does not look like a PAN (for example ABCDE1234F).',
            'gstin.regex' => 'That does not look like a GSTIN.',
            'bank_ifsc.regex' => 'That does not look like an IFSC code (for example HDFC0001234).',
            'bank_account_number.regex' => 'An account number is 9 to 18 digits.',
            // Without this the framework says "the registered pincode field
            // format is invalid", which tells the applicant nothing about what
            // a valid one looks like.
            'registered_pincode.regex' => 'A PIN code is 6 digits and cannot start with 0.',
        ]);

        if (filled($validated['pan'] ?? null)) {
            $this->assertPanUnclaimed($validated['pan'], $kyc);
        }

        $kyc->update($validated);

        return response()->json([
            'status' => 'success',
            'data' => $this->overview($seller->fresh(['kyc', 'documents'])),
        ]);
    }

    /**
     * One PAN, one shop.
     *
     * Compared through the blind index, so this never has to decrypt every
     * other seller's PAN to answer the question.
     */
    private function assertPanUnclaimed(string $pan, SellerKycProfile $kyc): void
    {
        $taken = SellerKycProfile::where('pan_hash', SellerKycProfile::hashPan($pan))
            ->whereKeyNot($kyc->id)
            ->exists();

        if ($taken) {
            throw ValidationException::withMessages([
                'pan' => ['This PAN is already registered to another seller account.'],
            ]);
        }
    }

    /** Upload a supporting document to the private disk. */
    public function uploadDocument(Request $request)
    {
        $seller = $this->sellerFor($request);

        if (! $seller->kyc->isEditable()) {
            return response()->json([
                'status' => 'error',
                'message' => 'Your application is under review and cannot be edited right now.',
            ], 422);
        }

        $validated = $request->validate([
            'kind' => ['required', Rule::in(SellerDocument::KINDS)],
            // Images and PDFs only, and small. `mimes` checks the real type, not
            // the extension the client claims.
            'file' => 'required|file|mimes:jpg,jpeg,png,webp,pdf|max:5120',
        ]);

        $file = $request->file('file');

        // The private disk, never `public` — these are identity documents, and
        // the product-image disk is served straight off a guessable URL. `private`
        // is the server disk until a private bucket is configured in the admin
        // panel, then the bucket; the row records which, so old files stay readable.
        $path = $file->store('seller-kyc/'.$seller->id, 'private');

        // One document per kind: re-uploading replaces rather than accumulating
        // near-identical scans for a reviewer to pick between.
        $seller->documents()->where('kind', $validated['kind'])->get()
            ->each(fn (SellerDocument $d) => $d->deleteWithFile());

        $document = $seller->documents()->create([
            'kind' => $validated['kind'],
            'disk' => 'private',
            'path' => $path,
            'original_name' => $file->getClientOriginalName(),
            'mime' => $file->getClientMimeType(),
            'size_bytes' => $file->getSize(),
            'uploaded_by' => $request->user()->id,
        ]);

        return response()->json([
            'status' => 'success',
            'data' => ['document' => $document, 'onboarding' => $this->overview($seller->fresh(['kyc', 'documents']))],
        ], 201);
    }

    public function deleteDocument(Request $request, $id)
    {
        $seller = $this->sellerFor($request);
        $document = $seller->documents()->find($id);

        if (! $document) {
            return response()->json(['status' => 'error', 'message' => 'Document not found'], 404);
        }

        if (! $seller->kyc->isEditable()) {
            return response()->json([
                'status' => 'error',
                'message' => 'Your application is under review and cannot be edited right now.',
            ], 422);
        }

        $document->deleteWithFile();

        return response()->json([
            'status' => 'success',
            'data' => $this->overview($seller->fresh(['kyc', 'documents'])),
        ]);
    }

    /**
     * Stream a document to someone entitled to see it: the seller it belongs
     * to, or staff reviewing it. The file never gets a public URL.
     */
    public function downloadDocument(Request $request, $id)
    {
        $document = SellerDocument::find($id);

        if (! $document) {
            return response()->json(['status' => 'error', 'message' => 'Document not found'], 404);
        }

        $user = $request->user();
        $isOwner = $document->seller_id === $user->seller?->id;

        if (! $isOwner && ! $user->isAdmin()) {
            return response()->json(['status' => 'error', 'message' => 'Forbidden'], 403);
        }

        if (! $document->exists()) {
            return response()->json(['status' => 'error', 'message' => 'The stored file is missing.'], 410);
        }

        return \Illuminate\Support\Facades\Storage::disk($document->disk)
            ->download($document->path, $document->original_name);
    }

    /** Lock the application and hand it to a reviewer. */
    public function submit(Request $request)
    {
        $seller = $this->sellerFor($request);
        $kyc = $seller->kyc;

        if (! $kyc->isEditable()) {
            return response()->json([
                'status' => 'error',
                'message' => $kyc->isApproved()
                    ? 'Your account is already verified.'
                    : 'Your application is already under review.',
            ], 422);
        }

        $missingFields = $kyc->missingFields();
        $missingDocuments = $this->missingDocuments($seller);

        if ($missingFields || $missingDocuments) {
            throw ValidationException::withMessages([
                'onboarding' => ['Your application is not complete yet.'],
                'missing_fields' => $missingFields,
                'missing_documents' => $missingDocuments,
            ]);
        }

        $kyc->forceFill([
            'status' => 'SUBMITTED',
            'submitted_at' => now(),
            // Cleared so a resubmission isn't presented alongside the reason the
            // previous attempt was turned down.
            'rejection_reason' => null,
        ])->save();

        return response()->json([
            'status' => 'success',
            'message' => 'Submitted for review. We usually respond within two business days.',
            'data' => $this->overview($seller->fresh(['kyc', 'documents'])),
        ]);
    }

    // ── Helpers ──────────────────────────────────────────────────────────

    private function sellerFor(Request $request): Seller
    {
        $seller = $request->user()->seller;

        // The owner's own shop is created without an application, so it has no
        // KYC row yet; give it an empty one rather than failing the screen.
        $seller->kyc()->firstOrCreate([], [
            'business_type' => 'INDIVIDUAL',
            'legal_name' => $request->user()->name,
        ]);

        return $seller->load(['kyc', 'documents']);
    }

    /**
     * GST_CERTIFICATE is only expected once a GSTIN has been entered, and
     * INCORPORATION_CERT only from registered entities — asking a sole trader
     * for a certificate of incorporation is how an onboarding flow stalls.
     */
    private function missingDocuments(Seller $seller): array
    {
        $required = SellerDocument::REQUIRED_KINDS;

        if (filled($seller->kyc->gstin)) {
            $required[] = 'GST_CERTIFICATE';
        }

        if (in_array($seller->kyc->business_type, ['LLP', 'PRIVATE_LIMITED', 'PARTNERSHIP'], true)) {
            $required[] = 'INCORPORATION_CERT';
        }

        $held = $seller->documents->pluck('kind')->all();

        return array_values(array_diff($required, $held));
    }

    /** The whole onboarding state in one payload, so the UI never guesses. */
    private function overview(Seller $seller): array
    {
        $kyc = $seller->kyc;
        $missingFields = $kyc->missingFields();
        $missingDocuments = $this->missingDocuments($seller);

        return [
            'seller' => [
                'id' => $seller->id,
                'display_name' => $seller->display_name,
                'slug' => $seller->slug,
                'status' => $seller->status,
                'support_email' => $seller->support_email,
                'support_phone' => $seller->support_phone,
                'commission_rate' => (float) $seller->commission_rate,
            ],
            'kyc' => $kyc->maskedAttributes(),
            'documents' => $seller->documents->map(fn (SellerDocument $d) => [
                'id' => $d->id,
                'kind' => $d->kind,
                'original_name' => $d->original_name,
                'size_bytes' => $d->size_bytes,
                'uploaded_at' => $d->created_at,
            ])->values(),
            'checklist' => [
                'missing_fields' => $missingFields,
                'missing_documents' => $missingDocuments,
                'can_submit' => $kyc->isEditable() && ! $missingFields && ! $missingDocuments,
                'editable' => $kyc->isEditable(),
            ],
            'accepted_document_kinds' => SellerDocument::KINDS,
            'business_types' => SellerKycProfile::BUSINESS_TYPES,
        ];
    }

    private function uniqueSlug(string $name): string
    {
        $base = Str::slug($name) ?: 'seller';
        $slug = $base;

        while (Seller::where('slug', $slug)->exists()) {
            $slug = $base.'-'.Str::lower(Str::random(4));
        }

        return $slug;
    }
}
