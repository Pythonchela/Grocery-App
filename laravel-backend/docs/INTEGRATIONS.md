# Integrations & API keys (admin panel)

Full admins can set the API keys and settings below from **Admin → Integrations & API
keys**, with no `.env` edit and no redeploy. Changes apply within about a minute.

## What is managed there

| Card | Settings |
| --- | --- |
| Gemini AI | API key (AI search, review summaries, smart import). Has a **Test connection** button. |
| Google sign-in | Web / storefront / Android / iOS client IDs (public identifiers, not secrets). |
| Email | Mailer (Log or SMTP), from address and name, SMTP host, port, username, password. **Send test email** goes to your own address. |
| SMS & login OTP | Provider (Log, MSG91 or Twilio), its credentials and templates, whether to also text order updates. **Send test message** goes to a number you type. |
| Image & file storage | Server disk or an S3-compatible bucket: a public bucket for product images, a private one for seller documents, region, endpoint, keys. **Test storage** proves both work. |
| Delivery partners | Couriers offered; Shiprocket, Delhivery, Ola, Rapido, Porter credentials. **Test Shiprocket** checks the login; the others cannot be checked live (they publish no open API), so they say so rather than guess. |
| Shipping & pickup | Pickup address, PIN, coordinates, free-shipping threshold, default item weight. |
| Marketplace | Default seller commission, seller review turnaround. |

**Payments are deliberately not here.** Razorpay keys, the webhook secret, the gateway
choice and the sandbox flag stay in the server's `.env` (see `PAYMENTS.md`). A hijacked admin
session must not be able to redirect customer money. The page shows a read-only Payments card
(configured? test or live? the webhook URL to copy) and never a value.

Also stay in `.env`: `APP_KEY`, the database, Redis, domains, each courier's `*_BASE_URL`
(letting a session change where credentials are sent would be an exfiltration path), the Sentry
DSN (read before any setting can apply), and `INTEGRATIONS_ALLOW_PRIVATE_HOSTS`.

## Precedence

1. A value set in the admin panel wins.
2. Otherwise the server's `.env` / config value is used (the card shows **From the server**).
3. **Remove** on a secret, or blanking a plain setting, deletes the override and the `.env`
   value applies again.

Leaving a secret field blank on save means "keep what is there".

## How it is protected

- **Who:** full ADMIN / SUPER_ADMIN only (the same gate as user management). Sub-admins,
  sellers and customers get 403 on every route.
- **Re-authentication:** saving or removing anything requires the admin's current password.
  Wrong attempts are throttled (5 per 15 minutes per admin) and audited. There is no
  "sudo window", so a stolen session cannot ride one.
- **Admins with no password** (created through Google or OTP) cannot save. Whoever runs the
  server gives them one: `php artisan haatvia:set-password their@email` (this also signs out
  their other sessions).
- **Never shown again:** no endpoint returns a secret. The page shows only "set" and, for a
  long enough secret, its last four characters. Responses are `Cache-Control: no-store`.
- **Encrypted at rest** with `APP_KEY` (`Crypt`), and each value is bound to its own row, so a
  ciphertext copied to another row is refused. Only the *encrypted* rows are cached (60 s).
- **Not in `config:cache`:** the admin values are applied by HTTP middleware, not at
  provider boot, so `php artisan config:cache` never writes a decrypted secret into
  `bootstrap/cache/config.php`. (Checked: the cached file contains none.)
- **Audit trail:** who, when, which setting, outcome, IP. It stores a short keyed fingerprint
  (HMAC with `APP_KEY`) to show *that* a value changed, never the value.
- **Logs:** a formatter on the log channels redacts known secrets and `?key=` /
  `Authorization` credentials. The Gemini key is now sent in an `x-goog-api-key` header, not
  the URL, so an HTTP error can no longer quote it.
- **Testing a connection** calls fixed provider hosts only (no user-supplied URL), can test
  values you have typed but not saved, and never echoes the provider's reply.
- **Fails safe:** if the settings table is missing or the database is briefly down, requests
  carry on with the `.env` values, exactly as before.

## Email

Order and account emails go through Laravel's mailer, so any SMTP provider works (Amazon SES,
Brevo, Mailgun, Resend, Gmail...). Choose **SMTP**, fill in the host, port, username and password
from your provider, and a **From address the provider has verified** (otherwise mail is rejected
or lands in spam). Press **Send test email**: it goes to your own admin address, never to anyone
named in a request.

- Emails are sent *after* the response has gone out, so a slow or broken mail server can never
  hold up or fail an order. Failures are logged and sent to error tracking, without the address.
- There is deliberately **no queue worker** dependency: nothing in the deployment runs one, and a
  queued email with no worker is an email that never arrives.
- Accounts created by phone OTP get a placeholder `<phone>@example.com` address. Placeholder and
  reserved domains are never mailed.
- The mail host must be a **public** address (see "Hosts you type in" below).

## SMS and phone sign-in

The login code is sent by the SMS provider you choose. The code is stored hashed, expires in five
minutes, works once, and is rate limited.

| Provider | Notes |
| --- | --- |
| **MSG91** | Suits Indian numbers. Indian carriers only deliver pre-approved (DLT) wording, so you give it the **Flow template ID** approved on your DLT entity. The OTP template needs one variable named `otp`; the optional order template one named `message`. |
| **Twilio** | Free text, works worldwide. Account SID, auth token, and a sender number (or Messaging Service SID). |
| **Log** | Sends nothing. Fine for development. **In production the OTP endpoint then answers "unavailable" (503) instead of pretending to send**, so the gap is noticed rather than silent. |

Order-update texts are **off by default** (each costs money, and on MSG91 each needs its own
template). Turn them on under "Also text order updates". The login code is always sent.

If the provider rejects a message, the customer sees "we could not send the code", nothing is
stored, and the failure goes to the log and error tracking without the phone number.

The MSG91 and Twilio integrations follow those providers' published APIs but have only been
exercised against test doubles. **Send one real test message** before relying on them.

## Image & file storage

By default uploads live on the server's own disk. That works, but the files are **lost if you move
or rebuild the server**. Switching to a bucket fixes that.

1. Create **two buckets**: a *public* one for product images (allow public reads through a bucket
   policy, an `r2.dev` address or a CDN) and a *private* one for seller KYC documents that must
   **not** allow public reads. The panel refuses to save if both are the same bucket.
2. Create an access key with read, write and delete on both. For Cloudflare R2 the region is `auto`
   and the endpoint is `https://<account-id>.r2.cloudflarestorage.com`; leave the endpoint empty for
   Amazon S3.
3. Fill in **Image & file storage**, choose *S3*, press **Test storage**. It writes, reads back and
   deletes a small file in both buckets, and fetches one over the Public URL: a bucket that accepts
   uploads but is not publicly readable is the classic "images upload fine and never show".
4. Save. **New** uploads now go to the buckets.
5. Move what is already there (run on the server):

```bash
php artisan media:migrate            # dry run: what would be copied and rewritten
php artisan media:migrate --apply    # copy product images, then rewrite their URLs
php artisan kyc:migrate              # dry run
php artisan kyc:migrate --apply      # move seller documents (keeps the originals)
```

`media:migrate` copies each file, checks it arrived, and only then rewrites the addresses stored in
the database (products, categories, banners... it finds them itself). If any copy fails, **nothing
is rewritten**. Both commands are safe to run twice and never delete from the server disk unless you
pass `--delete-source` to `kyc:migrate`.

No ACL is ever requested on S3: buckets created since 2023 reject the public-read ACL. Public
access comes from the bucket's policy or your CDN.

## Hosts you type in

The mail host and the storage endpoint are addresses the server connects to, carrying credentials.
To stop a hijacked admin session pointing the server at its own network, both must resolve to a
**public** address (no loopback, private, link-local or cloud-metadata addresses), and are checked
again at test time and pinned to the address that was checked. A self-hosted setup that really does
live on a private network can allow it with `INTEGRATIONS_ALLOW_PRIVATE_HOSTS=true` in the server's
`.env` only. No admin session can change that.

## Error tracking (Sentry)

Set `SENTRY_LARAVEL_DSN` in `.env` (from sentry.io: create a *Laravel* project; the free plan is
enough to start) and run `php artisan sentry:test` once. Unhandled errors, and failures the app
reports itself (a failed upload, an SMS the provider rejected), then arrive with the file, line and
deployed commit. It is read while the app boots, before any admin setting could apply, so the admin
page shows only a read-only status.

What leaves the server is limited on purpose, and scrubbed again just before sending:

- no request bodies, cookies or IP addresses; no `Authorization`, cookie or CSRF headers;
- no function arguments in stack traces;
- known keys and passwords, and `?key=` / `Authorization` values, replaced with `[redacted]` in
  messages, traces and URLs;
- no SQL bound values; performance tracing is off unless you set `SENTRY_TRACES_SAMPLE_RATE`.

Validation failures, 404s and authentication errors are not reported. The release is the deployed
git commit, read at `config:cache` time, so each report says which deploy it came from.

This covers the **backend**. Errors that happen only in a shopper's browser or the mobile app are
not reported yet.

## Console commands and the scheduler

Commands the scheduler runs (back-in-stock emails and so on) apply the admin-managed settings too,
so an email goes out through the same mailer the panel says. The commands that **write config to
disk** (`config:cache`, `optimize`) and the ones that run before the settings table exists
(`migrate`...) never see them, so a cached config cannot hold a decrypted secret. A long-running
worker (`queue:work`) reads settings once at start: restart it after changing them.

## `APP_KEY` is now the master key

Everything above is only as safe as `APP_KEY`. **Back it up** somewhere other than the
server. If it changes without `APP_PREVIOUS_KEYS`, the saved values cannot be decrypted:
they are treated as unset (the `.env` value applies) and the page shows "could not be read,
enter it again". To rotate properly, put the old key in `APP_PREVIOUS_KEYS` first.

## Deploying

`php artisan migrate --force` creates `integration_settings` and `integration_audit_logs`
(`deploy.sh` already runs it). Nothing else is needed; with no rows, behaviour is unchanged.

## Developers

Add a setting by adding a `Field` to `app/Integrations/Registry.php` (config path(s), rules,
env name). Services that copy config when they are built must be dropped after a change: add
them to the list in `IntegrationSettings::changed()`.
