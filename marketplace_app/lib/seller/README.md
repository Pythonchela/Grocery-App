# Seller area

Everything a vendor does in the app: apply, complete KYC onboarding, wait for
review, then run the shop (overview, orders, products, earnings).

It is the whole of the **seller app** (`lib/main_vendor.dart`, flavor `vendor`). The
shopping app contains none of it: its Account tab only links to the seller app. It is
also built to be **movable**: it can be lifted into a repository of its own.

## The boundary

`lib/seller/` may import only:

- itself,
- `lib/support/` — help tickets, shared with the shopper app. It follows the same rule
  (only the design system and the API client), so it moves with this folder,
- `lib/design/` — the design system (`components.dart`, `theme.dart`, tokens),
- `lib/data/api_client.dart` — the HTTP client (session-agnostic: the token is
  passed per call),
- packages.

It must **not** import the shopper app (`screens/`, `state/`, `widgets/`,
`data/models.dart`). And the only code outside this folder that may import the
seller area is the seller app's own (`lib/vendor/`), through `seller/seller.dart`.

`test/seller/boundary_test.dart` enforces both rules, and also walks the imports from
each app's entry point: the shopping app must not reach `lib/seller/` or `lib/vendor/`,
and the seller app must not reach the shopper's screens, widgets or state.

## The seam: `SellerHost`

The one thing the seller area needs from its host is a `SellerHost`: how to read
the API token, how to sign out, and the marketplace's name. The seller app builds it
from its own `VendorSession` (`lib/vendor/vendor_app.dart`).

## Moving it to its own repository

It is already its own app, built from this repository. To give it a repository too:

1. Create a new Flutter app; copy `lib/design/`, `lib/data/` (the API client,
   notifications and order-alert files the seller app uses), `lib/support/`,
   `lib/seller/`, `lib/vendor/` and `lib/main_vendor.dart` into it.
2. Add the dependencies from this app's `pubspec.yaml`.
3. Copy the `vendor` flavor from `android/app/build.gradle.kts` and
   `android/app/src/vendor/`.

## Structure

| | |
|---|---|
| `seller_area.dart` | The gate: asks the API where this account stands and shows the matching screen |
| `seller_api.dart` | Every API call, behind an interface (fakeable in tests) |
| `seller_models.dart` | Data shapes, parsed defensively |
| `validators.dart` | Client-side mirrors of the API's rules (the API still decides) |
| `document_picker.dart` | The file-picker plugin behind an interface |
| `screens/` | Apply, the 5-step application, status, and the dashboard tabs |
| `widgets/` | Paged-list loader and small shared widgets |

## What it can do

- **Onboarding:** apply, a 5-step KYC application (with masked PAN / bank
  numbers), document upload, submit, and the review / rejected / suspended states.
- **Orders:** the seller's workflow by stage (to pack, packed, shipped, delivered,
  cancelled). Mark a line packed; mark it shipped with a courier and tracking
  number; correct the tracking until the order is out for delivery. An order that
  holds several sellers' goods ships as several parcels, and the order's status
  is rolled up from its lines on the server.
- **Products:** add and edit products with photos, variants (colour, size, SKU,
  stock, optional prices), status (draft / live / out of stock / discontinued);
  delete a product nobody has bought, or discontinue one that has been ordered.
- **Overview and earnings:** balance, what needs packing, recent orders, and the
  payout ledger.

## What is not here yet

- **Payout requests.** The ledger shows the balance, but payouts are made by the
  marketplace, not requested from the app.
- **Per-parcel tracking for the customer on split orders.** The API returns each
  line's courier and tracking number; the shopper apps show the order-level one,
  which a single-seller order gets automatically.
- **Product moderation.** A seller can publish straight to the store; there is no
  review queue.
- **Reordering photos** (the first is the cover; remove and re-add to change it).
