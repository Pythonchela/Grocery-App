import LegalPage, { Section, Faq } from '../../components/legal/LegalPage';
import { LEGAL } from '../../lib/legal';

export const metadata = {
  title: `FAQs | ${LEGAL.brand}`,
  description: `Answers to common questions about ordering, payment, delivery, returns and your account at ${LEGAL.brand}.`,
  alternates: { canonical: '/faqs' },
};

const days = LEGAL.returnDays;

const GROUPS = [
  {
    id: 'ordering',
    title: 'Ordering and payment',
    items: [
      ['How do I place an order?', 'Add items to your cart, choose your delivery address and a payment method, and confirm. You will see a confirmation, and the order appears under Orders.'],
      ['How can I pay?', 'Online through Razorpay (cards, UPI and other methods it offers), or cash on delivery where it is available for the items in your cart.'],
      ['Is it safe to pay online?', 'Yes. Payment happens on Razorpay\'s secure screen. We never see or store your card, UPI or bank details.'],
      ['My payment was taken but I have no order. What now?', 'The amount is returned to you automatically. If you do not see it within 7 working days, write to us with the payment reference.'],
      ['Can I use a coupon, my wallet or loyalty points?', 'Yes, where your account has them. Apply a coupon at checkout. Wallet credit and points are shown there too.'],
    ],
  },
  {
    id: 'delivery',
    title: 'Delivery',
    items: [
      ['Do you deliver to my PIN code?', 'Enter your PIN code on a product page or at checkout. The app tells you whether we deliver there and when to expect the order.'],
      ['How much is delivery?', 'It is shown at checkout before you pay, based on your PIN code and the weight of the parcel. Orders above the free-delivery amount shown in the app are delivered free.'],
      ['How do I track my order?', 'Open Orders and choose the order. You can see each step and, once it is dispatched, the courier details. You also get notifications.'],
      ['What if I am not home?', 'The courier may call you and try again. If delivery fails, the parcel comes back to us and we will contact you.'],
    ],
  },
  {
    id: 'returns',
    title: 'Cancelling, returns and refunds',
    items: [
      ['Can I cancel my order?', 'Yes, from Orders until it has been dispatched. After that it cannot be cancelled, but you can return it once delivered.'],
      ['How long do I have to return something?', `${days} days from the day it is delivered.`],
      ['How do I return or exchange an item?', 'Open Orders, choose the delivered item and tap Return or Exchange. If we approve it, we collect it from your address.'],
      ['How will I get my refund?', 'Back to your original payment method or to your wallet, as you choose when you ask for the return. Orders paid by cash on delivery are refunded to your wallet. Card, UPI and bank refunds usually take 5 to 7 working days.'],
    ],
  },
  {
    id: 'account',
    title: 'Your account',
    items: [
      ['How do I sign in?', 'With your email and password, a one-time code sent to your phone, or your Google account, where these are offered.'],
      ['I forgot my password.', 'Sign in with a one-time code or with Google instead, where those are offered, or write to us and we will help you get back into your account.'],
      ['How do I delete my account?', 'Follow the steps on the account deletion page. We act on your request within 30 days.'],
      ['Who can see my details?', 'Only the people who need them to deliver your order, such as the courier. We never sell your information. See the Privacy Policy.'],
    ],
  },
];

export default function FaqsPage() {
  return (
    <LegalPage
      title="Frequently asked questions"
      updated={LEGAL.policiesUpdated}
      sections={GROUPS.map(({ id, title }) => ({ id, title }))}
      intro="Quick answers about ordering, delivery, returns and your account. Can't find yours? See the contact page."
    >
      {GROUPS.map((group) => (
        <Section key={group.id} id={group.id} title={group.title}>
          <Faq items={group.items} />
        </Section>
      ))}
    </LegalPage>
  );
}
