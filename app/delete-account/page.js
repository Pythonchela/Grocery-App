import LegalPage, { Section, List } from '../../components/legal/LegalPage';
import { LEGAL } from '../../lib/legal';

export const metadata = {
  title: `Delete your account | ${LEGAL.brand}`,
  description: `How to ask ${LEGAL.brand} to delete your account and personal data, and what we keep.`,
  alternates: { canonical: '/delete-account' },
};

export default function DeleteAccountPage() {
  const address = LEGAL.email;
  const subject = encodeURIComponent(`Delete my ${LEGAL.brand} account`);
  const body = encodeURIComponent('Please delete my account and personal data.\n\nRegistered email or phone number:\n');

  return (
    <LegalPage
      title="Delete your account"
      updated={LEGAL.updated}
      intro={`You can ask ${LEGAL.brand} to delete your account and the personal information we hold about you at any time. This page applies to the ${LEGAL.brand} Android app and the website at ${LEGAL.site}.`}
    >
      <Section id="how" title="How to ask">
        <ol className="list-decimal pl-5 space-y-2">
          <li>
            Send an email to{' '}
            <a href={`mailto:${address}?subject=${subject}&body=${body}`} className="text-accent font-bold hover:underline">{address}</a>{' '}
            from the email address on your account, with the subject &ldquo;Delete my {LEGAL.brand} account&rdquo;.
          </li>
          <li>If you signed up with a phone number only, include that number and tell us the name on the account.</li>
          <li>We may reply to confirm it is really you before we delete anything. This protects your account from someone else.</li>
          <li>We delete the account and confirm to you by email. We act within 30 days of your request.</li>
        </ol>
      </Section>

      <Section id="deleted" title="What is deleted">
        <List
          items={[
            'Your profile: name, email address, phone number, profile picture and password.',
            'Your saved addresses, wishlist and cart.',
            'Your notification settings and the push token for your phone.',
            'Your wallet balance, loyalty points and referral code. These cannot be used once the account is deleted.',
            'Your sign-in link to Google, if you used it.',
          ]}
        />
      </Section>

      <Section id="kept" title="What we must keep">
        <p>
          Some records stay because the law requires them. Order, payment and invoice records are kept for the period that
          Indian tax, accounting and consumer law requires. We remove your name and contact details from them wherever the
          law allows. We may also keep what is needed to settle a dispute or prevent fraud, and for no longer than that
          purpose lasts.
        </p>
      </Section>

      <Section id="before" title="Before you delete">
        <List
          items={[
            'Open orders may need to be delivered or cancelled first. We will tell you if that is the case.',
            'Deletion cannot be undone. If you only want fewer messages, turn notifications off in your phone settings instead.',
          ]}
        />
        <p>
          More on how we handle your information is in our{' '}
          <a href="/privacy" className="text-accent font-bold hover:underline">Privacy Policy</a>.
        </p>
      </Section>
    </LegalPage>
  );
}
