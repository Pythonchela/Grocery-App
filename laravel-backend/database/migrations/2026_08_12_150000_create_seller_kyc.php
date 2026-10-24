<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Identity and settlement details for a merchant, and the documents backing
 * them.
 *
 * Kept in its own table rather than on `sellers` for two reasons. The catalog
 * joins `sellers` on every product query and has no business touching a PAN;
 * and a separate table makes "who may read this" a table-level question instead
 * of a column-by-column one that some future `select *` will get wrong.
 *
 * The sensitive columns are `text` because they hold Laravel's encrypted
 * payloads, which are far longer than the values themselves — a PAN is ten
 * characters, its ciphertext is a few hundred. They are consequently not
 * searchable or indexable, which is the correct trade for identity numbers.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('seller_kyc_profiles', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('seller_id')->unique();

            $table->string('business_type'); // INDIVIDUAL, PROPRIETORSHIP, PARTNERSHIP, LLP, PRIVATE_LIMITED
            $table->string('legal_name');

            // Encrypted at rest.
            $table->text('pan')->nullable();
            $table->text('gstin')->nullable(); // below the threshold, a seller may have none

            // Blind index: a keyed hash of the PAN, so "has this PAN already
            // registered a shop" is answerable without the column being
            // readable. Encryption alone can't do this — two encryptions of the
            // same PAN produce different ciphertext, so a unique constraint on
            // the encrypted column would never fire.
            $table->string('pan_hash', 64)->nullable()->unique();

            $table->string('registered_line1')->nullable();
            $table->string('registered_line2')->nullable();
            $table->string('registered_city')->nullable();
            $table->string('registered_state')->nullable();
            $table->string('registered_pincode', 6)->nullable();

            $table->string('bank_account_holder')->nullable();
            $table->text('bank_account_number')->nullable(); // encrypted
            $table->string('bank_ifsc', 11)->nullable();
            $table->string('bank_name')->nullable();

            // DRAFT -> SUBMITTED -> APPROVED | REJECTED. A rejection returns it
            // to the seller to correct and resubmit; it does not delete anything.
            $table->string('status')->default('DRAFT');
            $table->timestamp('submitted_at')->nullable();
            $table->timestamp('reviewed_at')->nullable();
            $table->uuid('reviewed_by')->nullable();
            $table->text('rejection_reason')->nullable();

            $table->timestamps();

            $table->foreign('seller_id')->references('id')->on('sellers')->onDelete('cascade');
            $table->foreign('reviewed_by')->references('id')->on('users')->onDelete('set null');
            $table->index('status');
        });

        Schema::create('seller_documents', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('seller_id');

            $table->string('kind'); // PAN_CARD, GST_CERTIFICATE, CANCELLED_CHEQUE, ADDRESS_PROOF, INCORPORATION_CERT

            // Always a private disk. These are identity documents; the `public`
            // disk the product images use would put them on a guessable URL with
            // no auth in front of it.
            $table->string('disk')->default('local');
            $table->string('path');

            $table->string('original_name');
            $table->string('mime', 100);
            $table->unsignedBigInteger('size_bytes');
            $table->uuid('uploaded_by')->nullable();
            $table->timestamps();

            $table->foreign('seller_id')->references('id')->on('sellers')->onDelete('cascade');
            $table->foreign('uploaded_by')->references('id')->on('users')->onDelete('set null');
            $table->index(['seller_id', 'kind']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('seller_documents');
        Schema::dropIfExists('seller_kyc_profiles');
    }
};
