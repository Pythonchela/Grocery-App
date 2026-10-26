/**
 * What the storefront knows about the store, as the server states it.
 *
 * This installation is one business selling its own goods, so the answer is
 * always the same; it is read from the server anyway so that the site and the
 * API cannot disagree.
 */

/** What the storefront assumes until the server answers (or if it cannot). */
export const FALLBACK_STORE_CONFIG = {
  mode: 'single',
  vendors_enabled: false,
  house_visible: true,
  shops_first: false,
  shows_shops: false,
  home_shows_shops: false,
  one_shop_per_cart: false,
  store_name: '',
  // Public Google client id for "Continue with Google", set by the owner in Settings.
  google_web_client_id: null,
};

/** Merges what the server sent over the fallback, so a missing key never changes the store by accident. */
export function readStoreConfig(data) {
  return data && typeof data === 'object' ? { ...FALLBACK_STORE_CONFIG, ...data } : FALLBACK_STORE_CONFIG;
}
