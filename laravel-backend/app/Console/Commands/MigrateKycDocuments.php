<?php

namespace App\Console\Commands;

use App\Console\Commands\Concerns\CopiesFiles;
use App\Models\SellerDocument;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Storage;
use Throwable;

/**
 * Moves seller identity documents from the server's disk to the private bucket.
 *
 * Each document row records which disk its file is on, so old files stay readable
 * while they are moved one at a time: a row is only switched to the private disk
 * after its file is proved to be there.
 *
 *     php artisan kyc:migrate                          # dry run
 *     php artisan kyc:migrate --apply                  # copy, keep the originals
 *     php artisan kyc:migrate --apply --delete-source  # copy, then remove the originals
 *
 * The originals are kept unless asked otherwise: for identity documents, a copy
 * you can check is worth more than the disk space.
 */
class MigrateKycDocuments extends Command
{
    use CopiesFiles;

    protected $signature = 'kyc:migrate
        {--apply : Actually copy (without this, only report)}
        {--delete-source : Remove the original from the server disk once the copy is verified}';

    protected $description = 'Move seller KYC documents to the private bucket';

    public function handle(): int
    {
        if (config('filesystems.disks.private.driver') !== 's3') {
            $this->error('The private disk is still the server disk. Choose S3 (Admin -> Integrations -> Image & file storage) and test it first.');

            return self::FAILURE;
        }

        $apply = (bool) $this->option('apply');
        $private = Storage::disk('private');

        $documents = SellerDocument::query()->where('disk', '!=', 'private')->get();
        $this->info($documents->count().' document(s) are not on the private disk yet.');

        $moved = $missing = $failed = 0;

        foreach ($documents as $document) {
            $source = Storage::disk($document->disk);

            if (! $source->exists($document->path)) {
                $missing++;
                $this->warn("  document {$document->id}: the file is missing on disk '{$document->disk}'");

                continue;
            }

            if (! $apply) {
                $moved++;

                continue;
            }

            try {
                if (! $this->alreadyThere($source, $private, $document->path) && ! $this->copyVerified($source, $private, $document->path)) {
                    $failed++;
                    $this->error("  document {$document->id}: the copy could not be verified");

                    continue;
                }
            } catch (Throwable $e) {
                $failed++;
                $this->error("  document {$document->id}: ".$e::class);

                continue;
            }

            $original = $document->disk;
            $document->forceFill(['disk' => 'private'])->save();

            if ($this->option('delete-source')) {
                $source = Storage::disk($original);
                $source->delete($document->path);
            }

            $moved++;
        }

        $this->line(($apply ? 'Moved' : 'Would move')." {$moved}, missing {$missing}, failed {$failed}.");

        if (! $apply) {
            $this->comment('This was a dry run. Run again with --apply to do it.');
        }

        return $failed > 0 ? self::FAILURE : self::SUCCESS;
    }
}
