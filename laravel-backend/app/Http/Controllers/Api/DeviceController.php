<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\DeviceToken;
use Illuminate\Http\Request;

/**
 * The phone tells us where to send push notifications, and when to stop.
 */
class DeviceController extends Controller
{
    /** Register (or re-register) this install for the signed-in user. */
    public function store(Request $request)
    {
        $validated = $request->validate([
            'token' => 'required|string|min:20|max:512',
            'platform' => 'nullable|in:android,ios',
            'app_version' => 'nullable|string|max:32',
        ]);

        // updateOrCreate on the token: if the handset was previously signed in as
        // someone else, the row is reassigned instead of duplicated.
        $device = DeviceToken::updateOrCreate(
            ['token' => $validated['token']],
            [
                'user_id' => $request->user()->id,
                'platform' => $validated['platform'] ?? 'android',
                'app_version' => $validated['app_version'] ?? null,
                'last_seen_at' => now(),
            ],
        );

        return response()->json(['status' => 'success', 'data' => ['id' => $device->id]], 201);
    }

    /** Stop sending to this install (sign-out, or notifications turned off). */
    public function destroy(Request $request)
    {
        $validated = $request->validate(['token' => 'required|string|max:512']);

        // Scoped to the caller, so one account cannot unsubscribe another's phone.
        DeviceToken::where('user_id', $request->user()->id)
            ->where('token', $validated['token'])
            ->delete();

        return response()->json(['status' => 'success', 'message' => 'Device removed']);
    }
}
