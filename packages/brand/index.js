/**
 * packages/brand — brand identity, keyed by brand id.
 *
 * The previous lib/brandConfig.js was a single frozen object, so "spin up a
 * second app with different branding" meant editing the file the first app
 * depends on. Making this a map is the whole difference: a new storefront,
 * a seller portal or a white-label tenant registers an entry here and every
 * component in packages/ui and packages/commerce-ui renders it unchanged.
 *
 * Colour does NOT live here — that is packages/tokens. This file is names,
 * words, legal text and destinations only.
 */

/** Fields every brand must supply. Anything omitted falls back to `base`. */
const base = {
  id: 'base',

  // Identity
  name: 'Haatvia',
  nameUpper: 'HAATVIA',
  nameDisplay: 'HAAT', // logo text before the accent part
  nameAccent: 'VIA', // rendered in the accent colour
  logoInitials: 'HV',
  tagline: 'SHOP ONLINE',
  editionLabel: "Spring '26 Edition",
  appStoreName: 'Haatvia App Store',
  devDomain: 'Haatvia.dev',

  // Legal & contact
  legalEntity: 'Haatvia',
  domain: 'rentalmoney.in',
  supportEmail: 'solutionsintellihive@gmail.com',
  grievanceOfficer: 'Grievance Officer, Haatvia',

  // Product surface names
  walletName: 'Haatvia Wallet',
  loyaltyName: 'Haatvia Points',
  responseLabel: 'Haatvia Response', // shown above an admin reply to a review

  // Storage key prefix. Namespaced per brand so two brands served from the same
  // origin can't read each other's session.
  storageNamespace: 'haatvia',

  // Currency & locale
  currency: 'INR',
  currencySymbol: '₹',
  locale: 'en-IN',

  // Footer / legal navigation. Real hrefs — the previous footer rendered these
  // as <span> elements with cursor-pointer and no destination.
  footerLinks: [
    { label: 'Privacy Policy', href: '/legal/privacy' },
    { label: 'Terms of Service', href: '/legal/terms' },
    { label: 'Returns & Refunds', href: '/legal/returns' },
    { label: 'Contact Us', href: '/legal/contact' },
  ],
};

/** Registered brands. Add an entry to launch a differently-branded app. */
const brands = {
  haatvia: { ...base, id: 'haatvia' },
};

/**
 * Resolve a brand by id, falling back to the default.
 * Set NEXT_PUBLIC_BRAND to switch a deployment without a code change.
 */
export function getBrand(id = process.env.NEXT_PUBLIC_BRAND || 'haatvia') {
  return brands[id] || brands.haatvia;
}

export const brand = getBrand();

/** SEO metadata derived from whichever brand is active. */
export function getSeo(b = brand) {
  return {
    title: `${b.name} | Online Shop`,
    description:
      'Shop authentic Indian ethnic wear, electronics, footwear and artisanal decor with instant UPI payments, video reels, vernacular voice search and verified reviews.',
    keywords: `${b.name}, Indian marketplace, B2C shopping India, UPI checkout, verified reviews`,
    og: {
      title: `${b.name} | Online Shop`,
      description: 'Video-first shopping and express delivery across India.',
      url: `https://${b.domain}`,
      siteName: b.name,
      imageAlt: `${b.name} online shop`,
    },
  };
}

export const seo = getSeo();

/** Namespaced localStorage keys, so brands never collide on a shared origin. */
export function storageKey(name, b = brand) {
  return `${b.storageNamespace}_${name}`;
}

export default brand;
