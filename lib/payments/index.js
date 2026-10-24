// Collecting payment for a server-issued quote, whichever gateway issued it.
//
// The API says which gateway a quote belongs to (`quote.provider`) and hands
// over that gateway's public settings (`quote.client`). The storefront's only
// job is to run the matching SDK and pass back whatever it returns as
// `payment` — the server verifies it with the same gateway.
//
// To support another gateway: add a handler here. Nothing else in the
// storefront changes.

import { collectRazorpayPayment } from './razorpay';

/** provider key → (quote, opts) => Promise<evidence object> */
const handlers = {
  razorpay: collectRazorpayPayment,
};

/** Providers with nothing to collect: the sandbox, and orders that cost ₹0. */
const NO_COLLECTION = new Set(['mock', 'none']);

/**
 * @returns {Promise<{ payment?: object }>} fields to spread into the checkout body
 */
export async function collectPayment(quote, opts = {}) {
  if (!quote?.provider || NO_COLLECTION.has(quote.provider)) return {};

  const handler = handlers[quote.provider];
  if (!handler) {
    throw new Error('This payment method is not supported in this version of the app. Please refresh and try again.');
  }

  return { payment: await handler(quote, opts) };
}
