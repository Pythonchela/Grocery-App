<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;
use Throwable;

/**
 * Image upload for the catalogue. Writes to the `media` disk, which is the server's
 * own disk until a bucket is chosen in the admin panel (Image & file storage) and
 * then the bucket. This controller does not change either way.
 */
class UploadController extends Controller
{
    public function store(Request $request)
    {
        $request->validate([
            'file' => 'required|file|mimes:jpg,jpeg,png,webp,gif,mp4,webm|max:10240',
        ]);

        try {
            $path = $request->file('file')->store('uploads', 'media');
        } catch (Throwable $e) {
            // A misconfigured bucket or a full disk. Reported (to the log and to
            // Sentry), and answered plainly rather than with a stack trace.
            report($e);

            return response()->json([
                'status' => 'error',
                'message' => 'The file could not be saved. Please try again; if it keeps failing, check the storage settings.',
            ], 503);
        }

        // On the server disk the URL is built from the request, exactly as before,
        // so existing installs keep working whatever APP_URL says.
        $url = config('filesystems.disks.media.driver') === 'local'
            ? asset('storage/'.$path)
            : Storage::disk('media')->url($path);

        return response()->json([
            'status' => 'success',
            'data' => [
                'path' => $path,
                'url' => $url,
            ],
        ], 201);
    }
}
