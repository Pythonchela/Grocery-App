<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('return_requests', function (Blueprint $table) {
            $table->string('seller_recommendation', 20)->nullable();
            $table->text('seller_note')->nullable();
            $table->timestamp('seller_reviewed_at')->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('return_requests', function (Blueprint $table) {
            $table->dropColumn(['seller_recommendation', 'seller_note', 'seller_reviewed_at']);
        });
    }
};
