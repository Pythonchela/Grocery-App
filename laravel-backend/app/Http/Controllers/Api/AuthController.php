<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\User;
use App\Services\GoogleIdentityService;
use App\Services\ReferralService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

class AuthController extends Controller
{
    public function register(Request $request)
    {
        $validated = $request->validate([
            'name' => 'required|string|max:255',
            'email' => 'required|email|unique:users,email',
            'phone' => 'nullable|string|unique:users,phone',
            'password' => 'required|string|min:8',
            'referral_code' => 'nullable|string|max:32',
        ]);

        $user = User::create([
            'name' => $validated['name'],
            'email' => $validated['email'],
            'phone' => $validated['phone'] ?? null,
            'password' => Hash::make($validated['password']),
            'role' => 'CUSTOMER',
        ]);

        // `status` is deliberately not mass-assignable, so the insert falls
        // through to the column default and the in-memory model still has it as
        // null. Without this reload the API hands back a user whose status is
        // null — the same defect that made phone-OTP signup reject itself.
        $user->refresh();

        $referrals = app(ReferralService::class);
        $referrals->ensureCode($user);

        // Recorded now, but neither side is paid until this user's first order.
        if (! empty($validated['referral_code'])) {
            $referrals->attach($user, $validated['referral_code']);
        }

        $token = $user->createToken('api-token')->plainTextToken;

        return response()->json([
            'status' => 'success',
            'data' => ['user' => $user->fresh(), 'token' => $token],
        ], 201);
    }

    /**
     * Sign in (or sign up) with a Google ID token.
     *
     * Deliberately one endpoint, not two: from the user's side "sign in with
     * Google" is a single action, and making them pick sign-in vs sign-up first
     * is the friction the button exists to remove.
     *
     * Account linking is by verified email, and only in one direction: an
     * existing password account gains a Google identity, but a Google account
     * never gains a password. Somebody who signs up with Google and later wants
     * a password goes through the reset flow, which proves the mailbox again.
     */
    public function google(Request $request, GoogleIdentityService $google, ReferralService $referrals)
    {
        $validated = $request->validate([
            'id_token' => 'required|string',
            'referral_code' => 'nullable|string|max:32',
        ]);

        try {
            $profile = $google->verify($validated['id_token']);
        } catch (\RuntimeException $e) {
            throw ValidationException::withMessages(['id_token' => [$e->getMessage()]]);
        }

        $user = User::where('google_id', $profile['sub'])->first();

        if (! $user) {
            // No Google identity yet. If the verified email already has an
            // account, attach to it rather than creating a duplicate — two
            // accounts on one email is how order history goes missing.
            $user = User::whereRaw('LOWER(email) = ?', [$profile['email']])->first();

            // Refused *before* anything is attached, not after: a staff account
            // must not end up carrying a Google identity it never asked for.
            if ($user && $user->isAdmin()) {
                throw ValidationException::withMessages([
                    'email' => ['This is a staff account. Please sign in with your email and password.'],
                ]);
            }

            if ($user) {
                $user->forceFill([
                    'google_id' => $profile['sub'],
                    'email_verified_at' => $user->email_verified_at ?? now(),
                ])->save();
            } else {
                $user = User::create([
                    'name' => $profile['name'] !== '' ? $profile['name'] : 'Customer',
                    'email' => $profile['email'],
                    'avatar' => $profile['picture'],
                ]);

                // password stays null, and status/verification are not
                // mass-assignable — the same guard that silently broke OTP
                // signup, so they are set explicitly here.
                $user->forceFill([
                    'google_id' => $profile['sub'],
                    'auth_provider' => 'GOOGLE',
                    'email_verified_at' => now(),
                    'status' => 'ACTIVE',
                    'role' => 'CUSTOMER',
                ])->save();

                $referrals->ensureCode($user);

                if (! empty($validated['referral_code'])) {
                    $referrals->attach($user, $validated['referral_code']);
                }
            }
        }

        // Staff never sign in through Google, and are never attached to a Google
        // identity by an email match. Otherwise whoever can present a Google
        // account with that address gains admin access without the password —
        // the highest privilege in the app should not hinge on an email match.
        // This also covers an account that already carries a google_id.
        if ($user->isAdmin()) {
            throw ValidationException::withMessages([
                'email' => ['This is a staff account. Please sign in with your email and password.'],
            ]);
        }

        if ($user->status !== 'ACTIVE') {
            throw ValidationException::withMessages(['email' => ['This account has been blocked.']]);
        }

        $token = $user->createToken('api-token')->plainTextToken;

        return response()->json([
            'status' => 'success',
            'data' => ['user' => $user->fresh(), 'token' => $token],
        ]);
    }

    public function login(Request $request)
    {
        $validated = $request->validate([
            'email' => 'required|email',
            'password' => 'required|string',
        ]);

        $user = User::where('email', $validated['email'])->first();

        if (! $user || ! Hash::check($validated['password'], $user->password)) {
            throw ValidationException::withMessages([
                'email' => ['The provided credentials are incorrect.'],
            ]);
        }

        if ($user->status !== 'ACTIVE') {
            throw ValidationException::withMessages([
                'email' => ['This account has been blocked.'],
            ]);
        }

        $token = $user->createToken('api-token')->plainTextToken;

        return response()->json([
            'status' => 'success',
            'data' => ['user' => $user, 'token' => $token],
        ]);
    }

    public function logout(Request $request)
    {
        $request->user()->currentAccessToken()->delete();

        return response()->json(['status' => 'success', 'message' => 'Logged out']);
    }

    public function me(Request $request)
    {
        return response()->json(['status' => 'success', 'data' => $request->user()]);
    }

    public function sendOtp(Request $request)
    {
        $validated = $request->validate([
            'phone' => 'required|string|regex:/^[0-9]{10}$/',
        ]);

        // With no SMS provider, in production, "sent" would be a lie and nobody could
        // ever sign in by phone. Say so, so it is noticed and fixed, instead of
        // quietly writing codes into a log.
        if (! app(\App\Services\Messaging\SmsGatewayManager::class)->canDeliver()) {
            \Illuminate\Support\Facades\Log::error('[OTP] no SMS provider is configured; cannot send login codes');

            return response()->json([
                'status' => 'error',
                'message' => 'Sign-in by phone is unavailable right now. Please use email or Google.',
            ], 503);
        }

        // random_int(), not rand() — rand() is seeded and predictable, which
        // would let an attacker who has seen one OTP derive the next.
        $otp = (string) random_int(100000, 999999);

        try {
            app(\App\Services\NotificationService::class)->sendOtp($validated['phone'], $otp);
        } catch (\App\Services\Messaging\SmsDeliveryException $e) {
            // Nothing was sent, so nothing is stored: a code nobody received must
            // not stay guessable for five minutes.
            report($e);

            return response()->json([
                'status' => 'error',
                'message' => 'We could not send the code. Please try again in a moment.',
            ], 503);
        }

        \Illuminate\Support\Facades\Cache::put(self::otpKey($validated['phone']), self::otpDigest($otp), now()->addMinutes(5));

        return response()->json([
            'status' => 'success',
            'message' => 'We have sent a code to your phone.',
        ]);
    }

    /** Cache key for a phone's pending code. */
    private static function otpKey(string $phone): string
    {
        return 'otp_'.$phone;
    }

    /**
     * What is stored instead of the code, so reading the cache (a shared Redis, a
     * dump) does not reveal a code that is still valid. Keyed with APP_KEY: six
     * digits alone could be brute-forced from a bare hash.
     */
    private static function otpDigest(string $otp): string
    {
        return hash_hmac('sha256', $otp, (string) config('app.key'));
    }

    public function verifyOtp(Request $request)
    {
        $validated = $request->validate([
            'phone' => 'required|string|regex:/^[0-9]{10}$/',
            'otp' => 'required|string|size:6',
        ]);

        $stored = \Illuminate\Support\Facades\Cache::get(self::otpKey($validated['phone']));

        // hash_equals, not != — constant-time, so response latency can't be used
        // to narrow the code down digit by digit.
        if (! $stored || ! hash_equals((string) $stored, self::otpDigest($validated['otp']))) {
            throw ValidationException::withMessages([
                'otp' => ['Invalid or expired OTP.'],
            ]);
        }

        \Illuminate\Support\Facades\Cache::forget(self::otpKey($validated['phone']));

        // Find or create user
        $user = User::firstOrCreate(
            ['phone' => $validated['phone']],
            [
                'name' => 'User ' . substr($validated['phone'], -4),
                'email' => $validated['phone'] . '@example.com', // Dummy email as it's required
                'password' => Hash::make(uniqid()),
                'role' => 'CUSTOMER',
            ]
        );

        if ($user->wasRecentlyCreated) {
            // `status` is deliberately not mass-assignable, so the insert falls
            // through to the column default ('ACTIVE') and the in-memory model
            // still has it as null. Without this reload the check below rejects
            // every brand-new phone signup as "blocked".
            $user->refresh();

            // Same code issuance the email/password path does, so OTP signups
            // aren't silently excluded from the referral programme.
            app(ReferralService::class)->ensureCode($user);
        }

        if ($user->status !== 'ACTIVE') {
            throw ValidationException::withMessages([
                'phone' => ['This account has been blocked.'],
            ]);
        }

        $token = $user->createToken('api-token')->plainTextToken;

        return response()->json([
            'status' => 'success',
            'data' => ['user' => $user, 'token' => $token],
        ]);
    }
}
