/**
 * The single place that decides what the seller link says and where it goes.
 *
 * The navbar, the mobile menu and the footer all show this entry, and each
 * inventing its own copy is how you end up telling an approved seller to
 * "start selling" in one place and "view dashboard" in another.
 */
export function sellerEntry(sellerState) {
  switch (sellerState?.stage) {
    case 'ACTIVE':
      return { label: 'Seller dashboard', href: '/seller', tone: 'active' };
    case 'IN_REVIEW':
      return { label: 'Application in review', href: '/sell', tone: 'pending' };
    case 'APPLYING':
      return { label: 'Finish your application', href: '/sell', tone: 'pending' };
    // NONE, UNKNOWN, or not resolved yet. The invitation is the safe default:
    // it's correct for everyone who hasn't applied, and merely redundant for
    // someone who has — whereas guessing "dashboard" for a shopper sends them
    // to a page they can't use.
    default:
      return { label: 'Sell on BazaarX', href: '/sell', tone: 'neutral' };
  }
}
