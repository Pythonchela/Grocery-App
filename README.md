# Single-store app

A complete online store for **one business**: a customer website and app, and an
admin panel for the owner. There are no vendors: nobody applies to sell, there are
no shops to choose between, no commissions or payouts.

This is a separate copy of the Haatvia marketplace with everything vendor-related
taken out. It does not share code, a database or a server with the marketplace.

```
.
├── app/, components/, lib/   Website: storefront for shoppers, /admin for the owner (Next.js)
├── laravel-backend/          The API (Laravel)
├── marketplace_app/          The customer mobile app (Flutter, Android)
└── packages/                 Design system: colours, brand names, shared components
```

## Which kind of store this is

The same code runs three kinds of store, and each copy of the project is set to one of
them in a single file, `lib/storeKind.js` (`STORE_KIND`). It decides which fields the
add-product page asks for, what blocks a product from going live, how a new category is
delivered, and which sample items the starter seeder adds.

| Kind | For | Delivered by | The add-product page asks for |
|---|---|---|---|
| `instant` | Food and grocery | A local rider, within hours | Veg / non-veg mark, pack size, minutes to get ready. No weight or parcel size. |
| `parcel` | Shopping: clothes, shoes, electronics, beauty | A courier, in days | Sizes and colours, weight (suggested), parcel size. |
| `heavy` | Furniture and appliances | A truck, booked for a slot | Packed weight and size (required), finish or size, vehicle needed. |

Only `lib/storeKind.js` and the sample items in `laravel-backend/database/seeders/StarterCatalogSeeder.php`
differ between the three. Everything else is the same code.

## What is in it

**Shoppers** (website and app): browse and search, product pages with options,
cart and checkout (cash on delivery and online payment), delivery tracking, returns
and refunds, wishlist, reviews and questions, coupons and bundle deals, wallet,
loyalty points and referrals, support tickets, notifications.

**The owner** (website, `/admin`): products and stock, categories, bulk import,
orders and a live board of open orders, returns, reviews and questions, coupons,
bundles, customer support inbox, broadcast messages, analytics, storefront builder,
colours and logo, staff accounts, integrations (payments, couriers, email/SMS,
storage), an audit log, and **My shop** (opening hours, minimum order, delivery
area and the pickup address couriers collect from).

**Removed on purpose:** vendor applications and verification, the seller dashboard
and seller app, shops and shop pages, "Sold by", payouts, commissions and tax
deductions, category requests, the one-shop basket rule. Their database tables are
dropped by the migration `drop_vendor_tables`.

**Kept inside, not shown anywhere:** the store's own record in the `sellers` table
(one row, created by the first migration). Stock, orders and courier pickup are tied
to it, and removing it would mean reworking checkout and delivery. Products and order
lines still carry its id. Nothing in the website or app presents it as a seller.

## Running it on your computer

You need PHP 8.3 with Composer, Node 22, and (for the app) Flutter.

```bash
# 1. The API
cd laravel-backend
cp .env.example .env          # then set APP_NAME to the store's name
php artisan key:generate
touch database/database.sqlite   # a file database is fine for trying it out
php artisan migrate
php artisan db:seed --class=StarterCatalogSeeder   # optional: ten sample products (zero stock)
php artisan haatvia:admin     # creates the owner's login
php artisan serve --port=8001

# 2. The website (from the project root)
npm install
echo "NEXT_PUBLIC_API_URL=http://127.0.0.1:8001/api/v1" > .env
npm run dev                   # http://localhost:3000, admin at /admin

# 3. The app
cd marketplace_app
flutter run --dart-define=API_BASE=http://10.0.2.2:8001/api/v1   # Android emulator
```

For a real server use PostgreSQL or MySQL, set `APP_ENV=production`, and run
`php artisan schedule:run` every minute (it refunds unclaimed payments, restores
items marked unavailable until a time, and closes resolved tickets).

## Setting it up for a new client

1. **Name.** `laravel-backend/.env`: `APP_NAME="Their Store"`. The store's public
   profile (logo, tagline, hours, minimum order, delivery area, pickup address) is
   edited by the owner at **Admin → My shop**.
2. **Brand.** `packages/brand/index.js`: the names, initials, support email and legal
   name. Then `npm run tokens:build` (also regenerates the app's copy).
3. **Colours and logo.** The owner sets them at **Admin → Colours** and **Design**,
   no rebuild needed. Corner radius too.
4. **Integrations.** **Admin → Integrations & API keys**: payment gateway, courier,
   email, SMS, storage. Nothing is live until keys are entered.
5. **App identity (Android).** `marketplace_app/android/app/build.gradle.kts`
   (`applicationId`), `res/values/strings.xml` (`app_name`). Icons and Play Store
   images: edit the initials and colours at the top of
   `marketplace_app/tools/make_brand_assets.py`, then `python tools/make_brand_assets.py`.
   Listing text to start from: `marketplace_app/store/listing.md`.
6. **Release build.** `flutter build apk --release --dart-define=API_BASE=https://their-api/api/v1`
   (needs `android/key.properties`; see `marketplace_app/README.md`).

## Tests

```bash
cd laravel-backend && php artisan test
npm test
cd marketplace_app && flutter test
```
