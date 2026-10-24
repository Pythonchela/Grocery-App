# Payments

The platform owns the money flow. A payment gateway is only a hook that takes a
payment and gives one back — it knows nothing about orders, carts, coupons,
wallets or returns.

```
client SDK ──evidence──▶ POST /orders/checkout ──▶ PaymentService ──▶ gateway driver
                                                        │
                                       payments / refunds tables (the ledger)
```

## The pieces

| | |
|---|---|
| `app/Services/Contracts/PaymentGateway.php` | What a gateway must do: `key`, `createIntent`, `verify`, `refund`, `parseWebhook`. |
| `app/Services/Payments/PaymentGatewayManager.php` | The gateways this deployment can reach. Answers "which one for a new payment?" and "which one took that old payment?". |
| `app/Services/Payments/PaymentService.php` | All the rules: verify, record, refund routing, wallet split, webhook reconciliation. |
| `payments` table | One row per captured gateway payment, with its `provider`. |
| `refunds` table | Every refund — gateway (`SOURCE`) and wallet (`WALLET`) — with status. |
| `POST /api/v1/webhooks/payments/{provider}` | One public endpoint for every gateway. |
| `php artisan payments:refund-unclaimed` | Scheduled every 10 min. Refunds money that was captured but never became an order. |

## Adding a gateway

1. Write a class implementing `PaymentGateway`, with a static
   `fromConfig(): ?static` that returns `null` while its credentials are missing.
2. Add it to `gateways` in `config/payments.php`.
3. Add its credentials to `config/services.php` and `.env`.
4. Storefront and app: add a handler for its `provider` key in
   `lib/payments/index.js` (web) and `lib/data/payments.dart` (mobile). It runs
   the gateway's SDK and returns whatever the API's `verify` needs.

No controller, model, migration or route changes. `tests/Support/FakeGateway.php`
is a gateway shaped nothing like Razorpay; the suite in
`tests/Feature/PaymentPlatformTest.php` runs against it, which is what keeps the
platform honest about not depending on one gateway.

With several gateways configured, `PAYMENT_GATEWAY` picks the default and a
client may pass `gateway` to `POST /payments/intent` to choose another enabled
one. Old payments are always refunded through the gateway that took them.

## Refund rules (all in `PaymentService::refundOrder`)

- **Proportional.** An order paid ₹600 by card and ₹400 from the wallet refunds
  60/40. The card share is capped at what is still refundable on the payment.
- **Never more than was paid.** Across all refunds on an order — cancel, returns,
  anything — the total cannot exceed what the customer handed over.
- **COD has no gateway payment**, so it refunds to the wallet (which is also the
  only place cash-on-delivery money can go).
- **Wallet-only mode.** A customer may choose store credit; it skips the gateway.
- **Idempotent.** Each refund carries a reference (`return:<id>`, `cancel:<id>`).
  Asking twice returns the first answer.
- **The gateway call is last** inside the caller's transaction. It is the one
  step that cannot be rolled back, so nothing that might fail comes after it. If
  the gateway refuses, the whole action (stock, points, coupon, status) rolls
  back and the API answers 502.
- **A refund can be `PENDING`.** The gateway accepted it but has not paid out; its
  webhook settles it to `PROCESSED`, or to `FAILED` (which restores the payment's
  refundable amount and logs at `critical` — the customer is still owed money).

## Other money rules

- **Coupons and points** are spread across the order's lines at purchase
  (`order_items.discount_allocated`), so a return refunds what was actually paid
  for that item. Cancelling releases the coupon and returns redeemed points.
- **Returns reverse loyalty points** in proportion to the value returned.
- **₹0 orders** (wallet, points or a coupon covered everything) use provider
  `none`: no gateway is involved, and checkout accepts that intent only because it
  was quoted at exactly zero.
- **COD** is marked `PAID` when the order is marked `DELIVERED`.

## Webhooks

Each driver authenticates its own payloads and returns normalised events
(`payment.captured`, `payment.failed`, `refund.processed`, `refund.failed`); the
platform handles them identically for every gateway. Handlers are idempotent
(gateways deliver at least once) and ignore payments that are not ours (one
gateway account can serve several apps).

Money captured with no order to match is recorded, then refunded by
`payments:refund-unclaimed` after `PAYMENT_UNCLAIMED_REFUND_MINUTES` (default 30).
This needs the scheduler running: `php artisan schedule:run` every minute.

### Razorpay

1. Dashboard → Account & Settings → Webhooks → Add new webhook (use Test Mode
   while developing).
2. URL: `https://<your-api>/api/v1/webhooks/payments/razorpay` (needs public
   HTTPS; use a tunnel locally).
3. Secret: a long random string of your own. Put it in `.env` as
   `RAZORPAY_WEBHOOK_SECRET`. Without it, webhooks are refused.
4. Events: `payment.captured`, `payment.failed`, `refund.processed`,
   `refund.failed`.

## Environment

```
RAZORPAY_KEY_ID=            # rzp_test_… for Test Mode, rzp_live_… for real money
RAZORPAY_KEY_SECRET=
RAZORPAY_WEBHOOK_SECRET=
PAYMENT_GATEWAY=            # optional: default gateway when several are configured
PAYMENT_UNCLAIMED_REFUND_MINUTES=30
```

With no real gateway configured the sandbox gateway is used. It moves no money.

## Safeguards

- **No silent sandbox in production.** The sandbox gateway approves every payment
  without taking money. It is offered locally and in tests, but in production a
  missing set of gateway keys makes prepaid checkout answer "not available"
  (cash on delivery keeps working) rather than accepting unpaid orders. Override
  only for a deliberately fake demo with `PAYMENTS_ALLOW_SANDBOX=true`.
- **No invented store credit for old orders.** A prepaid order with no payment
  record (placed before the ledger, or under the sandbox) refunds no money to a
  gateway and no gateway share to the wallet: it is recorded as a `SKIPPED`
  refund, and only wallet money the customer really spent is returned.

See `UPGRADE_NOTES.md` for what to set and check when deploying.

## Known limits

- Refund idempotency is at the platform, not the gateway: a gateway call that
  succeeds followed by a database failure at commit could leave the gateway
  ahead of us. The reference is passed to the gateway as its receipt so the
  refund can be found and reconciled by hand.
- A `FAILED` refund is surfaced in logs and the `refunds` table but there is no
  admin screen for it yet.
- Orders placed before the `payments` table existed have no payment row, so their
  refunds go to the wallet rather than back to the gateway.
