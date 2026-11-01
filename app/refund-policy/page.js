import LegalPage, { Section, List } from '../../components/legal/LegalPage';
import { LEGAL } from '../../lib/legal';

export const metadata = {
  title: `Refund and Returns Policy | ${LEGAL.brand}`,
  description: `How to cancel an order, return or exchange an item, and how and when ${LEGAL.brand} refunds you.`,
  alternates: { canonical: '/refund-policy' },
};

const SECTIONS = [
  { id: 'cancel', title: 'Cancelling an order' },
  { id: 'returns', title: 'Returns and exchanges' },
  { id: 'how', title: 'How to ask for a return' },
  { id: 'refunds', title: 'How refunds are paid' },
  { id: 'failed', title: 'Payment taken but no order' },
  { id: 'help', title: 'Need help' },
];

export default function RefundPolicyPage() {
  const days = LEGAL.returnDays;
  const mail = (
    <a href={`mailto:${LEGAL.email}`} className="text-accent font-bold hover:underline">{LEGAL.email}</a>
  );

  return (
    <LegalPage
      title="Refund and Returns Policy"
      updated={LEGAL.policiesUpdated}
      sections={SECTIONS}
      intro={`You can cancel an order before it is dispatched, and return or exchange a delivered item within ${days} days of delivery. This page explains how, and how you get your money back.`}
    >
      <Section id="cancel" title="Cancelling an order">
        <List
          items={[
            'Open Orders in the app, choose the order and tap Cancel. You can cancel until the order has been dispatched.',
            'Once it has been dispatched it can no longer be cancelled. You can return it after it is delivered instead.',
            'If you paid online, we refund the amount you paid for a cancelled order. If you chose cash on delivery, you have nothing to pay.',
            'We may cancel an order ourselves, for example if an item is out of stock. You will be told, and anything you have paid is refunded.',
          ]}
        />
      </Section>

      <Section id="returns" title="Returns and exchanges">
        <List
          items={[
            `Time limit: you can ask within ${days} days of the day the order was delivered.`,
            'You can return an item, or exchange it for another size or variant of the same product where one is available.',
            'Items should be unused and in their original condition and packaging, with tags and accessories. We may refuse a return that is used, damaged by you, or missing parts.',
            'If you received the wrong, damaged or defective item, tell us as soon as you can and add photos. We will arrange the return and refund.',
            'Some items, such as perishable or made-to-order goods, may not be returnable. Where that applies, the product page says so.',
          ]}
        />
      </Section>

      <Section id="how" title="How to ask for a return">
        <ol className="list-decimal pl-5 space-y-2">
          <li>Open Orders in the app, choose the delivered order and the item, and tap Return or Exchange.</li>
          <li>Pick a reason, add a short comment and photos if they help, and choose how you want to be refunded.</li>
          <li>We review the request. If it is approved, we arrange a pickup from your delivery address through our courier partner. You do not need to ship it yourself.</li>
          <li>Hand over the item. After it has been picked up and checked, we send your refund, or the exchange item.</li>
        </ol>
        <p>You can follow the request under Returns in your account. You will get a notification at each step.</p>
      </Section>

      <Section id="refunds" title="How refunds are paid">
        <List
          items={[
            'Refund amount: the price you paid for the returned item after any discount or coupon.',
            'Refund method: when you ask for a return you can choose to be refunded to your original payment method, or to your wallet in the app. Orders paid by cash on delivery are refunded to the wallet.',
            'Wallet refunds are available to spend straight away. Refunds to a card, UPI or bank account usually take 5 to 7 working days to show up, depending on your bank.',
          ]}
        />
      </Section>

      <Section id="failed" title="Payment taken but no order">
        <p>
          If money leaves your account but your order is not created, the amount is returned to you automatically. If you do
          not see it within 7 working days, write to us with the payment reference and we will look into it.
        </p>
      </Section>

      <Section id="help" title="Need help">
        <p>
          Raise a request from Support in your account, or write to {mail}. You can also read our{' '}
          <a href="/shipping-policy" className="text-accent font-bold hover:underline">Shipping Policy</a> and{' '}
          <a href="/terms" className="text-accent font-bold hover:underline">Terms of Service</a>.
        </p>
      </Section>
    </LegalPage>
  );
}
