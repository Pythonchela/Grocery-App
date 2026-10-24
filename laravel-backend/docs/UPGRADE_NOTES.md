# Upgrading to the payments platform + seller fulfilment release

Read this before running `deploy.sh` for the first time after merging this
branch. Nothing here is automatic: merging to `main` changes no server. It only
takes effect when `deploy.sh` (or your own process) runs on the server.

## What changes on the server

- **Two migrations** (additive; no existing column is changed or dropped):
  - `payments` and `refunds` tables, and two columns on `payment_intents`.
  - Five columns on `order_items` for per-line fulfilment. Existing lines are
    backfilled from their order's status (delivered/out-for-delivery/shipped →
    shipped; packed → packed; everything else → pending).
- **No new composer or npm packages.**
- **New public endpoint:** `POST /api/v1/webhooks/payments/{provider}`.
- **New scheduled job:** `payments:refund-unclaimed` (every 10 minutes).

Verified by restoring a copy of the pre-change database (5 real orders) into a
scratch PostgreSQL database and running the migrations on it: all 6 pending
migrations applied, every order and user was intact, and the backfill was correct.

## Before you deploy

1. **Set the environment variables** on the server (`laravel-backend/.env`, or
   the container environment for Docker):

   ```
   RAZORPAY_KEY_ID=          # rzp_test_… to try it, rzp_live_… for real money
   RAZORPAY_KEY_SECRET=
   RAZORPAY_WEBHOOK_SECRET=  # see step 3
   ```

   **If you skip this in production, online payment is refused** (checkout says
   "Online payment is not available right now"; cash on delivery keeps working).
   That is deliberate: before this release a server without keys silently used a
   sandbox gateway that approves every payment without taking any money.
   To keep a deliberately fake demo, set `PAYMENTS_ALLOW_SANDBOX=true`.

2. **Make sure `APP_URL`, `FRONTEND_URLS`, `SANCTUM_STATEFUL_DOMAINS` and
   `SESSION_DOMAIN` are your real domains** (not `localhost`). Product photo URLs
   are built from the address the upload arrived on.

3. **Register the webhook in Razorpay** (Account & Settings → Webhooks):
   - URL: `https://<your-api-domain>/api/v1/webhooks/payments/razorpay`
   - Secret: a long random string you make up; put the same value in
     `RAZORPAY_WEBHOOK_SECRET`.
   - Events: `payment.captured`, `payment.failed`, `refund.processed`, `refund.failed`.

4. **Start the scheduler.** Without it, a payment captured for an order that
   never completed (customer paid, then the app died) is *not* refunded
   automatically. Add one line to the server's crontab (`crontab -e` as the user
   that owns the app):

   ```
   * * * * * cd /var/www/marketplace-app/laravel-backend && php artisan schedule:run >> /dev/null 2>&1
   ```

   With Docker, run `php artisan schedule:work` in a long-lived container that
   shares the backend's image and environment.

## Deploying

`deploy.sh` already does the right things in a sensible order (pull, composer
install, `migrate --force`, cache, build, restart). Two notes:

- **There is a short window between `git pull` and `migrate`** in which the new
  code is live but the new tables/columns do not exist yet (composer install sits
  in between). A cancel or checkout in that window would error. Deploy at a quiet
  time, or put the site in maintenance mode first
  (`php artisan down` … `php artisan up` after the migration succeeds).
- If `migrate` fails, **do not `php artisan up`** until it is fixed: the code
  expects the new schema.

## After you deploy — check these

- `php artisan schedule:list` shows `payments:refund-unclaimed`.
- A Test Mode payment end to end (UPI `success@razorpay`), then cancel it and
  confirm the refund appears in the Razorpay dashboard.
- Razorpay → Webhooks shows recent deliveries with status 200.
- Look at `refunds` for any row with `status = 'SKIPPED'` (see below).

## Orders placed before this release

Prepaid orders from before the ledger have **no payment record**, so the platform
cannot know that money reached a gateway (many were paid under the sandbox
gateway, which took none). Cancelling or returning one therefore does what it
always did: **no money is sent to a gateway and no store credit is invented.**
The gateway share is recorded as a `SKIPPED` refund, and any wallet money the
customer really spent is returned to their wallet. Review `SKIPPED` rows: if you
know a customer genuinely paid, refund them by hand.

Cash-on-delivery orders are unaffected: their refunds go to the wallet.

## Behaviour changes to be aware of

- A customer can no longer cancel an order once **any** seller has shipped their
  part of it.
- A delivered cash-on-delivery order is now marked **PAID** (it never was before).
- A return refund is split between the original payment method and the wallet in
  proportion to how the order was paid, and never exceeds what was captured.
- Returning an item now also takes back the loyalty points it earned, in
  proportion.
- The payment-intent response carries a `client` object instead of gateway-specific
  fields; the storefront and mobile app were updated together with the API.

## Rolling back

- **Code:** revert the merge commit and redeploy.
- **Database:** the migrations have `down()` methods, but rolling them back
  **drops the `payments` and `refunds` tables and the fulfilment columns and
  everything recorded in them**. Only do it if no real payments were taken with
  the new code. Reverting the code alone is safe: the extra tables and columns
  are ignored by the old code.
