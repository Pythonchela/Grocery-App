<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('category_requests', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('seller_id')->constrained()->cascadeOnDelete();
            $table->string('name', 120);
            $table->text('reason')->nullable();
            $table->string('status', 20)->default('PENDING');
            $table->foreignUuid('category_id')->nullable()->constrained()->nullOnDelete();
            $table->text('admin_note')->nullable();
            $table->timestamps();
            $table->index(['seller_id', 'status']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('category_requests');
    }
};
