import LegalPage, { Section, List } from '../../components/legal/LegalPage';
import { LEGAL } from '../../lib/legal';

export const metadata = {
  title: `About ${LEGAL.brand}`,
  description: `About ${LEGAL.brand}: who we are, how shopping works and how to reach us.`,
  alternates: { canonical: '/about' },
};

export default function AboutPage() {
  const mail = (
    <a href={`mailto:${LEGAL.email}`} className="text-accent font-bold hover:underline">{LEGAL.email}</a>
  );

  return (
    <LegalPage
      title={`About ${LEGAL.brand}`}
      updated={LEGAL.policiesUpdated}
      intro={`${LEGAL.brand} is an online shop. You can browse the range, order from your phone or the website, and have it delivered to your door anywhere our couriers reach.`}
    >
      <Section id="shopping" title="How shopping works">
        <List
          items={[
            'Browse by category or search, and check delivery to your PIN code before you buy.',
            'Pay online or, where it is offered, by cash on delivery.',
            'Follow your order from confirmed to delivered in the Orders tab, with notifications on the way.',
            `If something is not right, return or exchange it within ${LEGAL.returnDays} days of delivery.`,
          ]}
        />
      </Section>

      <Section id="promise" title="What we promise">
        <List
          items={[
            'Clear prices: the total you see at checkout is the total you pay.',
            'Honest product information, and refunds when we cannot deliver what you ordered.',
            'Help when you need it, from Support in your account or by email.',
            'Your information stays private. We never sell it. See our Privacy Policy.',
          ]}
        />
      </Section>

      <Section id="policies" title="Our policies">
        <ul className="space-y-1.5">
          {[
            ['/terms', 'Terms of Service'],
            ['/refund-policy', 'Refund and Returns Policy'],
            ['/shipping-policy', 'Shipping Policy'],
            ['/privacy', 'Privacy Policy'],
            ['/faqs', 'Frequently asked questions'],
          ].map(([href, label]) => (
            <li key={href}><a href={href} className="text-accent font-bold hover:underline">{label}</a></li>
          ))}
        </ul>
      </Section>

      <Section id="reach" title="Get in touch">
        <p>
          Write to {mail}, or see the <a href="/contact" className="text-accent font-bold hover:underline">contact page</a> for
          everything on how to reach us.
        </p>
      </Section>
    </LegalPage>
  );
}
