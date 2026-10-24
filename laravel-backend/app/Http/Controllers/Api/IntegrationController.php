<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Integrations\Field;
use App\Integrations\Group;
use App\Integrations\IntegrationSettings;
use App\Integrations\Registry;
use App\Models\IntegrationAuditLog;
use App\Services\Payments\PaymentGatewayManager;
use Illuminate\Http\Exceptions\HttpResponseException;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\Facades\Validator;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

/**
 * The admin panel's "Integrations & API keys".
 *
 * Reachable only by full admins (the route group adds `admin` + `manage-users`),
 * and every change additionally requires the admin to type their password again:
 * a stolen session token alone is not enough to swap a courier's credentials.
 *
 * The rules this controller keeps, all covered by tests:
 *  - no response ever contains a secret — only whether one is set and, for a long
 *    enough secret, its last four characters;
 *  - reads are `no-store`, so a secret-adjacent page is never cached;
 *  - changes need the current password; wrong attempts are throttled and audited;
 *  - the audit log holds fingerprints, never values;
 *  - the connection test calls fixed hosts only and echoes nothing back.
 */
class IntegrationController extends Controller
{
    /** Wrong passwords allowed per admin per 15 minutes before they are locked out. */
    private const REAUTH_ATTEMPTS = 5;

    private const REAUTH_WINDOW = 900;

    public function __construct(private readonly IntegrationSettings $settings) {}

    // ── Reading ─────────────────────────────────────────────────────────

    public function index(Request $request): JsonResponse
    {
        return $this->noStore([
            'status' => 'success',
            'data' => [
                'groups' => array_map(fn (Group $g) => $this->describeGroup($g), Registry::groups()),
                'payments' => $this->paymentsStatus(),
                // Tells the UI to explain, rather than fail, when this admin has no
                // password to confirm with (Google/OTP-created accounts).
                'can_confirm' => $request->user()->password !== null,
                'monitoring' => $this->monitoringStatus(),
            ],
        ]);
    }

    public function audit(): JsonResponse
    {
        $rows = IntegrationAuditLog::query()
            ->with('user:id,name,email')
            ->orderByDesc('created_at')
            ->limit(100)
            ->get()
            ->map(fn (IntegrationAuditLog $l) => [
                'id' => $l->id,
                'at' => $l->created_at,
                'who' => $l->user ? ['name' => $l->user->name, 'email' => $l->user->email] : null,
                'action' => $l->action,
                'group' => $l->group,
                'field' => $l->field,
                'outcome' => $l->outcome,
                'ip' => $l->ip,
                // Enough to tell that two entries were the same value, or that a
                // value changed — not enough to learn anything about it.
                'changed' => $l->fingerprint_old !== $l->fingerprint_new,
            ]);

        return $this->noStore(['status' => 'success', 'data' => $rows]);
    }

    // ── Writing ─────────────────────────────────────────────────────────

    public function update(Request $request, string $group): JsonResponse
    {
        $g = $this->group($group);

        $request->validate([
            'current_password' => 'required|string',
            'values' => 'required|array|min:1',
        ]);

        $this->confirmPassword($request, $g->id);

        $submitted = $request->input('values');
        $this->validateValues($g, $submitted);
        $this->validateTogether($g, $submitted);
        $this->validateRequiredWhen($g, $submitted);
        $this->validateDistinct($g, $submitted);

        $changed = [];

        DB::transaction(function () use ($g, $submitted, $request, &$changed) {
            foreach ($submitted as $name => $value) {
                $field = $g->field($name);
                $clear = $this->isBlank($field, $value);

                // A secret left blank means "keep what is there". A plain setting
                // left blank means "go back to the default".
                if ($clear && $field->isSecret()) {
                    continue;
                }

                $before = $this->effective($field);

                if ($clear) {
                    if (! $this->settings->has($field)) {
                        continue; // nothing of ours to remove
                    }
                    $this->settings->clear($field);
                    $this->record($request, 'CLEAR', $g->id, $field->name, 'ok', $before, $this->effective($field));
                    $changed[] = $field->name;

                    continue;
                }

                // The form sends every field. One that still says what it already
                // said must not become an override — or a later change to the
                // server's own default would silently stop applying.
                if ($this->same($field, $value, $before)) {
                    continue;
                }

                $this->settings->set($field, $field->cast($value), $request->user()->id);
                $this->record($request, 'SET', $g->id, $field->name, 'ok', $before, $field->cast($value));
                $changed[] = $field->name;
            }
        });

        // The cache was refilled inside the transaction; refill it from what is
        // actually committed.
        if ($changed) {
            $this->settings->changed();
        }

        return $this->noStore([
            'status' => 'success',
            'message' => $changed ? 'Saved.' : 'Nothing changed.',
            'changed' => $changed,
            'data' => $this->describeGroup($g),
        ]);
    }

    /** Remove an admin-set value, reverting the field to the server's own. */
    public function destroy(Request $request, string $group, string $field): JsonResponse
    {
        $g = $this->group($group);
        $f = $g->field($field) ?? abort(404, 'Unknown setting.');

        $request->validate(['current_password' => 'required|string']);
        $this->confirmPassword($request, $g->id);

        if ($this->settings->has($f)) {
            $before = $this->effective($f);
            $this->settings->clear($f);
            $this->record($request, 'CLEAR', $g->id, $f->name, 'ok', $before, $this->effective($f));
        }

        return $this->noStore([
            'status' => 'success',
            'message' => 'Reverted to the server setting.',
            'data' => $this->describeGroup($g),
        ]);
    }

    // ── Testing ─────────────────────────────────────────────────────────

    /**
     * Try the credentials against the provider. Needs no password — it reveals
     * nothing — but is rate limited, and accepts candidate values that are NOT
     * saved, so a key can be checked before it replaces a working one.
     */
    public function test(Request $request, string $group): JsonResponse
    {
        $g = $this->group($group);

        $request->validate([
            'values' => 'nullable|array',
            'target' => 'nullable|string|max:40',
        ]);

        $candidates = array_filter((array) $request->input('values', []), fn ($v) => $v !== null && $v !== '');
        $this->validateValues($g, $candidates);

        if ($g->tester === null) {
            return $this->noStore(['status' => 'success', 'data' => ['status' => 'unavailable', 'message' => 'Nothing to test for this group.']]);
        }

        // Saved (or environment) values, with the candidates laid over them.
        $values = [];
        foreach ($g->fields as $field) {
            $values[$field->name] = $candidates[$field->name] ?? $this->current($field);
        }

        // Who a test goes to is decided here, not by the form: an email test always
        // goes to the admin's own address, and a phone number is never written to the
        // audit log.
        $target = $g->id === 'email' ? $request->user()->email : $request->input('target');

        $result = app($g->tester)->test($values, $target);

        $this->record($request, 'TEST', $g->id, $g->id === 'couriers' ? $target : null, $result->status);

        return $this->noStore(['status' => 'success', 'data' => $result->toArray()]);
    }

    // ── Helpers ─────────────────────────────────────────────────────────

    private function group(string $id): Group
    {
        return Registry::group($id) ?? abort(404, 'Unknown integration.');
    }

    /** @return array<string, mixed> */
    private function describeGroup(Group $g): array
    {
        return [
            'id' => $g->id,
            'label' => $g->label,
            'description' => $g->description,
            'status' => $this->settings->status($g),
            'testable' => $g->tester !== null,
            'together' => $g->together,
            'fields' => array_map(fn (Field $f) => $this->settings->describe($f), $g->fields),
        ];
    }

    /**
     * Payments are managed on the server, not here. This only reports how they are
     * set up — never a value — so an admin can see that they work and copy the URL
     * to register with the gateway.
     *
     * @return array<string, mixed>
     */
    private function paymentsStatus(): array
    {
        $keyId = (string) config('services.razorpay.key_id');

        return [
            'managed_here' => false,
            'note' => 'Payment keys are set in the server environment, not in the admin panel.',
            'configured' => filled($keyId) && filled(config('services.razorpay.key_secret')),
            'mode' => match (true) {
                str_starts_with($keyId, 'rzp_live_') => 'live',
                str_starts_with($keyId, 'rzp_test_') => 'test',
                default => null,
            },
            'webhook_secret_set' => filled(config('services.razorpay.webhook_secret')),
            'webhook_url' => url('/api/v1/webhooks/payments/razorpay'),
            'online_payment_available' => app(PaymentGatewayManager::class)->hasOnlinePayment(),
        ];
    }

    /**
     * Error tracking is configured on the server (the DSN is read while the app
     * boots, before any admin setting could apply), so like Payments this only
     * reports how it is set up.
     *
     * @return array<string, mixed>
     */
    private function monitoringStatus(): array
    {
        return [
            'managed_here' => false,
            'note' => 'Error tracking (Sentry) is set in the server environment with SENTRY_LARAVEL_DSN.',
            'configured' => filled(config('sentry.dsn')),
            'environment' => app()->environment(),
        ];
    }

    /** What is in effect for a field right now: the admin's value, else the server's. */
    private function effective(Field $field): mixed
    {
        return $this->settings->value($field) ?? config($field->config[0]);
    }

    /** The same, for server-side use (testing). Never returned in a response. */
    private function current(Field $field): mixed
    {
        return $this->effective($field);
    }

    private function same(Field $field, mixed $submitted, mixed $existing): bool
    {
        if ($existing === null || $existing === '') {
            $existing = $field->cast === 'list' ? [] : '';
        }

        return json_encode($field->cast($submitted)) === json_encode($field->cast($existing));
    }

    private function isBlank(Field $field, mixed $value): bool
    {
        return $value === null || $value === '' || $value === [];
    }

    /** @param  array<string, mixed>  $submitted */
    private function validateValues(Group $g, array $submitted): void
    {
        $rules = [];
        $unknown = [];

        foreach ($submitted as $name => $value) {
            $field = $g->field((string) $name);

            if (! $field) {
                $unknown["values.{$name}"] = ['That setting does not exist.'];

                continue;
            }

            if ($this->isBlank($field, $value)) {
                continue; // a clear, or an unchanged secret — nothing to validate
            }

            $rules["values.{$name}"] = $field->rules;

            if ($field->cast === 'list') {
                $rules["values.{$name}.*"] = [Rule::in($field->options)];
            }
        }

        if ($unknown) {
            throw ValidationException::withMessages($unknown);
        }

        Validator::make(['values' => $submitted], $rules)->validate();
    }

    /**
     * A login needs both halves. Checked against the state the save would leave,
     * and only for a pair being touched — an unrelated edit must not be blocked by
     * an old half-configured pair.
     *
     * @param  array<string, mixed>  $submitted
     */
    private function validateTogether(Group $g, array $submitted): void
    {
        foreach ($g->together as $pair) {
            $touched = collect($pair)->contains(fn ($n) => array_key_exists($n, $submitted) && ! $this->isBlank($g->field($n), $submitted[$n]));

            if (! $touched) {
                continue;
            }

            $present = fn (string $n) => array_key_exists($n, $submitted) && ! $this->isBlank($g->field($n), $submitted[$n])
                ? true
                : filled($this->effective($g->field($n)));

            foreach ($pair as $name) {
                if (! $present($name)) {
                    throw ValidationException::withMessages([
                        "values.{$name}" => ['Enter this as well — the two are used together.'],
                    ]);
                }
            }
        }
    }

    /**
     * What a field will hold once this save is applied: the submitted value; the
     * server's own when a plain setting is blanked (reverting); or what is there now.
     *
     * @param  array<string, mixed>  $submitted
     */
    private function valueAfter(Group $g, string $name, array $submitted): mixed
    {
        $field = $g->field($name);

        if (array_key_exists($name, $submitted)) {
            if (! $this->isBlank($field, $submitted[$name])) {
                return $submitted[$name];
            }

            if (! $field->isSecret()) {
                return $this->settings->environmentValue($field);
            }
        }

        return $this->effective($field);
    }

    /**
     * A choice needs what it needs: picking SMTP needs a host, picking a storage
     * bucket needs credentials. Checked against the state the save would leave, and
     * only when this save touches the choice or something it needs - so an
     * unrelated edit is never blocked by an old half-configured group.
     *
     * @param  array<string, mixed>  $submitted
     */
    private function validateRequiredWhen(Group $g, array $submitted): void
    {
        foreach ($g->requiredWhen as $selector => $choices) {
            $needs = $choices[(string) $this->valueAfter($g, $selector, $submitted)] ?? [];

            $touched = array_key_exists($selector, $submitted)
                || array_intersect($needs, array_keys($submitted)) !== [];

            if (! $touched) {
                continue;
            }

            $errors = [];

            foreach ($needs as $name) {
                if (! $this->isReal($this->valueAfter($g, $name, $submitted))) {
                    $errors["values.{$name}"] = ['This is needed for the option you chose.'];
                }
            }

            if ($errors) {
                throw ValidationException::withMessages($errors);
            }
        }
    }

    /**
     * Whether a value counts as supplied. Empty does not; neither does the framework's
     * placeholder sender (hello@example.com), which is what an unset From address
     * reads as and would get every email rejected.
     */
    private function isReal(mixed $value): bool
    {
        if (! filled($value)) {
            return false;
        }

        return ! (is_string($value) && str_contains($value, '@') && \App\Services\NotificationService::isPlaceholderAddress($value));
    }

    /**
     * Fields that must differ, such as the public and private buckets.
     *
     * @param  array<string, mixed>  $submitted
     */
    private function validateDistinct(Group $g, array $submitted): void
    {
        foreach ($g->distinct as $names) {
            $values = array_map(fn ($n) => (string) $this->valueAfter($g, $n, $submitted), $names);

            if (count(array_unique(array_filter($values))) < count(array_filter($values))) {
                throw ValidationException::withMessages([
                    "values.{$names[1]}" => ['This must be a different bucket from the public one. Seller documents must never share a bucket that allows public reads.'],
                ]);
            }
        }
    }

    /**
     * Require the admin's current password, throttled and audited.
     *
     * No password on the account (created through Google or an OTP) means there is
     * nothing to confirm with, so the change is refused with instructions rather
     * than waved through.
     */
    private function confirmPassword(Request $request, string $group): void
    {
        $user = $request->user();

        if ($user->password === null) {
            $this->record($request, 'DENIED', $group, null, 'no_password');

            throw new HttpResponseException(response()->json([
                'status' => 'error',
                'code' => 'password_not_set',
                'message' => 'This account has no password, so a change cannot be confirmed. Ask whoever runs the server to set one: php artisan bazaarx:set-password '.$user->email,
            ], 422));
        }

        $key = 'integrations-reauth:'.$user->id;

        if (RateLimiter::tooManyAttempts($key, self::REAUTH_ATTEMPTS)) {
            $this->record($request, 'DENIED', $group, null, 'throttled');

            throw new HttpResponseException(response()->json([
                'status' => 'error',
                'message' => 'Too many incorrect passwords. Try again in '.ceil(RateLimiter::availableIn($key) / 60).' minutes.',
            ], 429));
        }

        if (! Hash::check((string) $request->input('current_password'), $user->password)) {
            RateLimiter::hit($key, self::REAUTH_WINDOW);
            $this->record($request, 'DENIED', $group, null, 'invalid_password');

            throw ValidationException::withMessages(['current_password' => ['That password is not correct.']]);
        }

        RateLimiter::clear($key);
    }

    private function record(Request $request, string $action, string $group, ?string $field, string $outcome, mixed $before = null, mixed $after = null): void
    {
        IntegrationAuditLog::create([
            'user_id' => $request->user()?->id,
            'action' => $action,
            'group' => $group,
            'field' => $field,
            'outcome' => $outcome,
            'fingerprint_old' => $before === null ? null : $this->settings->fingerprint($before),
            'fingerprint_new' => $after === null ? null : $this->settings->fingerprint($after),
            'ip' => $request->ip(),
        ]);
    }

    /** @param  array<string, mixed>  $payload */
    private function noStore(array $payload): JsonResponse
    {
        return response()->json($payload)->header('Cache-Control', 'no-store, private');
    }
}
