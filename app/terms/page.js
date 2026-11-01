import LegalPage, { Section, List } from '../../components/legal/LegalPage';
import { LEGAL } from '../../lib/legal';

export const metadata = {
  title: `Terms of Service | ${LEGAL.brand}`,
  description: `The terms for shopping with ${LEGAL.brand}: ordering, prices, payment, delivery, returns and your account.`,
  alternates: { canonical: '/terms' },
};

const SECTIONS = [
  { id: 'agreement', title: 'Using these terms' },
  { id: 'account', title: 'Your account' },
  { id: 'orders', title: 'Orders and prices' },
  { id: 'payment', title: 'Payment' },
  { id: 'delivery', title: 'Delivery, cancellation and returns' },
  { id: 'content', title: 'Reviews and what you post' },
  { id: 'use', title: 'Acceptable use' },
  { id: 'liability', title: 'Our responsibility' },
  { id: 'law', title: 'Governing law' },
  { id: 'changes', title: 'Changes' },
  { id: 'contact', title: 'Contact' },
];

export default function TermsPage() {
  const mail = (
    <a href={`mailto:${LEGAL.email}`} className="text-accent font-bold hover:underline">{LEGAL.email}</a>
  );

  return (
    <LegalPage
      title="Terms of Service"
      updated={LEGAL.policiesUpdated}
      sections={SECTIONS}
      intro={`These terms apply when you use the ${LEGAL.brand} app or the website at ${LEGAL.site} and buy from us. By creating an account or placing an order you agree to them. If you do not agree, please do not use the service.`}
    >
      <Section id="agreement" title="Using these terms">
        <p>
          {LEGAL.brand} (&ldquo;we&rdquo;, &ldquo;us&rdquo;) sells products to shoppers in India through the app and website.
          You must be 18 or older to place an order. These terms work together
          with our{' '}
          <a href="/privacy" className="text-accent font-bold hover:underline">Privacy Policy</a>,{' '}
          <a href="/refund-policy" className="text-accent font-bold hover:underline">Refund and Returns Policy</a> and{' '}
          <a href="/shipping-policy" className="text-accent font-bold hover:underline">Shipping Policy</a>.
        </p>
      </Section>

      <Section id="account" title="Your account">
        <List
          items={[
            'Give us correct details: your name, phone number, email and delivery address.',
            'Keep your password and any one-time codes to yourself. You are responsible for what happens under your account.',
            'Tell us at once if you think someone else has used your account.',
            'We may suspend or close an account that breaks these terms or is used for fraud or abuse.',
            'You can ask us to delete your account at any time. See the account deletion page.',
          ]}
        />
      </Section>

      <Section id="orders" title="Orders and prices">
        <List
          items={[
            'Product pages show the price in Indian rupees and whether an item is in stock. Delivery and any cash-on-delivery charge are shown at checkout before you pay.',
            'An order is placed when you complete checkout. You receive a confirmation in the app. We may cancel an order if an item turns out to be out of stock, mispriced by mistake, or if we cannot deliver to your address. If that happens we refund anything you have paid.',
            'Product photos and descriptions are as accurate as we can make them. Colours can look different on different screens.',
            'Offers, coupons and wallet or loyalty credit follow the conditions shown with them and cannot be exchanged for cash unless we say so.',
          ]}
        />
      </Section>

      <Section id="payment" title="Payment">
        <p>
          You can pay online through Razorpay, using the methods it offers, or choose cash on delivery where it is available
          for the items in your cart. We do not see or store your card, UPI or bank details. If an online payment is taken
          but the order does not go through, the amount is refunded to you automatically.
        </p>
      </Section>

      <Section id="delivery" title="Delivery, cancellation and returns">
        <List
          items={[
            'We deliver through courier partners to PIN codes they serve. See the Shipping Policy for charges and timings.',
            'You can cancel an order from the app until it has been dispatched. After that it can no longer be cancelled, but you may return it once it is delivered.',
            `You can ask to return or exchange a delivered item within ${LEGAL.returnDays} days of delivery. See the Refund and Returns Policy for how it works.`,
          ]}
        />
      </Section>

      <Section id="content" title="Reviews and what you post">
        <p>
          When you post a review, question, photo or message you confirm that it is yours, truthful and lawful. You allow
          us to display it in the app and website. We may remove content that is abusive, misleading, spam or breaks the law,
          and we may use automated checks to spot fake reviews.
        </p>
      </Section>

      <Section id="use" title="Acceptable use">
        <p>Please do not:</p>
        <List
          items={[
            'use the service for anything unlawful or to harm others;',
            'try to get into other accounts, our systems or our data, or to disrupt the service;',
            'copy or scrape the catalogue, or use it to build a competing service;',
            'place orders you do not intend to accept or pay for, or misuse coupons, refunds or referral offers.',
          ]}
        />
      </Section>

      <Section id="liability" title="Our responsibility">
        <p>
          We take care to run the service well, but it is provided as it is and may sometimes be unavailable. To the extent
          the law allows, we are not responsible for indirect losses, and our total responsibility for any order is limited to
          the amount you paid for it. Nothing in these terms limits your rights under the Consumer Protection Act, 2019 or any
          other law that cannot be limited.
        </p>
      </Section>

      <Section id="law" title="Governing law">
        <p>
          These terms are governed by the laws of India. Disputes will be handled by the courts of competent jurisdiction in
          India. Before going to court, please write to us so that we can try to put things right.
        </p>
      </Section>

      <Section id="changes" title="Changes">
        <p>
          We may change these terms. The date at the top shows the latest version. If a change matters, we will tell you in
          the app or by email. Using the service after a change means you accept it.
        </p>
      </Section>

      <Section id="contact" title="Contact">
        <p>Questions about these terms: {mail}.</p>
      </Section>
    </LegalPage>
  );
}
