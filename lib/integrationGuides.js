/**
 * Step-by-step guides shown on each Settings tab: where to get the keys, what to
 * paste where, and what to do when it does not work.
 *
 * Plain data on purpose. Text in `backticks` is shown as code. Nothing here is
 * HTML, and nothing here is a secret: it is the same for every store.
 *
 * Third-party consoles rename their menus now and then. The steps name the
 * thing to look for rather than a click path where the path is likely to move.
 *
 * Shape:
 *   facts   [label, value]       time, cost, what you need before starting
 *   parts   [{ title?, steps }]  one or more routes (two SMS providers, say)
 *   step    { title, body, code?, link?: { label, href } }
 *   fill    [field, where it comes from]
 *   trouble [what you see, what to do]
 */

const ANDROID_ID = 'in.bazaarx.store';

export const GUIDES = {
  overview: {
    title: 'Where to start',
    intro:
      'Set things up in this order. Each tab has its own step-by-step guide, so you can do one at a time and come back later. Nothing breaks while a tab is empty: the store falls back to a built-in behaviour and tells you what is missing.',
    facts: [
      ['Before you start', 'A domain with HTTPS, and a server where the store runs.'],
      ['Who can use this page', 'Full admins only. Every change asks for your password again.'],
    ],
    parts: [
      {
        steps: [
          {
            title: 'Shipping and pickup (this page)',
            body: 'Fill in where parcels are collected from. Couriers quote against this address.',
          },
          {
            title: 'Payments',
            body: 'Razorpay keys are set on the server, not here. Open the Payments tab for the exact steps.',
          },
          {
            title: 'Email and SMS',
            body: 'Order emails, and the one-time code for phone sign-in. Phone sign-in does not work in production until an SMS provider is set.',
          },
          {
            title: 'Delivery partners',
            body: 'Add the courier you actually use. A courier with no credentials only gives sandbox quotes.',
          },
          {
            title: 'File storage',
            body: 'Move product images off the server disk before you go live, so they survive a server change.',
          },
          {
            title: 'Google sign-in, push notifications and AI',
            body: 'Optional. Add them when you want them; each can be turned on later without rebuilding the app.',
          },
        ],
      },
    ],
  },

  general: {
    title: 'How to fill in shipping and pickup',
    intro: 'These are plain settings, not keys. Use the address couriers should collect parcels from.',
    facts: [
      ['Time', '5 minutes'],
      ['Cost', 'Free'],
    ],
    parts: [
      {
        steps: [
          {
            title: 'Enter the pickup address',
            body: 'Name, phone, street, city, state and PIN code of the place where parcels are packed. Use the same address as Admin → My shop.',
          },
          {
            title: 'Find the latitude and longitude',
            body: 'Open Google Maps, right-click the exact spot of your shop or warehouse, and click the numbers at the top of the menu to copy them. Paste the first number as Latitude and the second as Longitude.',
            link: { label: 'Open Google Maps', href: 'https://www.google.com/maps' },
          },
          {
            title: 'Decide on free shipping',
            body: '"Free shipping above" is checked after discounts. Enter 0 to charge shipping on every order.',
          },
          {
            title: 'Decide on automatic courier booking',
            body: 'On: marking an order shipped books the courier for you, and the courier charges your account. It needs a working courier on the Delivery partners tab. Off: you type the courier and tracking number yourself.',
          },
          {
            title: 'Set a safe default weight',
            body: 'Used for any product with no weight. Err on the heavy side: couriers bill by weight, and an underestimate is charged back to you.',
          },
        ],
      },
    ],
    trouble: [
      ['Quotes look wrong or are missing', 'Check the PIN code (six digits, no spaces) and that at least one courier is ticked on the Delivery partners tab.'],
    ],
  },

  google: {
    title: 'How to set up Google sign-in',
    intro:
      'Shoppers tap "Continue with Google" on the website and in the app. You create the sign-in in Google Cloud, then paste the IDs here. Client IDs are public identifiers, not secrets, so they are shown in full.',
    facts: [
      ['Time', 'About 20 minutes, plus a wait of a few minutes up to a few hours for Google to apply changes'],
      ['Cost', 'Free'],
      ['You need', 'A Google account, your site address (for example https://yourshop.in), and the app\'s package name'],
    ],
    parts: [
      {
        steps: [
          {
            title: 'Create a Google Cloud project',
            body: 'Sign in to the Google Cloud console with the Google account that should own this. Open the project picker at the top, choose New project, name it after your store and create it. Make sure it is the selected project afterwards.',
            link: { label: 'Open Google Cloud console', href: 'https://console.cloud.google.com/' },
          },
          {
            title: 'Set up the consent screen',
            body: 'Go to APIs & Services → OAuth consent screen (newer consoles call it Google Auth Platform). Choose External. Enter the app name (your store name), a support email and a developer contact email. Leave the scopes at the defaults (email, profile, openid): they need no Google review.',
          },
          {
            title: 'Publish the consent screen',
            body: 'While it says Testing, only the test users you list can sign in. Click Publish app (or set the audience to In production) so every shopper can.',
          },
          {
            title: 'Create the Web client',
            body: 'Go to APIs & Services → Credentials → Create credentials → OAuth client ID → Application type: Web application. Under Authorized JavaScript origins add your site address exactly as shoppers type it, for example `https://yourshop.in`, and the `www` version too if you use it. For testing on your own computer also add `http://localhost:3000`. No redirect URI is needed. Create it and copy the Client ID (it ends in .apps.googleusercontent.com).',
            link: { label: 'Open Credentials', href: 'https://console.cloud.google.com/apis/credentials' },
          },
          {
            title: 'Create the Android client',
            body: `Create credentials → OAuth client ID → Application type: Android. Package name: \`${ANDROID_ID}\` (use your own if you changed the app's application ID). Paste the SHA-1 of the key that signs the app (next step). Make one Android client for each signing key you use: your debug key, your release key, and, if you publish on Google Play with Play App Signing, the key Google signs with.`,
          },
          {
            title: 'Get the SHA-1 fingerprints',
            body: 'For your own debug key, run this in a terminal (on Windows use `%USERPROFILE%\\.android\\debug.keystore` in place of the `~/.android` path). For the release key, use your release keystore and its alias. For the Play key, open Play Console → your app → Test and release → App integrity → App signing, and copy the SHA-1 of the App signing key certificate.',
            code: 'keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android',
          },
          {
            title: 'Paste the Web client ID here and save',
            body: 'Paste the Web client ID into "Web client ID" below, save, and confirm with your password. The website shows the button within a minute. The phone app picks it up the next time it opens; you do not need to rebuild it.',
          },
          {
            title: 'Try it',
            body: 'Open the store in a private window, choose Log in, and use Continue with Google. On a phone, open the app, sign out, and try again.',
          },
        ],
      },
    ],
    fill: [
      ['Web client ID', 'The Client ID of the Web application client. The website and the app both use it.'],
      ['Web client ID (storefront)', 'Leave empty unless the website uses a different Web client from the app.'],
      ['Android client ID', 'Optional. The Client ID of the Android client. The Android client must exist in the same project for sign-in to work on the phone, but the app sends the Web client ID.'],
      ['iOS client ID', 'Only if you later publish an iPhone app.'],
    ],
    trouble: [
      ['The Continue with Google button is missing', 'No Web client ID is saved yet, or the page has not reloaded. Save one, then refresh.'],
      ['On the phone: "ApiException: 10" or DEVELOPER_ERROR', 'The app\'s package name or signing key does not match an Android client in the same Google Cloud project. Add the SHA-1 of the key that built this copy of the app.'],
      ['"Error 400: origin_mismatch" on the website', 'Your site address is not in Authorized JavaScript origins, or differs by https/http, www or a trailing path. Add it exactly. Allow up to a few hours for Google to apply it.'],
      ['"Access blocked" or only some people can sign in', 'The consent screen is still in Testing. Publish it.'],
    ],
  },

  email: {
    title: 'How to set up email',
    intro:
      'Order confirmations and account emails are sent through an SMTP service. Any provider that offers SMTP works. Until a mailer is set, emails are only written to the server log and nobody receives them.',
    facts: [
      ['Time', '15 minutes, plus DNS changes that can take a few hours to apply'],
      ['Cost', 'Most providers have a free tier that covers a small store'],
      ['You need', 'A domain you control, and an address on it to send from (for example orders@yourshop.in)'],
    ],
    parts: [
      {
        steps: [
          {
            title: 'Choose a provider',
            body: 'Amazon SES, Brevo, Resend and Mailgun are common choices. Gmail works for a very small store. Sign up and open the provider\'s SMTP page.',
          },
          {
            title: 'Verify your sending domain',
            body: 'The provider gives you a few DNS records (SPF and DKIM). Add them where your domain is managed. Without this, mail is rejected or lands in spam. Wait until the provider shows the domain as verified.',
          },
          {
            title: 'Collect the SMTP details',
            body: 'You need four things from the provider: the SMTP host, the port (587 for most), a username, and a password. Some providers call the password an SMTP key or API key. Use the SMTP credentials, not the account login, unless the table below says otherwise.',
          },
          {
            title: 'Fill in this tab',
            body: 'Set Mailer to SMTP. Enter the host, port, username and password. Set From address to an address on the domain you verified, and From name to your store name.',
          },
          {
            title: 'Send a test email',
            body: 'Click Send test email. It goes to the email address of your admin account and uses the values as typed, so you can test before saving. When it arrives, save.',
          },
        ],
      },
    ],
    table: {
      title: 'What the common providers use',
      head: ['Provider', 'SMTP host', 'Port', 'Username', 'Password'],
      rows: [
        ['Amazon SES', 'email-smtp.<region>.amazonaws.com', '587', 'SMTP username from "Create SMTP credentials"', 'SMTP password from the same step (not your AWS password)'],
        ['Brevo', 'smtp-relay.brevo.com', '587', 'The login shown on its SMTP & API page', 'An SMTP key you generate there'],
        ['Resend', 'smtp.resend.com', '587', 'resend', 'Your Resend API key'],
        ['Gmail', 'smtp.gmail.com', '587', 'Your full Gmail address', 'An App Password (needs 2-step verification turned on)'],
      ],
      note: 'Check the provider\'s own SMTP page for the exact values for your account and region.',
    },
    fill: [
      ['Mailer', 'SMTP to send real email. Log only writes to the server log.'],
      ['From address', 'An address on a domain or address your provider has verified.'],
      ['SMTP host, port', 'From the provider\'s SMTP page. Port 465 uses SSL automatically.'],
      ['SMTP username, password', 'From the provider. The password is stored encrypted and never shown again.'],
    ],
    trouble: [
      ['The test says authentication failed', 'Wrong username or password, or you used the account login instead of the SMTP credentials.'],
      ['The test works but customers do not get mail', 'The domain is not fully verified, or the From address is not on it. Check the provider\'s dashboard for rejected or spam-filtered messages.'],
      ['"That host resolves to a private or reserved address"', 'The host must be a public address. A mail server on a private network is not allowed from this screen.'],
    ],
  },

  sms: {
    title: 'How to set up SMS and phone sign-in',
    intro:
      'The SMS provider sends the one-time code for phone sign-in, and can text order updates. For Indian numbers use MSG91. With no provider, phone sign-in is switched off in production rather than pretending to send.',
    facts: [
      ['Time', 'MSG91: a few days, mostly waiting for India\'s DLT approvals. Twilio: 15 minutes'],
      ['Cost', 'Pay per message. Order texts cost extra, so they are off by default'],
      ['You need', 'A registered business for MSG91 in India; a card for Twilio'],
    ],
    parts: [
      {
        title: 'MSG91 (Indian numbers)',
        steps: [
          {
            title: 'Create the MSG91 account',
            body: 'Sign up, complete the business verification, and add some credit to the wallet.',
            link: { label: 'Open MSG91', href: 'https://msg91.com/' },
          },
          {
            title: 'Register on DLT',
            body: 'By Indian law, business texts need a DLT registration with a telecom operator (Jio, Airtel, Vi or BSNL). Register your business as an entity, register a sender ID (header), and register one message template for the login code. MSG91\'s help section walks through it. Approval takes a few days.',
            link: { label: 'MSG91 DLT help', href: 'https://msg91.com/help/dlt-registration-in-india' },
          },
          {
            title: 'Create the OTP flow',
            body: 'In MSG91, add your DLT template and create a Flow (SMS) from it. The message must contain one variable named exactly `otp`, written `##otp##` in MSG91 (the DLT text itself uses `{#var#}`). Copy the flow\'s Template ID.',
          },
          {
            title: 'Copy the auth key',
            body: 'Find your Authkey in the MSG91 dashboard (search for Authkey or open the API section) and copy it.',
          },
          {
            title: 'Fill in the MSG91 rows and send a test',
            body: 'Set SMS provider to MSG91, paste the Auth key and the OTP template ID, type your own 10-digit number next to the test button, and click Send test message. Save when the text arrives.',
          },
          {
            title: 'Optional: order updates',
            body: 'To text order updates, register a second template with one variable named `message`, create its flow, paste its ID as the order template, and set "Also text order updates" to On.',
          },
        ],
      },
      {
        title: 'Twilio (free-text, works worldwide)',
        steps: [
          {
            title: 'Create the Twilio account',
            body: 'Sign up and verify your email and phone. A trial account can only text numbers you have verified in the console.',
            link: { label: 'Open Twilio', href: 'https://www.twilio.com/' },
          },
          {
            title: 'Copy the Account SID and Auth Token',
            body: 'Both are on the Twilio Console home page. The SID starts with `AC`. Click the eye to reveal the Auth Token.',
          },
          {
            title: 'Get a sender',
            body: 'Buy a phone number that can send SMS, or create a Messaging Service and use its SID (starts with `MG`). Texting Indian numbers from abroad is restricted by DLT rules, so for an Indian store MSG91 is the practical choice.',
          },
          {
            title: 'Fill in the Twilio rows and send a test',
            body: 'Set SMS provider to Twilio, paste the SID, the Auth Token and the sender (a number such as `+14155550123`, or the MG SID). Send a test message, then save.',
          },
        ],
      },
    ],
    fill: [
      ['SMS provider', 'MSG91 or Twilio. Log only means send nothing.'],
      ['MSG91 auth key', 'Your Authkey from the MSG91 dashboard.'],
      ['MSG91 OTP template ID', 'The Template ID of the flow whose message has the `otp` variable.'],
      ['Twilio account SID / auth token / sender', 'From the Twilio Console, plus the number or Messaging Service you chose.'],
    ],
    trouble: [
      ['The provider accepted the test but nothing arrives', 'On MSG91 the message text must match the DLT-approved template exactly, and the sender ID must be approved. Check the delivery report in MSG91.'],
      ['"No approved template" for order updates', 'You turned on order updates but did not enter an order template ID. Add it or turn updates off.'],
      ['Phone sign-in says it is unavailable', 'No SMS provider is set. Choose one and save.'],
    ],
  },

  couriers: {
    title: 'How to connect a delivery partner',
    intro:
      'Add only the courier you actually use. Shoppers are quoted only the couriers you tick under "Couriers to offer". A courier with no credentials gives sandbox quotes and ships nothing.',
    facts: [
      ['Time', 'Shiprocket: 15 minutes. Others: after the courier approves your business'],
      ['Cost', 'You pay the courier per parcel'],
      ['You need', 'An approved account with the courier, and the pickup address from the Overview tab'],
    ],
    parts: [
      {
        title: 'Shiprocket',
        steps: [
          {
            title: 'Create and verify a Shiprocket account',
            body: 'Complete the business and bank verification so you can ship.',
            link: { label: 'Open Shiprocket', href: 'https://www.shiprocket.in/' },
          },
          {
            title: 'Add your pickup address in Shiprocket',
            body: 'Add the address in Shiprocket\'s pickup addresses and note the exact name you gave it. That name is the "pickup location" below. Shiprocket\'s first address is usually called Primary.',
          },
          {
            title: 'Create an API user',
            body: 'In Shiprocket go to Settings → API → Configure → Create an API user. Use a different email from your login (one not already registered on Shiprocket) and set a password. You can have up to four API users. This is a separate login used only by the store.',
          },
          {
            title: 'Fill in and test',
            body: 'Enter the API user\'s email and password and the pickup location name, click Test Shiprocket, then save.',
          },
        ],
      },
      {
        title: 'Delhivery',
        steps: [
          {
            title: 'Get an API token',
            body: 'Delhivery issues the token for your business account. Ask your Delhivery account manager for the production API token (it is also in the API or integration settings of your Delhivery panel). The token is long; copy it fully.',
          },
          {
            title: 'Find the client name',
            body: 'This is your registered client or warehouse name exactly as it appears in Delhivery, including capitals and spaces.',
          },
        ],
      },
      {
        title: 'Ola, Rapido and Porter (same-day, local)',
        steps: [
          {
            title: 'Ask for production API access',
            body: 'These are business accounts. After onboarding, ask each company\'s business team for production API credentials: client ID and secret for Ola and Rapido, an API key for Porter. Make sure they are production credentials, not test ones.',
          },
          {
            title: 'Check the server address',
            body: 'Where each courier\'s API lives is set on the server, not here, so a stolen admin session cannot redirect your credentials. Porter\'s default address is its test environment. Ask whoever runs the server to set `PORTER_BASE_URL` to the production address before going live.',
          },
        ],
      },
    ],
    fill: [
      ['Couriers to offer', 'Tick the ones you use. Shoppers are only quoted these.'],
      ['Shiprocket email, password, pickup location', 'The API user you created, and the pickup address name from Shiprocket.'],
      ['Delhivery API token, client name', 'From Delhivery, as above.'],
      ['Ola, Rapido, Porter', 'The credentials each company issued.'],
    ],
    trouble: [
      ['Shiprocket test fails to log in', 'You used your main login. Use the separate API user\'s email and password.'],
      ['"Pickup location not found" when booking', 'The pickup location name here must match the name in Shiprocket exactly.'],
      ['Quotes appear but nothing can be booked', 'The courier has no credentials yet and is quoting in sandbox mode.'],
    ],
  },

  push: {
    title: 'How to set up push notifications',
    intro:
      'Push sends order and refund updates to shoppers\' phones through Firebase. Two things are needed: a file inside the app build, and a key here on the server. Without push the app still shows every update in its Notifications screen.',
    facts: [
      ['Time', '20 minutes, then a new app build'],
      ['Cost', 'Free'],
      ['You need', 'A Google account, and the app\'s package name'],
    ],
    parts: [
      {
        steps: [
          {
            title: 'Create a Firebase project',
            body: 'Open the Firebase console, choose Add project and follow the prompts. You can switch Google Analytics off.',
            link: { label: 'Open Firebase console', href: 'https://console.firebase.google.com/' },
          },
          {
            title: 'Add the Android app',
            body: `In the project, add an Android app. Package name: \`${ANDROID_ID}\` (or your own application ID). Register it and download \`google-services.json\`.`,
          },
          {
            title: 'Put the file into the app and rebuild',
            body: 'Place it at `marketplace_app/android/app/google-services.json` and build the app again. The app turns push on only when this file is present at build time. Keep the file out of public repositories you share.',
          },
          {
            title: 'Create the service account key',
            body: 'In Firebase go to Project settings (the gear) → Service accounts → Generate new private key. A JSON file downloads. The server uses it to send messages.',
          },
          {
            title: 'Paste it here',
            body: 'Open the JSON file in a text editor, copy everything, and paste it into the field below. Click Test connection (Google checks the key without sending anything), then save. After saving, delete the downloaded file. It is stored encrypted here and never shown again.',
          },
        ],
      },
    ],
    fill: [
      ['Firebase service account (JSON)', 'The whole private key file from Project settings → Service accounts.'],
    ],
    trouble: [
      ['"That is not a Firebase service account file"', 'You pasted google-services.json, or only part of the file. The service account key contains project_id, client_email and private_key.'],
      ['"Google rejected this service account"', 'The key was deleted or revoked in Firebase. Generate a new one and paste it again.'],
      ['The test passes but no phone gets notifications', 'The app was built without google-services.json, or with one for a different package name. Rebuild with the right file.'],
    ],
  },

  storage: {
    title: 'How to set up file storage',
    intro:
      'Product images and other uploads are kept on the server\'s disk until you choose a bucket. On the disk they are lost if you ever change servers. A bucket keeps them safe and fast. Cloudflare R2 is the simplest; Amazon S3 and any S3-compatible service work too.',
    facts: [
      ['Time', '20 minutes'],
      ['Cost', 'R2 has a free allowance and no download fees. S3 charges for storage and traffic'],
      ['You need', 'A Cloudflare or AWS account'],
    ],
    parts: [
      {
        title: 'Cloudflare R2',
        steps: [
          {
            title: 'Create a bucket',
            body: 'In the Cloudflare dashboard open R2 Object Storage and create a bucket, for example `mystore-media`.',
            link: { label: 'Open Cloudflare', href: 'https://dash.cloudflare.com/' },
          },
          {
            title: 'Make it publicly readable',
            body: 'Open the bucket → Settings → Public access. For production connect a custom domain such as `cdn.yourshop.in`. For a quick test you can enable the r2.dev address. Copy the public address: that is the Public URL.',
          },
          {
            title: 'Create an API token',
            body: 'R2 → Manage API tokens → Create API token, with permission Object Read & Write, limited to this bucket. Copy the Access Key ID and the Secret Access Key now. The secret is shown only once.',
          },
          {
            title: 'Note the endpoint',
            body: 'It looks like `https://<your-account-id>.r2.cloudflarestorage.com` and is shown with the token. Region is `auto`.',
          },
        ],
      },
      {
        title: 'Amazon S3',
        steps: [
          {
            title: 'Create the bucket',
            body: 'In the AWS console create an S3 bucket in a nearby region (for India, Mumbai: `ap-south-1`).',
            link: { label: 'Open AWS console', href: 'https://console.aws.amazon.com/s3/' },
          },
          {
            title: 'Allow public reads',
            body: 'Turn off "Block all public access" for this bucket and add a bucket policy that allows `s3:GetObject` for everyone, or put CloudFront in front. Leave ACLs disabled; the store does not use them.',
          },
          {
            title: 'Create an access key',
            body: 'In IAM create a user for the store with a policy that allows `s3:PutObject`, `s3:GetObject`, `s3:DeleteObject` and `s3:ListBucket` on this bucket only. Create an access key for it and copy both values.',
          },
          {
            title: 'Public URL',
            body: 'Your CloudFront address, or `https://<bucket>.s3.<region>.amazonaws.com`. Leave Endpoint empty for Amazon S3.',
          },
        ],
      },
      {
        title: 'Then, for both',
        steps: [
          {
            title: 'Fill in this tab and test',
            body: 'Set Storage to the S3 option, then enter the bucket, Public URL, region, endpoint (R2 only) and the two keys. Click Test storage. It writes a small file, reads it back, fetches it over the Public URL and deletes it. Save when it passes.',
          },
          {
            title: 'Move the images you already uploaded',
            body: 'Switching affects new uploads only. Whoever runs the server moves the old ones. Run the first command to see what would move, then the second to do it.',
            code: 'php artisan media:migrate\nphp artisan media:migrate --apply',
          },
        ],
      },
    ],
    fill: [
      ['Public bucket', 'The bucket name.'],
      ['Public URL', 'The https address the bucket\'s files are served from.'],
      ['Region', '`auto` for R2, or the AWS region such as `ap-south-1`.'],
      ['Endpoint', 'The R2 endpoint, or empty for Amazon S3.'],
      ['Access key ID, Secret access key', 'From the token or IAM user. Stored encrypted and never shown again.'],
    ],
    trouble: [
      ['"Uploads work, but the file is not readable at the Public URL"', 'The bucket is not public yet, or the Public URL is wrong. Images would upload and then never show.'],
      ['"The key is valid but is not allowed to write"', 'The token or policy lacks write or delete permission on this bucket.'],
      ['"The secret access key is wrong (or the region is)"', 'Re-copy the secret. For R2 the region must be `auto`.'],
    ],
  },

  gemini: {
    title: 'How to get a Gemini API key',
    intro:
      'Gemini powers AI search, review summaries and smart product import. It is optional: without a key the store uses its built-in behaviour.',
    facts: [
      ['Time', '2 minutes'],
      ['Cost', 'A free tier with rate limits. Heavy use needs billing turned on in Google Cloud'],
      ['You need', 'A Google account'],
    ],
    parts: [
      {
        steps: [
          {
            title: 'Open Google AI Studio',
            body: 'Sign in with a Google account and open the API keys page.',
            link: { label: 'Open AI Studio API keys', href: 'https://aistudio.google.com/apikey' },
          },
          {
            title: 'Create the key',
            body: 'Choose Create API key and pick or create a Google Cloud project when asked. Copy the key. It starts with `AIza`.',
          },
          {
            title: 'Paste, test and save',
            body: 'Paste it below and click Test connection. The test only lists the available models, so it costs nothing. Then save.',
          },
          {
            title: 'Optional: limit the key',
            body: 'In Google Cloud → APIs & Services → Credentials you can restrict the key to the Generative Language API, which limits the damage if it ever leaks.',
          },
        ],
      },
    ],
    fill: [['API key', 'The key from AI Studio. Stored encrypted; later you only see whether it is set and its last four characters.']],
    trouble: [
      ['The test says the key was rejected', 'A character was lost when copying, or the key was deleted. Create a new one.'],
      ['It worked, then stopped', 'You reached the free tier\'s limit. Wait, or turn on billing for the project.'],
    ],
  },

  payments: {
    title: 'How to set up payments (Razorpay)',
    intro:
      'Payment keys are deliberately not editable on this page. They move money, so they live in the server\'s private configuration file, where a stolen admin session cannot change them. This page only shows how they are set up. Whoever runs the server does steps 3 and 4.',
    facts: [
      ['Time', '30 minutes, plus Razorpay\'s business verification for live payments'],
      ['Cost', 'Razorpay charges a fee per payment'],
      ['You need', 'A Razorpay account, and access to the server\'s `.env` file'],
    ],
    parts: [
      {
        steps: [
          {
            title: 'Create the Razorpay account',
            body: 'Sign up and complete activation (business and bank details) to accept live payments. You can start in Test mode straight away: no real money moves.',
            link: { label: 'Open Razorpay', href: 'https://dashboard.razorpay.com/' },
          },
          {
            title: 'Generate the API keys',
            body: 'In the dashboard choose Test mode or Live mode, then Account & Settings → API Keys → Generate Key. You get a Key ID (`rzp_test_…` or `rzp_live_…`) and a Key Secret. The secret is shown once, so save it.',
          },
          {
            title: 'Add the webhook',
            body: 'In Razorpay go to Settings → Webhooks → Add new webhook. Use the Webhook URL shown on this tab, invent a long random secret, and tick the events payment.captured, refund.processed and refund.failed. Test mode and Live mode have separate webhooks, each with its own secret.',
          },
          {
            title: 'Put the keys on the server',
            body: 'Add these lines to the backend\'s `.env` file, then clear the config cache so they apply.',
            code: 'RAZORPAY_KEY_ID=rzp_test_YOUR_KEY_ID\nRAZORPAY_KEY_SECRET=your-key-secret\nRAZORPAY_WEBHOOK_SECRET=the-secret-you-typed-in-razorpay\n\nphp artisan config:clear',
          },
          {
            title: 'Check this tab',
            body: 'Mode should show Test or Live, Webhook secret should be Set, and Online payment at checkout should be Available. Place a test order with a Razorpay test card to confirm.',
          },
          {
            title: 'Going live',
            body: 'Repeat steps 2 to 4 in Live mode with the `rzp_live_` keys and a live webhook. Never leave test keys on the production server.',
          },
        ],
      },
    ],
    trouble: [
      ['Online payment shows Unavailable', 'The Key ID or Key Secret is missing on the server, or the config cache was not cleared.'],
      ['Customers pay but the order stays unpaid', 'The webhook is missing, points at the wrong address, or its secret differs from RAZORPAY_WEBHOOK_SECRET. Every webhook with a wrong secret is refused.'],
      ['Mode shows Test on the live site', 'The server still has rzp_test_ keys.'],
    ],
  },
};
