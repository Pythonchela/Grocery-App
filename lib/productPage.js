/**
 * The product page's small decisions, kept out of the component so they can be
 * tested. Each mirrors what the phone app does on its product screen
 * (`product_detail_screen.dart`, `cart_delivery.dart`, `product_delivery_card.dart`).
 */

/** The variant the page opens on: the first one in stock, else the first. */
export function openingVariant(variants = []) {
  return variants.find((v) => v.stock > 0) || variants[0] || null;
}

/** What the gallery shows: the chosen colour's own pictures, else the product's. */
export function galleryImages(product, variant) {
  return variant?.images?.length ? variant.images : product.images || [];
}

/** The first picture of a colour, when the store gave that colour any. */
export function colourPhoto(variants = [], colour) {
  for (const v of variants) {
    if (v.color === colour && v.images?.length) return v.images[0];
  }
  return null;
}

/** "Excellent", "Very good"... the word beside the average rating. */
export function ratingWord(rating) {
  if (rating >= 4.5) return 'Excellent';
  if (rating >= 4) return 'Very good';
  if (rating >= 3) return 'Good';
  if (rating >= 2) return 'Fair';
  return 'Poor';
}

/** The small promises under the price: returns, payment, speed. */
export function assurances(product, returnDays = 7) {
  const items = [
    { icon: 'return', label: `${returnDays}-day return` },
    product.codAvailable
      ? { icon: 'cash', label: 'Cash on delivery' }
      : { icon: 'card', label: 'Prepaid only' },
  ];
  if (product.deliveryProfile === 'instant') items.push({ icon: 'bolt', label: 'Quick delivery' });
  return items;
}

/** "25 mins", "1 hr 30 mins", "3 hrs"; the server's own wording for a day or more. */
export function etaHeadline(option) {
  const m = option.eta_minutes;
  if (m > 0 && m < 90) return `${m} mins`;
  if (m >= 90 && m < 60 * 24) {
    const h = Math.floor(m / 60);
    const r = m % 60;
    const hrs = (n) => (n === 1 ? '1 hr' : `${n} hrs`);
    if (r < 10) return hrs(h);
    if (r >= 50) return hrs(h + 1);
    return `${hrs(h)} ${r} mins`;
  }
  return option.eta_label;
}

const DATE = new Intl.DateTimeFormat('en-IN', { weekday: 'short', day: 'numeric', month: 'short' });

/**
 * When it arrives, worded to read right at every speed: "Delivery in 25 mins",
 * "Delivery tomorrow", "Delivery by Fri, 16 Oct". A day or more becomes a date.
 * Returns `{ lead, when }` so the date can be shown in bold.
 */
export function etaPhrase(option, now = new Date()) {
  const m = option.eta_minutes;
  if (!(m > 0)) return { lead: 'Delivery', when: option.eta_label || '' };
  if (m < 60 * 24) return { lead: 'Delivery in', when: etaHeadline(option) };

  const arrives = new Date(now.getTime() + m * 60000);
  const tomorrow = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1);
  const sameDay = (a, b) =>
    a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
  if (sameDay(arrives, tomorrow)) return { lead: 'Delivery', when: 'tomorrow' };
  return { lead: 'Delivery by', when: DATE.format(arrives).replace(',', '') };
}

/** The fastest of the delivery options a quote offers. */
export function fastestOption(options = []) {
  if (!options.length) return null;
  return options.reduce((a, b) => (a.eta_minutes <= b.eta_minutes ? a : b));
}

/** What to say about delivery when there is no PIN code to quote for. */
export function generalDelivery(product, freeAbove = 1999) {
  const free = `₹${Number(freeAbove).toLocaleString('en-IN')}`;
  switch (product.deliveryProfile) {
    case 'instant':
      return Number(product.prepMinutes) > 0
        ? `Quick local delivery · ready in about ${product.prepMinutes} mins`
        : 'Quick local delivery from the store';
    case 'heavy':
      return 'Delivered by truck in a booked slot';
    case 'parcel':
      return `Courier delivery · free above ${free} · track every step`;
    default:
      return `Free delivery above ${free}`;
  }
}

/** A bundle's other product, given the one being viewed. */
export function bundlePartner(bundle, productId) {
  const [first, second] = bundle.products || [];
  return first?.id === productId ? second : first;
}

/** Whether a bundle payload is a complete two-product deal worth showing. */
export function usableBundle(bundle, productId) {
  const products = bundle?.products;
  return Array.isArray(products) && products.length === 2 && products.some((p) => p.id === productId);
}
