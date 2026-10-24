<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Integration credentials and operational settings that an admin manages from the
 * panel instead of .env.
 *
 * `value` holds an *encrypted* payload, never the setting itself — see
 * App\Integrations\IntegrationSettings. It is a text column because the
 * ciphertext of even a short secret is long.
 *
 * The audit table records who changed what and when, and a short keyed
 * fingerprint of the old and new value so a change is visible as a change
 * without the value ever being written down. It has no update or delete path.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('integration_settings', function (Blueprint $table) {
            $table->string('key')->primary();
            $table->text('value');
            $table->uuid('updated_by')->nullable();
            $table->timestamps();
        });

        Schema::create('integration_audit_logs', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('user_id')->nullable();
            $table->string('action');           // SET, CLEAR, TEST, DENIED
            $table->string('group');
            $table->string('field')->nullable();
            $table->string('outcome');          // ok, failed, invalid_password, throttled, ...
            $table->string('fingerprint_old', 32)->nullable();
            $table->string('fingerprint_new', 32)->nullable();
            $table->string('ip', 64)->nullable();
            $table->timestamp('created_at')->useCurrent();

            $table->index('created_at');
            $table->index(['user_id', 'created_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('integration_audit_logs');
        Schema::dropIfExists('integration_settings');
    }
};
