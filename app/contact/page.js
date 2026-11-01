import LegalPage, { Section, List } from '../../components/legal/LegalPage';
import { LEGAL } from '../../lib/legal';

export const metadata = {
  title: `Contact us | ${LEGAL.brand}`,
  description: `How to reach ${LEGAL.brand} for help with an order, a return, your account or a complaint.`,
  alternates: { canonical: '/contact' },
};

export default function ContactPage() {
  const mail = (
    <a href={`mailto:${LEGAL.email}`} className="text-accent font-bold hover:underline">{LEGAL.email}</a>
  );

  return (
    <LegalPage
      title="Contact us"
      updated={LEGAL.policiesUpdated}
      intro="The quickest way to get help with an order is from your account, where we can already see your order. You can also write to us by email."
    >
      <Section id="app" title="From your account">
        <p>
          Open <strong className="text-ink">Account, then Support</strong> in the app or on the website, and describe the
          problem. You can attach photos, and you will see our replies in the same place. For anything about a delivered
          item, start from <strong className="text-ink">Orders</strong> and tap Return.
        </p>
      </Section>

      <Section id="email" title="By email">
        <p>
          Write to {mail}. Please include your order number, or the email address or phone number on your account, so we
          can find it quickly.
        </p>
      </Section>

      <Section id="complaints" title="Complaints and grievances">
        <p>
          If you are not happy with our answer, write to the Grievance Officer at {mail} with the subject
          &ldquo;Grievance&rdquo;. We acknowledge a complaint within 48 hours and aim to resolve it within one month.
        </p>
      </Section>

      <Section id="more" title="Before you write">
        <List
          items={[
            'Track an order: Orders in the app.',
            'Return or refund questions: see the Refund and Returns Policy.',
            'Delivery questions: see the Shipping Policy.',
            'Delete your account: see the account deletion page.',
          ]}
        />
        <p>
          <a href="/faqs" className="text-accent font-bold hover:underline">Frequently asked questions</a>,{' '}
          <a href="/refund-policy" className="text-accent font-bold hover:underline">Refund and Returns Policy</a>,{' '}
          <a href="/shipping-policy" className="text-accent font-bold hover:underline">Shipping Policy</a>,{' '}
          <a href="/delete-account" className="text-accent font-bold hover:underline">Delete your account</a>.
        </p>
      </Section>
    </LegalPage>
  );
}
