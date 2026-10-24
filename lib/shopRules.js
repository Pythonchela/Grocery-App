/**
 * What kind of store this is, and the one-shop-per-basket rule that goes with it.
 *
 * Kept free of React so the rule can be tested on its own and the cart, the
 * product page and the shop page all ask the same question the same way.
 */

/** What the storefront assumes until the server answers (or if it cannot). */
export const FALLBACK_STORE_CONFIG = {
  mode: 'hybrid',
  vendors_enabled: true,
  house_visible: true,
  shops_first: false,
  shows_shops: true,
  // Whether the home page carries a row of shops among its products.
  home_shows_shops: true,
  one_shop_per_cart: true,
  store_name: '',
};

/** Merges what the server sent over the fallback, so a missing key never hides a feature by accident. */
export function readStoreConfig(data) {
  return data && typeof data === 'object' ? { ...FALLBACK_STORE_CONFIG, ...data } : FALLBACK_STORE_CONFIG;
}

/** The shop whose goods are in the basket, or null when it has none (or none say which shop). */
export function cartShop(cart) {
  const line = (cart || []).find((item) => item.shopId);
  return line ? { id: line.shopId, name: line.soldBy || null } : null;
}

/**
 * When the store keeps a basket to one shop: the name of the shop already in the
 * basket if `product` is from a different one, otherwise null. The caller then
 * asks the shopper whether to start a new basket.
 *
 * Goods that do not say which shop they are from never conflict.
 */
export function shopConflict(cart, product, config) {
  if (!config?.one_shop_per_cart || !cart?.length) return null;

  const inBasket = cartShop(cart);
  const incoming = product?.shopId;
  if (!inBasket || !incoming || inBasket.id === incoming) return null;

  return inBasket.name || 'another shop';
}

/** Whether the store offers a way to apply as a seller at all: not in a single-business store. */
export function offersSelling(config) {
  return config ? config.vendors_enabled !== false : true;
}
