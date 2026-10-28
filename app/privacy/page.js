import LegalPage, { Section, List } from '../../components/legal/LegalPage';
import { LEGAL } from '../../lib/legal';

export const metadata = {
  title: `Privacy Policy | ${LEGAL.brand}`,
  description: `How ${LEGAL.brand} collects, uses, shares and protects your personal information in its app and website, and how to ask us to delete it.`,
  alternates: { canonical: '/privacy' },
};

const SECTIONS = [
  { id: 'who', title: 'Who we are' },
  { id: 'collect', title: 'What we collect' },
  { id: 'use', title: 'How we use it' },
  { id: 'share', title: 'Who we share it with' },
  { id: 'ai', title: 'AI features' },
  { id: 'keep', title: 'How long we keep it' },
  { id: 'rights', title: 'Your choices and rights' },
  { id: 'security', title: 'How we protect it' },
  { id: 'children', title: 'Children' },
  { id: 'transfers', title: 'Where it is processed' },
  { id: 'changes', title: 'Changes to this policy' },
  { id: 'contact', title: 'Contact and grievances' },
];

export default function PrivacyPolicyPage() {
  const mail = (
    <a href={`mailto:${LEGAL.email}`} className="text-accent font-bold hover:underline">{LEGAL.email}</a>
  );

  return (
    <LegalPage
      title="Privacy Policy"
      updated={LEGAL.updated}
      sections={SECTIONS}
      intro={`This policy explains what personal information ${LEGAL.brand} collects when you use our Android app and our website at ${LEGAL.site}, what we do with it, who we share it with, and the choices you have. We collect only what we need to run the shop and deliver your orders. We do not sell your personal information.`}
    >
      <Section id="who" title="Who we are">
        <p>
          {LEGAL.brand} (&ldquo;we&rdquo;, &ldquo;us&rdquo;) runs the {LEGAL.brand} shopping app for Android and the website
          at {LEGAL.site}. We decide why and how your personal information is used, which makes us the data controller
          (the &ldquo;data fiduciary&rdquo; under India&apos;s Digital Personal Data Protection Act, 2023). You can reach us at {mail}.
        </p>
      </Section>

      <Section id="collect" title="What we collect">
        <p><strong className="text-ink">Information you give us</strong></p>
        <List
          items={[
            'Account details: your name, email address, phone number and password. We store passwords only in a hashed form, never as plain text.',
            'Sign-in with Google: if you choose it, Google tells us your name, email address, profile picture and a Google account ID. We never see your Google password.',
            'Delivery addresses: the name, phone number and address you enter at checkout or in your address book.',
            'Orders: what you bought, the amounts, the delivery status, and whether payment succeeded.',
            'Wallet, loyalty points and referral code linked to your account.',
            'What you post or send: reviews, questions, return and refund requests, support messages, and any photos or files you attach to them.',
            'Your wishlist and cart.',
          ]}
        />
        <p><strong className="text-ink">Information collected automatically</strong></p>
        <List
          items={[
            'Notifications: if you allow notifications in the app, a push token that identifies your phone to Google Firebase Cloud Messaging so we can send order updates.',
            'Technical data: your IP address, device and browser type, and server logs that we use to keep the service secure and to find and fix faults. Error reports we collect have passwords, keys and cookies removed before they leave our servers.',
            'On the website, your browser stores a sign-in token, your cart and your display preferences on your own device so that you stay signed in and keep your cart between visits.',
          ]}
        />
        <p><strong className="text-ink">What we do not collect</strong></p>
        <List
          items={[
            'Your location. The app does not ask for location access.',
            'Your contacts, camera, microphone or files. The only permissions the app uses are technical: network access, receiving push messages, showing notifications, vibration and running small background tasks such as checking an order\'s status.',
            'Your card, UPI or bank details. Payments are taken by Razorpay on its own secure screen. We receive only the result and a payment reference.',
            'Advertising or analytics identifiers. We do not use advertising trackers or third-party analytics on the app or the website.',
          ]}
        />
      </Section>

      <Section id="use" title="How we use it">
        <List
          items={[
            'To create and secure your account, and to sign you in.',
            'To process orders: take payment, pack, ship and deliver your items, and handle cancellations, returns and refunds.',
            'To send you order updates by push notification, SMS or email, including one-time codes for signing in.',
            'To answer your questions and support requests.',
            'To prevent fraud and abuse, such as fake reviews and unauthorised payments, and to keep our systems safe.',
            'To improve search and show helpful summaries of reviews (see AI features).',
            'To meet our legal obligations, including tax, accounting and consumer-protection rules.',
          ]}
        />
        <p>
          We rely on your agreement when you create an account or turn on notifications, on the need to carry out your
          orders, and on our legal obligations. You can withdraw agreement for notifications at any time in your phone&apos;s
          settings.
        </p>
      </Section>

      <Section id="share" title="Who we share it with">
        <p>We share personal information only where it is needed to do the job, and only with the people below.</p>
        <List
          items={[
            'Payment provider: Razorpay processes your payment and sends us the outcome. Its checkout screen may also collect device and network information to prevent fraud, under Razorpay\'s own privacy policy.',
            'Delivery partners: couriers we book for your parcel, such as Shiprocket, Delhivery and local delivery services, receive your name, phone number, delivery address and the contents of the parcel.',
            'Google: for sign-in with Google, and Firebase Cloud Messaging to deliver push notifications.',
            'Messaging providers: services that send our SMS one-time codes and emails, such as MSG91, Twilio or an email (SMTP) provider, receive your phone number or email address and the message.',
            'AI providers: see the next section.',
            'Hosting and storage: our web hosting company and, if enabled, a cloud storage service that holds uploaded images and files.',
            'Error monitoring: Sentry, if enabled, receives technical error reports with sensitive values removed.',
            'Authorities: we may disclose information when the law requires it or to protect our rights, our customers or the public.',
          ]}
        />
        <p>These providers may use your information only to provide their service to us. We do not sell your personal information or share it for advertising.</p>
      </Section>

      <Section id="ai" title="AI features">
        <p>
          Some features use artificial intelligence. When they are turned on, the text of your search, the review text we
          summarise, and, on the website, the messages you type to the shopping assistant are sent to our AI providers
          (Google Gemini and Anthropic) to produce the result. We send only the text needed for that request, not your
          name, email or phone number. A decision about your account or order is never made by AI alone.
        </p>
      </Section>

      <Section id="keep" title="How long we keep it">
        <p>
          We keep your account information while your account is open. When you ask us to delete your account we delete
          or anonymise it (see below). We keep order, payment and invoice records for as long as Indian tax, accounting
          and consumer law requires us to, and records needed to handle a dispute or prevent fraud for as long as that
          purpose lasts. Server logs are kept for a short period.
        </p>
      </Section>

      <Section id="rights" title="Your choices and rights">
        <List
          items={[
            'Access and correct: you can see and edit your name, email, phone and addresses in your account. For anything else, write to us.',
            'Delete your account and data: follow the steps on our account deletion page. We will act on your request within 30 days.',
            'Notifications: turn push notifications off in your phone settings, or ask us to stop SMS and email that are not needed for your orders.',
            'Google sign-in: you can remove our access in your Google Account settings under security and connections.',
            'Complain: if you think we have mishandled your information, write to us first. You may also complain to the Data Protection Board of India.',
          ]}
        />
        <p>
          Our account deletion page is at{' '}
          <a href="/delete-account" className="text-accent font-bold hover:underline">{LEGAL.site}/delete-account</a>.
        </p>
      </Section>

      <Section id="security" title="How we protect it">
        <p>
          All traffic between the app or website and our servers is encrypted with HTTPS. Passwords are stored hashed.
          Staff access is limited to what each person needs, and the keys that connect our services are encrypted and
          kept out of the app. No system is perfectly secure, so if we learn of a breach that affects you we will tell you
          and the authorities as the law requires.
        </p>
      </Section>

      <Section id="children" title="Children">
        <p>
          {LEGAL.brand} is meant for people aged 18 and over. We do not knowingly collect information from anyone under 18.
          If you believe a child has given us their information, write to us and we will delete it.
        </p>
      </Section>

      <Section id="transfers" title="Where it is processed">
        <p>
          Our servers and database are operated for us by our hosting provider. Some of our providers, such as
          Google, Anthropic and Sentry, process information in other countries. By using the service you understand that your
          information may be processed outside India by these providers, under their own safeguards.
        </p>
      </Section>

      <Section id="changes" title="Changes to this policy">
        <p>
          We may update this policy. The date at the top shows when it last changed. If a change is significant we will
          tell you in the app or by email before it takes effect.
        </p>
      </Section>

      <Section id="contact" title="Contact and grievances">
        <p>
          For privacy questions, requests, or complaints, write to the Grievance Officer at {mail}. We acknowledge a
          complaint within 48 hours and aim to resolve it within one month.
        </p>
        <p>{LEGAL.brand} &middot; {LEGAL.site}</p>
      </Section>
    </LegalPage>
  );
}
