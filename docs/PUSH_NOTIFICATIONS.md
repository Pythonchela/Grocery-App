# Push notifications

Every order and refund update is already stored by the API and shown in the
app's **Notifications** screen, with an unread badge on the Account tab. That
works with no setup, but only while the app is open. Push adds the nudge on the
lock screen when it is closed.

Push needs a Firebase project. Nothing in this repository can create one - it
belongs to your Google account - so it is the one step left to do by hand. The
code is finished and switches itself on when it finds the two files below.

## 1. Create the Firebase project (about 5 minutes)

1. Open <https://console.firebase.google.com> and **Add project**. Analytics is
   not needed.
2. **Project settings > General > Your apps > Android**. Package name:
   `in.haatvia.shop`. Register the app and **download
   `google-services.json`**.
3. **Project settings > Service accounts > Generate new private key**. This
   downloads a second JSON file - the service account the server uses to send.

## 2. Give the app its file

Build the release APK yourself (`flutter build apk --release --dart-define=API_BASE=...`).

```bash
# Windows PowerShell:  [Convert]::ToBase64String([IO.File]::ReadAllBytes("google-services.json"))
base64 -w0 google-services.json
```

Save the output as a repository secret named **`ANDROID_GOOGLE_SERVICES_JSON_BASE64`**
(Settings > Secrets and variables > Actions). The next build writes the file
into the app, applies the Firebase plugin and enables push. With no secret the
build still succeeds, just without push.

To try it on your own machine, copy `google-services.json` to
`marketplace_app/android/app/` and run `flutter run`. The file is git-ignored.

## 3. Give the server its key

Admin panel > **Integrations & API keys > Push notifications**. Paste the
*whole contents* of the service-account file and press **Test connection**. A
green result means Google accepted it. The key is stored encrypted and is never
shown again.

(Or set `FCM_SERVICE_ACCOUNT` in the server environment to the same JSON.)

## 4. Check it

Sign in on a phone with the new build and allow notifications when asked. Place a
test order from another account, or change an order's status in the admin panel:
the phone should buzz.

## How it behaves

- A phone registers its token after sign-in and removes it on sign-out. Signing
  in as someone else on the same phone moves the token to them.
- A shopper's notification preferences apply: if they switch off "Deals", no
  push is sent for deals.
- A push that cannot be delivered never fails the order or refund that caused it.
  Tokens Google reports as dead (app uninstalled) are deleted.
- Tapping a notification opens the order it is about.
- iOS needs an Apple developer account and an APNs key uploaded in Firebase, plus
  `GoogleService-Info.plist`; Android works with the steps above alone.
