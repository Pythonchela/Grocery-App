'use client';

import React, { useEffect, useRef } from 'react';
import { ShoppingBasket } from 'lucide-react';
import { useStore } from '../providers/StoreProvider';

/**
 * "Start a new basket?" - shown when someone adds goods from a second shop
 * while the basket still holds the first one's. Baskets hold one shop at a
 * time, so they choose: clear the old basket for this item, or keep it.
 */
export default function ShopSwitchDialog() {
  const { pendingShopSwitch, confirmShopSwitch, cancelShopSwitch } = useStore();
  const keepRef = useRef(null);

  useEffect(() => {
    if (!pendingShopSwitch) return undefined;
    // The safe choice has focus, so Enter cannot empty a basket by accident.
    keepRef.current?.focus();
    const onKey = (e) => { if (e.key === 'Escape') cancelShopSwitch(); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [pendingShopSwitch, cancelShopSwitch]);

  if (!pendingShopSwitch) return null;

  const { product, fromShop } = pendingShopSwitch;
  const toShop = product.soldBy || 'this shop';

  return (
    <div className="fixed inset-0 z-[100] flex items-end sm:items-center justify-center p-4">
      {/* Tapping outside keeps the basket; Esc and the button do the same for the keyboard. */}
      <div aria-hidden="true" className="absolute inset-0 bg-inverse/60 backdrop-blur-sm" onClick={cancelShopSwitch} />
      <div
        role="alertdialog"
        aria-modal="true"
        aria-labelledby="shop-switch-title"
        aria-describedby="shop-switch-body"
        className="relative w-full max-w-sm bg-surface border border-line rounded-panel p-5 space-y-4 shadow-xl"
      >
        <div className="flex items-start gap-3">
          <span className="w-10 h-10 rounded-full bg-accent-soft text-accent flex items-center justify-center shrink-0">
            <ShoppingBasket className="w-5 h-5" />
          </span>
          <div>
            <h2 id="shop-switch-title" className="text-base font-black text-ink">Start a new basket?</h2>
            <p id="shop-switch-body" className="text-sm text-ink-muted font-medium mt-1">
              Your basket has items from <strong className="text-ink">{fromShop}</strong>. To add
              {' '}<strong className="text-ink">{product.title}</strong> from <strong className="text-ink">{toShop}</strong>,
              we will clear it first.
            </p>
          </div>
        </div>

        <div className="flex flex-col-reverse sm:flex-row gap-2">
          <button
            ref={keepRef}
            onClick={cancelShopSwitch}
            className="flex-1 border border-line-strong text-ink text-sm font-bold py-2.5 rounded-control hover:bg-surface-muted transition"
          >
            Keep my basket
          </button>
          <button onClick={confirmShopSwitch} className="flex-1 btn-primary text-sm py-2.5">
            Start new basket
          </button>
        </div>
      </div>
    </div>
  );
}
