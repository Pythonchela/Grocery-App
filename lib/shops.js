/**
 * Shop data as the storefront shows it. Pure functions, so the wording
 * ("Opens tomorrow at 9:00 AM", "20 mins · Min ₹149") is tested on its own.
 */

const DAYS = [
  ['mon', 'Monday'], ['tue', 'Tuesday'], ['wed', 'Wednesday'], ['thu', 'Thursday'],
  ['fri', 'Friday'], ['sat', 'Saturday'], ['sun', 'Sunday'],
];

const text = (v) => {
  const s = v == null ? '' : String(v).trim();
  return s || null;
};

/** "21:00" -> "9:00 PM". */
export function clock(hhmm) {
  const [h = '0', m = '00'] = String(hhmm).split(':');
  const hour = Number(h) || 0;
  const hour12 = hour % 12 === 0 ? 12 : hour % 12;

  return `${hour12}:${m.padStart(2, '0').slice(0, 2)} ${hour < 12 ? 'AM' : 'PM'}`;
}

/** The week as lines to show; empty when the shop is always open (it set no hours). */
export function hoursLines(openingHours) {
  if (!openingHours || typeof openingHours !== 'object' || Object.keys(openingHours).length === 0) return [];

  return DAYS.map(([key, name]) => {
    const slot = openingHours[key];
    const open = slot && text(slot.open);
    const close = slot && text(slot.close);

    return { day: name, hours: open && close ? `${clock(open)} – ${clock(close)}` : 'Closed' };
  });
}

/** What the API sends for a shop, with the fields the pages use under friendly names. */
export function mapShop(s) {
  if (!s) return s;

  return {
    id: String(s.id),
    name: s.name || s.display_name || '',
    slug: s.slug || '',
    logoUrl: text(s.logo_url),
    bannerUrl: text(s.banner_url),
    tagline: text(s.tagline),
    about: text(s.about),
    isHouse: Boolean(s.is_house),
    isOpen: s.is_open !== false,
    closedText: text(s.closed_text),
    minOrder: Number(s.min_order_amount) || 0,
    prepMinutes: Number(s.prep_minutes) > 0 ? Number(s.prep_minutes) : null,
    rating: Number(s.rating) || 0,
    reviewsCount: Number(s.reviews_count) || 0,
    productCount: Number(s.product_count) || 0,
    categories: Array.isArray(s.categories) ? s.categories.map(String) : [],
    hours: hoursLines(s.opening_hours),
    servicePincodes: Array.isArray(s.service_pincodes) ? s.service_pincodes.map(String) : [],
    supportPhone: text(s.support_phone),
  };
}

/** The line under a shop's name: what it wrote about itself, else what it sells. */
export function shopSubtitle(shop) {
  return shop.tagline || shop.categories.join(' · ');
}

/** "20 mins · Min ₹149", whichever parts the shop has. */
export function shopMetaLine(shop, formatMoney) {
  return [
    shop.prepMinutes ? `${shop.prepMinutes} mins` : null,
    shop.minOrder > 0 ? `Min ${formatMoney(shop.minOrder)}` : null,
  ].filter(Boolean).join(' · ');
}
