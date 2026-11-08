# Moving the single-store app to its own backend and database

Goal: the single-store app (`in.haatvia.shop`) runs on its own backend and database, keeps every
connection it has today (Google sign-in, Razorpay, Shiprocket, push, SMS, email, storage), and nothing
that works today breaks on the way. The multi-vendor marketplace is not touched at any point.

## Why this is safe to do

The app talks to the backend through only two build settings and two things the server tells it:

| Connection | Where it lives | Does the app change? |
|---|---|---|
| Server address | `API_BASE` and `WEB_BASE`, set when the app is built | Yes: a rebuild with the new addresses |
| Google sign-in | The Google Cloud project; the Web client ID comes from the server (`GET /config`) | No |
| Razorpay | The key ID is sent by the server at checkout | No |
| Push | `google-services.json` inside the app; the service account is in the server's Settings | No |
| Shiprocket, SMS, email, storage | Entered in the server's Settings | No |
| Play listing, package name, signing key | Play Console and `C:\Users\Abrar\.android\single-store\` | No |

The single-store backend already passes its tests, and the app was run against it end to end (an order
from the phone, handled in the admin, delivered, tracked). It serves the same customer API the app uses
today.

## What does NOT carry over by itself

1. **Data.** A new database is empty: users, orders, addresses, wallet, products. Choose one:
   - Fresh start (recommended before the public launch; there are only sample products and test accounts).
   - Move the data: restore a dump into the new database, then run the migrations (they drop the vendor
     tables), then remove the extra seller rows. Rehearse on a copy first.
2. **Sign-ins.** Tokens from the old server are refused by the new one. The app handles that by signing
   the person out. Google and phone sign-ins re-create the account on the next login. Email-and-password
   users need their data moved, or a password reset (which needs email working).
3. **Keys saved in Settings.** They are encrypted with the old server's `APP_KEY`. Never reuse that key.
   Enter them again on the new server (each Settings tab has a guide).
4. **Push tokens.** They live in the database. Phones register again when someone signs in.
5. **Uploaded images.** Files on the old server's disk keep their old addresses. Keep the old host alive,
   or put images in a bucket and run `php artisan media:migrate --apply`.
6. **Webhooks.** Razorpay and the couriers send events to the address you registered. Add the new
   address before the switch; keep the old one until the old server is retired.
7. **Installed apps.** The address is baked into each build. A build with the old address keeps using the
   old server until the person updates, so the old server must stay up for as long as such builds exist.

## Phases

**0. Decide** (nothing is built yet)
- Domains, for example `api.yourstore.in` and `yourstore.in`, with HTTPS.
- Hosting, and a database (Postgres gives the best search; MySQL also works).
- Fresh start or move the data.
- Whether the Play app is already public (this decides how long the old server must stay).

**1. Build the new environment** (live system untouched)
- New server, new database, new `APP_KEY`, new `.env` (`APP_URL`, `FRONTEND_URLS` including the new
  website, database, `PAYMENT` and mail settings).
- Deploy `laravel-backend` and the website from `E:\Marketplace Single Vendor`.
- Run the migrations, create the owner with `php artisan haatvia:admin`, start the scheduler
  (`schedule:run` every minute) and the queue worker.
- Copy the privacy and delete-account pages into the single-store website, so the Play policy URL
  is on the new domain.

**2. Reconnect each service** (use the Settings tabs; the same accounts, the same credentials)
- Google: add the new website address under Authorized JavaScript origins; paste the same Web client ID.
  Nothing changes for the Android clients.
- Razorpay: same Key ID and Secret in the server `.env`; add a second webhook for the new address
  with its own secret.
- Shiprocket and other couriers: the same API user in Settings; register the new webhook address.
- Push: a new service account key for the same Firebase project, pasted in Settings.
- SMS, email, Gemini, storage: re-enter in Settings and use each tab's test button.

**3. Prove it on the new server before anyone depends on it**
- Run the backend and web test suites on exactly the code you deploy.
- Install a debug build on the phone with `--dart-define=API_BASE=https://api.yourstore.in/api/v1`
  and `--dart-define=WEB_BASE=https://yourstore.in`.
- Walk through: home, product, sign up and login (email and Google), add to cart, checkout with Razorpay
  **test** keys, the webhook marking the order paid, the admin seeing and handling it, a courier test,
  a push test, an image upload.
- Every green test button in Settings; privacy and delete-account pages reachable.

**4. Data** (only if moving it): rehearse on a copy, compare counts, confirm the shop and catalogue look right.

**5. Cut over**
- Switch to live Razorpay keys and register the live webhooks.
- Build the release bundle with the new addresses and a higher version number; upload it to Play internal
  testing first and test the build that comes from Play (its signing key differs: add its SHA-1 as another
  Android client in Google Cloud).
- Update the Play listing's privacy policy URL to the new domain.
- Then roll out.

**6. Rollback and clean-up**
- Nothing on the old server is deleted for at least two weeks.
- Rollback is a build with the old addresses, or pausing the Play rollout.
- Afterwards: backups, error tracking (Sentry DSN), and retire the old webhook addresses.

## The multi-vendor marketplace is read-only throughout

Nothing in this process edits the marketplace: its code (`E:\Marketplace App`), its phone app, its server,
its database, its domain, its `.env`, its Settings values or its signing key. All of the work happens in
`E:\Marketplace Single Vendor` and on the new server.

The only place the two can touch is an account they both use. There the rule is **add a new entry, never
change or remove an existing one**:

| Shared account | Do this | Never do this |
|---|---|---|
| Google Cloud project | Add the new website address as an extra Authorized JavaScript origin; add Android clients for `in.haatvia.shop` | Edit or delete an existing client, origin or the consent screen |
| Firebase | Register `in.haatvia.shop` as its own Android app; make a new service-account key | Delete or rotate the marketplace's key or app |
| Razorpay | Add a second webhook for the new address with its own secret | Edit or delete the marketplace's webhook; change the existing keys |
| Shiprocket | Create a separate API user for the single store (up to four are allowed) | Reuse the marketplace's API user, or replace its webhook address |
| SMS, email, Gemini, storage | Use a separate key, sender or bucket where the provider allows it | Share one bucket or rotate a key the marketplace uses |

Better still, give the single store its own Razorpay and Shiprocket accounts if it will be a separate business:
then nothing is shared and there is nothing to break.

## Rules that keep it from breaking anything

- Only add; never edit the live marketplace, its database or its keys.
- One server per build: a debug build for testing, a release build for the public. They never mix.
- Test keys everywhere until phase 5.
- A new `APP_KEY` and a new database. Nothing shared with the marketplace.
- Each phase is finished and checked before the next starts.

## What is needed from you

- Hosting, domain and database choice.
- Fresh start or move the data, and whether the Play app is already public.
- An empty GitHub repository for the single-store project (it has no remote yet).
- You run the commands on the server (as before); the exact commands for each phase are prepared in
  advance, one step at a time.

## Local rehearsal (done 2026-10-28, nothing pushed, nothing deployed)

A fresh copy of the single-store backend was run on a new local MySQL database (`single_store_local`),
completely separate from the marketplace.

- All 52 migrations ran cleanly; one house store row, no vendor tables.
- The whole backend test suite passes on MySQL as well as sqlite (601 tests, 11 skipped on both).
  Running on a second engine found and fixed three things sqlite hid: `media:migrate` used a SQL cast
  MySQL rejects (it is the command the plan relies on to move images to a bucket), the integration audit
  list could show two changes made in the same second in the wrong order, and one test assumed sqlite's JSON text.
- The website, against that backend, loads the storefront, the privacy page and the delete-account page.
- The Android debug app, against that backend with **no Google ID in the build**, loads home, categories and
  images, and shows "Continue with Google": the ID was saved in the new backend's Settings and the app
  picked it up from the server. This is the behaviour the switch depends on.
- A fresh store's starter products are "Sold out" until the owner enters stock.

Not rehearsed (needs real accounts or a real server): live Razorpay and courier webhooks, push delivery,
a sign-in with a real Google account, the Play-signed build, and a data move from the marketplace.

To run it again: start Laragon's MySQL, then from `laravel-backend` run
`php artisan serve --port=8002` with `DB_CONNECTION=mysql DB_DATABASE=single_store_local DB_USERNAME=root`
set; start the website with `NEXT_PUBLIC_API_URL=http://127.0.0.1:8002/api/v1 npm run dev`; run the app with
`adb reverse tcp:8002 tcp:8002` and `--dart-define=API_BASE=http://127.0.0.1:8002/api/v1`.

