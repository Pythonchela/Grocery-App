# Haatvia — Flutter app

The mobile client for the same Laravel API the web storefront uses, built on the
shared design system in [`../packages`](../packages/README.md).

```
This is the customer app for a single-business store. There are no seller screens.

```
lib/
├── main.dart             the app
├── support/              help tickets
├── design/
│   ├── tokens.g.dart     GENERATED — colours, radii, type, spacing, motion
│   ├── brand.g.dart      GENERATED — names, legal text, storage namespace
│   ├── theme.dart        DsThemeScope + Material ThemeData built from tokens
│   └── components.dart   BxButton, BxField, BxCard, BxBadge, BxAlert, BxTabs…
├── data/                 API client + model normalisers (mirror lib/apiClient.js)
├── state/                cart, session and theme
├── widgets/              commerce composites (ProductCardTile)
└── screens/              home, category, search, product, cart, account,
                          design-system gallery
```

## Running it

For local development, start the Laravel API and explicitly override the URL.
On an Android emulator:

```bash
flutter run --dart-define=API_BASE=http://10.0.2.2:8000/api/v1
```

For a physical device on the same network, point it at your machine:

```bash
flutter run --dart-define=API_BASE=http://192.168.1.2:8000/api/v1
```

To run it in a browser instead:

```bash
flutter run -d chrome
```

## Release APK

Release builds use a private signing key rather than the Android debug key.
Create `android/key.properties` locally with `storeFile`, `storePassword`,
`keyAlias`, and `keyPassword`. This file and keystores are ignored by Git.
Keep the same signing key for all future APK updates.

```bash
flutter build apk --release --dart-define=API_BASE=https://api.example.com/api/v1
```

The APK is written to `build/app/outputs/flutter-apk/app-release.apk`. Change `applicationId` in `android/app/build.gradle.kts` and `app_name` in `android/app/src/main/res/values/strings.xml` for each client.

Browser targets are subject to CORS. `laravel-backend/config/cors.php` reads a
comma-separated `FRONTEND_URLS` which already includes `localhost:8080`; native
iOS and Android builds aren't affected by it.

## The design system

Nothing in `lib/design/*.g.dart` is hand-written. Both generated files come from
`packages/tokens/src/tokens.js` and `packages/brand/index.js` via:

```bash
npm run tokens:build
```

That one command updates the web app's CSS variables *and* this app's Dart
constants, which is the point — a palette change lands on both clients from a
single edit instead of being re-keyed into each.

Widgets never name a colour. They read `context.ds.surface`, which resolves
through `DsThemeScope` — the Flutter equivalent of the CSS custom properties
that flip under `.dark` on the web. That is why there is no light/dark branching
anywhere in the screen code.

`DsBrand.storageKey()` namespaces `SharedPreferences` keys the same way the web
client namespaces `localStorage`, so two brands served to the same device can't
read each other's session.

The gallery is **not reachable from any customer screen** — it has its own
entry point instead:

```bash
flutter run -t lib/main_design_system.dart
```

A `kDebugMode` guard was not enough: `flutter run` *is* a debug build, so the
link stayed visible through all of normal development. A separate target means
it can never ship by accident while staying one command away. It is deliberately
the same page as the web's `/design-system`, section for section — putting them
side by side is how a divergence gets caught.

## Tests

```bash
flutter test
```

Fifteen tests covering the parts that quietly rot: that components read the
generated tokens rather than Material defaults, that switching theme
re-resolves them, that a `BxButton` is one merged semantics node carrying a name
and a button role, and that a `BxField` cannot render unlabelled.

## Sign-in

Three ways in, all landing on the same account:

- **Email + password** — `POST /auth/register` / `POST /auth/login`
- **Phone OTP** — `POST /auth/otp/send` / `/verify`
- **Google** — `POST /auth/google`

### Google Sign-In setup

Not wired out of the box, because it needs OAuth client ids that only you can
create. The button hides itself until the build supplies one, so nothing looks
broken in the meantime.

1. In the Google Cloud console, create an OAuth consent screen and then
   **three** client ids:
   - **Web** — this is the one the server verifies against, and the one Android
     must request an ID token *for*.
   - **Android** — keyed to your package name (`in.haatvia.shop`)
     and the SHA-1 of the signing certificate. Debug and release certificates
     have different SHA-1s, so register both or Google sign-in works in debug
     and fails in production.
   - **iOS** — keyed to the bundle id.

2. Server, in `laravel-backend/.env`:

```bash
GOOGLE_CLIENT_ID=<web client id>
GOOGLE_ANDROID_CLIENT_ID=<android client id>
GOOGLE_IOS_CLIENT_ID=<ios client id>
```

   All of them are accepted audiences — a token minted for any platform is
   valid, and `GoogleIdentityService` rejects anything minted for a different
   app entirely. That `aud` check is the one that matters: without it, an ID
   token from *any* app using Google Sign-In would buy a session here.

3. App, at build time:

```bash
flutter run --dart-define=GOOGLE_SERVER_CLIENT_ID=<web client id>
```

   On Android this must be the **Web** client id, not the Android one. Pass the
   Android one and the plugin returns an access token with `idToken` null, and
   sign-in fails with nothing useful to show the user.

Accounts link by verified email in one direction only: an existing password
account gains a Google identity, but a Google account never gains a password.

## Delivery

Checkout quotes every enabled carrier through `POST /delivery/quote` and shows
one option per speed — instant, same-day, express, standard, heavy. Which
partner fulfils it is the server's decision, not the customer's: a 40 kg item
routes to Porter because nothing else can carry it, a COD order drops the rider
networks because they will not collect cash, and an intercity order drops them
because they are intracity only.

Every figure on the checkout screen is advisory. The server re-quotes the
delivery fee, re-validates the coupon and re-caps the loyalty redemption when
the order is placed, so a tampered client produces a correct order rather than a
cheap one.

All five carriers currently run in **sandbox** — no partner credentials are
configured — and the checkout screen says so rather than presenting invented
rates as live quotes.

## Not built yet

Product Q&A, the reels feed, multiple named wishlists (the app flattens them
into one saved view), review photo upload, and push notifications — the
notification list is polled, not pushed.

Store submission is still blocked: `fastlane/Appfile` carries placeholder
`XXXXXXXXXX` team ids and there is no `play_store_credentials.json`. Building a
release APK has been verified on this machine with Android SDK 36.1 and Java 17.

