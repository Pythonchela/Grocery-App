/**
 * Who the policies speak for and how to reach them. One place, so the privacy
 * policy, the account-deletion page and the footer cannot drift apart.
 *
 * Each store sets its own at build time (NEXT_PUBLIC_LEGAL_NAME, NEXT_PUBLIC_LEGAL_SITE,
 * NEXT_PUBLIC_LEGAL_EMAIL); the values after || are used when they are not set.
 */
export const LEGAL = {
  brand: process.env.NEXT_PUBLIC_LEGAL_NAME || 'BazaarX',
  site: process.env.NEXT_PUBLIC_LEGAL_SITE || 'rentalmoney.in',
  email: process.env.NEXT_PUBLIC_LEGAL_EMAIL || 'solutionsintellihive@gmail.com',
  // The date the text last changed. Update it whenever the policy does.
  updated: '27 October 2026',
  // The date the shop policies (terms, returns, shipping, about, contact, FAQs) last changed.
  policiesUpdated: '1 November 2026',
  // Must match RETURN_WINDOW_DAYS in the backend's ReturnController (a test checks it).
  returnDays: 7,
};
