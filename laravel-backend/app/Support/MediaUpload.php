<?php

namespace App\Support;

use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;

/**
 * Saves a catalogue picture to the `media` disk (the server's own disk until a
 * bucket is chosen in Settings) and returns its public URL. Shared by the upload
 * endpoint and the product importer, so a photo lands in the same place and gets
 * the same kind of URL whichever way it arrived.
 */
final class MediaUpload
{
    /** @throws \Throwable when the disk cannot be written */
    public static function store(UploadedFile $file): string
    {
        $path = $file->store('uploads', 'media');

        // On the server disk the URL is built from the request, so existing installs
        // keep working whatever APP_URL says.
        return config('filesystems.disks.media.driver') === 'local'
            ? asset('storage/'.$path)
            : Storage::disk('media')->url($path);
    }
}
