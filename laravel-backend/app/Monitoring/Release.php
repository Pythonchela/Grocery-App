<?php

namespace App\Monitoring;

/**
 * The git commit this deployment is running, so an error report says which deploy
 * it came from. Read from the checkout itself (no `git` binary, no shell), at the
 * time `config:cache` runs - which deploy.sh does right after pulling - so it
 * names the code that was just deployed.
 *
 * SENTRY_RELEASE, if set, wins. Returns null when there is no checkout to read
 * (a Docker image built without .git), which Sentry accepts.
 */
final class Release
{
    public static function detect(?string $gitDir = null): ?string
    {
        $gitDir ??= base_path('../.git');
        $head = is_file("{$gitDir}/HEAD") ? trim((string) @file_get_contents("{$gitDir}/HEAD")) : '';

        if ($head === '') {
            return null;
        }

        // Detached HEAD: the file is the commit itself.
        if (preg_match('/^[0-9a-f]{40}$/', $head)) {
            return substr($head, 0, 12);
        }

        if (! str_starts_with($head, 'ref: ')) {
            return null;
        }

        $ref = trim(substr($head, 5));

        // A ref name is used as a path below, so hold it to the shape git allows.
        if (! preg_match('#^refs/[A-Za-z0-9._/\-]+$#', $ref) || str_contains($ref, '..')) {
            return null;
        }

        if (is_file("{$gitDir}/{$ref}")) {
            $sha = trim((string) @file_get_contents("{$gitDir}/{$ref}"));

            return preg_match('/^[0-9a-f]{40}$/', $sha) ? substr($sha, 0, 12) : null;
        }

        // Packed refs: "<sha> <ref>" per line.
        foreach (is_file("{$gitDir}/packed-refs") ? (file("{$gitDir}/packed-refs", FILE_IGNORE_NEW_LINES) ?: []) : [] as $line) {
            if (preg_match('/^([0-9a-f]{40}) '.preg_quote($ref, '/').'$/', $line, $m)) {
                return substr($m[1], 0, 12);
            }
        }

        return null;
    }
}
