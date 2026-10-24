<?php

namespace App\Console\Commands\Concerns;

use Illuminate\Contracts\Filesystem\Filesystem;

trait CopiesFiles
{
    /**
     * Copy one file between disks and prove it arrived: the same size at the other
     * end. A copy that cannot be proved is reported as failed, so nothing downstream
     * (rewriting URLs, deleting the source) acts on a file that is not there.
     */
    protected function copyVerified(Filesystem $from, Filesystem $to, string $path): bool
    {
        $stream = $from->readStream($path);

        if (! is_resource($stream)) {
            return false;
        }

        try {
            $to->writeStream($path, $stream);
        } finally {
            fclose($stream);
        }

        return $to->exists($path) && $to->size($path) === $from->size($path);
    }

    /** Whether a file is already at the destination, complete. */
    protected function alreadyThere(Filesystem $from, Filesystem $to, string $path): bool
    {
        return $to->exists($path) && $to->size($path) === $from->size($path);
    }
}
