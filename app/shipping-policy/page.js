import LegalPage, { Section, List } from '../../components/legal/LegalPage';
import { LEGAL } from '../../lib/legal';

export const metadata = {
  title: `Shipping Policy | ${LEGAL.brand}`,
  description: `Where ${LEGAL.brand} delivers, what delivery costs, how long it takes and how to track your order.`,
  alternates: { canonical: '/shipping-policy' },
};

const SECTIONS = [
  { id: 'where', title: 'Where we deliver' },
  { id: 'charges', title: 'Delivery charges' },
  { id: 'time', title: 'How long it takes' },
  { id: 'track', title: 'Tracking your order' },
  { id: 'receive', title: 'When it arrives' },
  { id: 'problems', title: 'If something goes wrong' },
];

export default function ShippingPolicyPage() {
  const mail = (
    <a href={`mailto:${LEGAL.email}`} className="text-accent font-bold hover:underline">{LEGAL.email}</a>
  );

  return (
    <LegalPage
      title="Shipping Policy"
      updated={LEGAL.policiesUpdated}
      sections={SECTIONS}
      intro={`${LEGAL.brand} ships through courier partners. The delivery charge and the expected delivery date for your address are always shown at checkout, before you pay.`}
    >
      <Section id="where" title="Where we deliver">
        <p>
          We deliver across India to the PIN codes our courier partners serve. Enter your PIN code on a product page or at
          checkout and the app tells you whether we can deliver there.
        </p>
      </Section>

      <Section id="charges" title="Delivery charges">
        <List
          items={[
            'The delivery charge depends on where you live and the weight of your parcel. It is shown at checkout.',
            'Orders above the free-delivery amount shown in the app, counted after discounts, are delivered free.',
            'Cash on delivery may carry a small extra charge. If it does, it is shown at checkout before you confirm.',
            'The total you see at checkout is the total you pay. There are no charges added at the door.',
          ]}
        />
      </Section>

      <Section id="time" title="How long it takes">
        <p>
          We show an expected delivery date for your PIN code. It depends on the courier and the distance. We pack and hand
          over orders to the courier as soon as we can after they are placed. Delivery can take longer during festivals and
          sales, bad weather, strikes, or other events outside our control. We will tell you if your order is delayed.
        </p>
      </Section>

      <Section id="track" title="Tracking your order">
        <p>
          Open Orders in the app to see where your order is, from confirmed and packed to shipped, out for delivery and
          delivered. You get a notification at each step. Once it has been dispatched you can also see the courier and
          tracking details there.
        </p>
      </Section>

      <Section id="receive" title="When it arrives">
        <List
          items={[
            'Someone should be at the address to receive the parcel. The courier may call you before delivery.',
            'Check the parcel when you get it. If it looks opened or damaged, tell the courier and write to us the same day with photos.',
            'If you chose cash on delivery, please keep the exact amount ready.',
            'If the courier cannot deliver after attempts, the parcel comes back to us. We will contact you to try again or cancel the order and refund anything you paid.',
          ]}
        />
      </Section>

      <Section id="problems" title="If something goes wrong">
        <p>
          If your order is late, lost, damaged or wrong, raise a request from Support in your account or write to {mail}.
          Returns and refunds are explained in our{' '}
          <a href="/refund-policy" className="text-accent font-bold hover:underline">Refund and Returns Policy</a>.
        </p>
      </Section>
    </LegalPage>
  );
}
