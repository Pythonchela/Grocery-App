<?php

namespace App\Console\Commands;

use App\Console\Commands\Concerns\CopiesFiles;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\Storage;
use Throwable;

/**
 * Moves the product images already on the server's disk into the bucket chosen in
 * the admin panel, and points the database at the new addresses.
 *
 * Switching storage in the admin panel only affects NEW uploads. Images uploaded
 * before then stay where they were, and their full URLs are stored in the database
 * (products, categories, banners...). This command copies the files, checks each
 * arrived, and only then rewrites the URLs.
 *
 *     php artisan media:migrate            # dry run: what would happen
 *     php artisan media:migrate --apply    # do it
 *
 * Safe to run twice: files already copied are skipped, and URLs already rewritten
 * no longer match. Nothing is deleted from the server disk.
 */
class MigrateMedia extends Command
{
    use CopiesFiles;

    protected $signature = 'media:migrate
        {--apply : Actually copy and rewrite (without this, only report)}
        {--from=public : The disk the files are on now}
        {--to=media : The disk to move them to}
        {--path=uploads : Only this folder}
        {--old-url= : The address the old files are served from (default: APP_URL/storage)}
        {--skip-rewrite : Copy the files but leave the database alone}';

    protected $description = 'Copy uploaded images to the configured bucket and rewrite their URLs';

    /** Tables whose text is never a place for image URLs, or that must not be touched. */
    private const SKIP_TABLES = [
        'migrations', 'cache', 'cache_locks', 'sessions', 'jobs', 'job_batches', 'failed_jobs',
        'personal_access_tokens', 'password_reset_tokens', 'integration_settings', 'integration_audit_logs',
    ];

    private const TEXT_TYPES = ['varchar', 'text', 'json', 'jsonb', 'char', 'bpchar', 'tinytext', 'mediumtext', 'longtext', 'citext'];

    public function handle(): int
    {
        $apply = (bool) $this->option('apply');
        $from = Storage::disk((string) $this->option('from'));
        $to = Storage::disk((string) $this->option('to'));

        if (config('filesystems.disks.media.driver') !== 's3') {
            $this->error('The media disk is still the server disk. Choose S3 (Admin -> Integrations -> Image & file storage) and test it first.');

            return self::FAILURE;
        }

        $files = $from->allFiles((string) $this->option('path'));
        $this->info(count($files).' file(s) on the server disk under "'.$this->option('path').'".');

        $copied = $skipped = 0;
        $failed = [];

        foreach ($files as $path) {
            if ($this->alreadyThere($from, $to, $path)) {
                $skipped++;

                continue;
            }

            if (! $apply) {
                $copied++;

                continue;
            }

            try {
                $this->copyVerified($from, $to, $path) ? $copied++ : $failed[] = $path;
            } catch (Throwable $e) {
                $failed[] = $path;
            }
        }

        $this->line(($apply ? 'Copied' : 'Would copy')." {$copied}, already in the bucket {$skipped}, failed ".count($failed).'.');

        if ($failed) {
            $this->error('These files did not copy, so URLs were NOT rewritten:');
            array_map(fn ($p) => $this->line("  {$p}"), array_slice($failed, 0, 20));

            return self::FAILURE;
        }

        if ($this->option('skip-rewrite')) {
            return self::SUCCESS;
        }

        return $this->rewriteUrls($apply);
    }

    private function rewriteUrls(bool $apply): int
    {
        $old = rtrim((string) ($this->option('old-url') ?: rtrim((string) config('app.url'), '/').'/storage'), '/');
        $new = rtrim(Storage::disk((string) $this->option('to'))->url(''), '/');

        if ($old === '' || $new === '' || $old === $new) {
            $this->warn('Nothing to rewrite (the old and new addresses are the same, or empty).');

            return self::SUCCESS;
        }

        $this->line("Rewriting {$old}  ->  {$new}");

        // The same URL appears plain, and with its slashes escaped inside JSON text.
        $pairs = [[$old, $new], [str_replace('/', '\\/', $old), str_replace('/', '\\/', $new)]];
        $total = 0;

        foreach (Schema::getTables() as $table) {
            $name = $table['name'];

            if (in_array($name, self::SKIP_TABLES, true) || ! Schema::hasColumn($name, 'id')) {
                continue;
            }

            foreach (Schema::getColumns($name) as $column) {
                if (! in_array(strtolower((string) $column['type_name']), self::TEXT_TYPES, true) || $column['name'] === 'id') {
                    continue;
                }

                $total += $this->rewriteColumn($name, $column['name'], $pairs, $apply);
            }
        }

        $this->info(($apply ? 'Rewrote' : 'Would rewrite')." {$total} value(s).");

        if (! $apply) {
            $this->comment('This was a dry run. Run again with --apply to do it.');
        }

        return self::SUCCESS;
    }

    /**
     * @param  list<array{0: string, 1: string}>  $pairs
     */
    private function rewriteColumn(string $table, string $column, array $pairs, bool $apply): int
    {
        $grammar = DB::connection()->getQueryGrammar();
        $wrapped = $grammar->wrap($column);
        $count = 0;

        $query = DB::table($table)->select(['id', $column])->where(function ($q) use ($wrapped, $pairs) {
            foreach ($pairs as [$search]) {
                $q->orWhereRaw("CAST({$wrapped} AS TEXT) LIKE ?", ['%'.$search.'%']);
            }
        });

        foreach ($query->cursor() as $row) {
            $value = $row->{$column};

            if (! is_string($value)) {
                continue;
            }

            $updated = $value;
            foreach ($pairs as [$search, $replace]) {
                $updated = str_replace($search, $replace, $updated);
            }

            if ($updated === $value) {
                continue;
            }

            $count++;

            if ($apply) {
                DB::table($table)->where('id', $row->id)->update([$column => $updated]);
            }
        }

        if ($count > 0) {
            $this->line("  {$table}.{$column}: {$count}");
        }

        return $count;
    }
}
