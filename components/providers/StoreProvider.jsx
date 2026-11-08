'use client';

import React, { createContext, useContext, useState, useEffect, useCallback } from 'react';
import { apiFetch, getStoredAuth, setStoredAuth, clearStoredAuth } from '../../lib/apiClient';
import {
  cartLineRequest,
  hasRequiredOptions,
  optionUnitPrice,
  picksFromOrderItem,
  selectionProblem,
  selectionSignature,
  selectionSummary,
} from '../../lib/productOptions';
import { FALLBACK_STORE_CONFIG, readStoreConfig } from '../../lib/shopRules';

const StoreContext = createContext();

/** Where a captured `?ref=` code waits between the visit and the signup. */
const REFERRAL_KEY = 'haatvia_referral_code';

/**
 * Reads and clears the stored code in one step.
 *
 * Consumed rather than left in place: a code should attribute the signup it
 * was captured for, not silently reattach itself to some unrelated account
 * created on this browser weeks later.
 */
function consumeStoredReferralCode() {
  try {
    const code = localStorage.getItem(REFERRAL_KEY);
    if (code) localStorage.removeItem(REFERRAL_KEY);
    return code || undefined;
  } catch {
    return undefined;
  }
}

export function StoreProvider({ children }) {
  const [cartItems, setCartItems] = useState([]);
  /**
   * Whether the saved basket has been read back yet. Until it has, the empty
   * starting basket must not be written over it - on a dev double-mount that
   * emptied a shopper's saved basket on every full page load.
   */
  const [cartLoaded, setCartLoaded] = useState(false);
  const [isCartOpen, setIsCartOpen] = useState(false);
  const [isVoiceOpen, setIsVoiceOpen] = useState(false);
  const [authToken, setAuthToken] = useState(null);
  const [authUser, setAuthUser] = useState(null);

  /**
   * What kind of store this is (one business, owner plus vendors, vendors only)
   * and whether a basket holds one shop. Starts as the marketplace default so a
   * slow or failed answer never hides a feature.
   */
  const [storeConfig, setStoreConfig] = useState(FALLBACK_STORE_CONFIG);

  useEffect(() => {
    let cancelled = false;
    apiFetch('/config')
      .then((res) => { if (!cancelled) setStoreConfig(readStoreConfig(res.data)); })
      .catch(() => { /* keep the fallback */ });
    return () => { cancelled = true; };
  }, []);

  // Load from localStorage on mount (if available)
  useEffect(() => {
    try {
      const saved = localStorage.getItem('haatvia_cart');
      if (saved) setCartItems(JSON.parse(saved));
    } catch (e) { /* non-critical: ignore */ }
    setCartLoaded(true);

    const { token, user } = getStoredAuth();
    if (token) { setAuthToken(token); setAuthUser(user); }

    // First-touch referral capture: a shared link's ?ref= is stored the
    // moment it's seen, since the visitor who clicked it usually browses a
    // while before actually signing up — by then the query string is long
    // gone. Never overwritten once set, so the credit always goes to whoever
    // the shopper actually arrived through.
    try {
      const ref = new URLSearchParams(window.location.search).get('ref');
      if (ref && !localStorage.getItem(REFERRAL_KEY)) {
        localStorage.setItem(REFERRAL_KEY, ref);
      }
    } catch (e) { /* non-critical: ignore */ }

    // apiFetch fires this when the API rejects our token.
    const onUnauthorized = () => { setAuthToken(null); setAuthUser(null); };
    window.addEventListener('haatvia:unauthorized', onUnauthorized);
    return () => window.removeEventListener('haatvia:unauthorized', onUnauthorized);
  }, []);

  const login = async (email, password) => {
    const res = await apiFetch('/auth/login', { method: 'POST', body: { email, password } });
    setStoredAuth(res.data.token, res.data.user);
    setAuthToken(res.data.token);
    setAuthUser(res.data.user);
    return res.data.user;
  };

  const register = async (name, email, phone, password) => {
    const res = await apiFetch('/auth/register', {
      method: 'POST',
      body: { name, email, phone, password, referral_code: consumeStoredReferralCode() },
    });
    setStoredAuth(res.data.token, res.data.user);
    setAuthToken(res.data.token);
    setAuthUser(res.data.user);
    return res.data.user;
  };

  const loginWithGoogle = async (idToken) => {
    const res = await apiFetch('/auth/google', {
      method: 'POST',
      body: { id_token: idToken, referral_code: consumeStoredReferralCode() },
    });
    setStoredAuth(res.data.token, res.data.user);
    setAuthToken(res.data.token);
    setAuthUser(res.data.user);
    return res.data.user;
  };

  const logout = async () => {
    // Revoke server-side first, then forget locally. Clearing localStorage
    // alone left the token valid on the API for its full lifetime — a logout
    // that only logs you out of this browser isn't one.
    if (authToken) {
      try {
        await apiFetch('/auth/logout', { method: 'POST', token: authToken });
      } catch {
        // Already expired or revoked — dropping it locally is still correct.
      }
    }

    clearStoredAuth();
    setAuthToken(null);
    setAuthUser(null);
  };

  /** Keep the cached user in sync after a profile edit. */
  const updateAuthUser = (user) => {
    setAuthUser(user);
    if (authToken) setStoredAuth(authToken, user);
  };

  // Save to localStorage when changed
  useEffect(() => {
    if (!cartLoaded) return;
    try {
      localStorage.setItem('haatvia_cart', JSON.stringify(cartItems));
    } catch (e) { /* non-critical: ignore */ }
  }, [cartItems, cartLoaded]);

  /**
   * `selection` is what the shopper picked on the product page (portion,
   * add-ons, weight...). A product with a choice they must make can't be added
   * from a card or a list - those send them to the product page instead.
   */
  const handleAddToCart = (product, variant = null, selection = null) => {
    const groups = product.optionGroups || [];

    if (hasRequiredOptions(groups) && !selection) {
      if (typeof window !== 'undefined') window.location.assign(`/product/${product.id}`);
      return;
    }
    if (selectionProblem(groups, selection || {})) return;

    addLine(product, variant, selection);
  };

  /** Puts the line in the basket. */
  const addLine = (product, variant, selection) => {
    const groups = product.optionGroups || [];
    const options = selection || {};

    const signature = selectionSignature(options);
    const unitPrice = signature
      ? optionUnitPrice(variant?.price ?? product.price, groups, options)
      : variant?.price ?? product.price;

    setCartItems((prev) => {
      const base = variant ? `${product.id}-${variant.id}` : product.id;
      // The same dish with different picks is a different line.
      const cartItemId = signature ? `${base}~${signature}` : base;
      const existing = prev.find((item) => item.cartItemId === cartItemId);
      if (existing) {
        return prev.map((item) =>
          item.cartItemId === cartItemId ? { ...item, quantity: item.quantity + 1 } : item
        );
      }
      return [...prev, {
        ...product,
        cartItemId,
        variantId: variant?.id,
        variantName: variant ? [variant.color, variant.size].filter(Boolean).join(' - ') : null,
        options,
        optionPicks: selectionSummary(groups, options),
        price: unitPrice,
        mrp: signature && product.price > 0 ? Math.max(unitPrice, product.mrp * (unitPrice / product.price)) : product.mrp,
        quantity: 1
      }];
    });
    setIsCartOpen(true);
  };

  const handleUpdateQty = (cartItemId, newQty) => {
    if (newQty <= 0) {
      setCartItems((prev) => prev.filter((item) => item.cartItemId !== cartItemId));
    } else {
      setCartItems((prev) =>
        prev.map((item) => (item.cartItemId === cartItemId ? { ...item, quantity: newQty } : item))
      );
    }
  };

  const handleRemoveItem = (cartItemId) => {
    setCartItems((prev) => prev.filter((item) => item.cartItemId !== cartItemId));
  };

  const clearCart = () => setCartItems([]);

  /**
   * Reconcile the cart against live prices and stock.
   *
   * Each cart line is a snapshot of the product as it was when it was added,
   * price included, and it persists in localStorage indefinitely. Without this
   * a shopper can sit on a week-old cart showing a price the store no longer
   * offers, then watch the total change at checkout — which reads as a bait and
   * switch even though checkout was the honest number all along.
   */
  const revalidateCart = async (items) => {
    if (!items.length) return;

    try {
      const res = await apiFetch('/cart/price', {
        method: 'POST',
        body: { items: items.map(cartLineRequest) },
      });

      // The report comes back in the order the lines were sent, which is what
      // tells apart the same dish ordered two ways.
      const rows = res.data?.items || [];
      const rowFor = new Map(items.map((item, i) => [item.cartItemId, rows[i]]));

      setCartItems(prev => prev.map(item => {
        const row = rowFor.get(item.cartItemId);
        if (!row) return item;

        return {
          ...item,
          // The old price is kept alongside the new one so the cart can say
          // "was ₹1,299" rather than silently changing the number.
          previousPrice: row.unit_price !== null && row.unit_price !== item.price
            ? item.price
            : undefined,
          price: row.unit_price ?? item.price,
          mrp: row.unit_mrp ?? item.mrp,
          optionPicks: row.options?.length ? picksFromOrderItem(row.options) : item.optionPicks,
          unavailable: !row.available,
          stockNotice: row.reason || null,
        };
      }));
    } catch {
      // Offline or API down: the cart still works from its snapshot, and
      // checkout re-prices authoritatively regardless.
    }
  };

  // Re-check whenever the drawer opens. That's the moment the numbers are about
  // to be read, and it keeps the check off the hot path of every page load.
  useEffect(() => {
    if (isCartOpen) revalidateCart(cartItems);
  }, [isCartOpen]);

  const cartCount = cartItems.reduce((acc, i) => acc + i.quantity, 0);

  return (
    <StoreContext.Provider
      value={{
        cartItems,
        cartCount,
        isCartOpen,
        setIsCartOpen,
        isVoiceOpen,
        setIsVoiceOpen,
        handleAddToCart,
        storeConfig,
        handleUpdateQty,
        handleRemoveItem,
        clearCart,
        authToken,
        authUser,
        login,
        register,
        loginWithGoogle,
        logout,
        updateAuthUser,
      }}
    >
      {children}
    </StoreContext.Provider>
  );
}

export function useStore() {
  return useContext(StoreContext);
}
