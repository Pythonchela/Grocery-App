'use client';

import React, { useEffect, useState } from 'react';
import Link from 'next/link';
import { Plus, ShoppingBag, Tag } from 'lucide-react';
import { useStore } from '../providers/StoreProvider';
import { apiFetch, mapProduct } from '../../lib/apiClient';
import { hasRequiredOptions } from '../../lib/productOptions';
import { bundlePartner, openingVariant, usableBundle } from '../../lib/productPage';

/** Whole rupees without decimals, otherwise two: "₹10,998" and "₹9,348.30". */
const formatINR = (n) =>
  `₹${Number(n).toLocaleString('en-IN', {
    minimumFractionDigits: Number.isInteger(Number(n)) ? 0 : 2,
    maximumFractionDigits: 2,
  })}`;

function Thumb({ product }) {
  return (
    <div className="flex-1 min-w-0 text-center">
      <Link href={`/product/${product.id}`} className="block">
        <div className="aspect-square rounded-card overflow-hidden bg-surface-sunken border border-line">
          <img src={product.image} alt="" className="w-full h-full object-cover" />
        </div>
        <p className="mt-2 text-xs font-semibold text-ink line-clamp-2">{product.title}</p>
      </Link>
    </div>
  );
}

/**
 * "Buy together & save": live two-product deals that feature this product.
 * Display only - the server applies the saving when it prices the basket, so
 * adding both items is all this has to do.
 */
export default function BundleOffer({ product, addCurrent }) {
  const { handleAddToCart } = useStore();
  const [deals, setDeals] = useState([]);
  const [note, setNote] = useState('');

  useEffect(() => {
    let cancelled = false;
    apiFetch(`/deals/bundles?product_id=${product.id}`)
      .then((res) => {
        if (cancelled) return;
        setDeals((res.data || []).filter((d) => usableBundle(d, product.id)));
      })
      .catch(() => { /* supplementary: the page stands without it */ });
    return () => { cancelled = true; };
  }, [product.id]);

  if (!deals.length) return null;

  const addBoth = (deal, partner) => {
    const inStock = (partner.variants || []).filter((v) => v.stock > 0);
    // Several options, or a choice to make: the partner's own page is where that happens.
    if (inStock.length > 1 || hasRequiredOptions(partner.optionGroups || [])) {
      window.location.assign(`/product/${partner.id}`);
      return;
    }
    // This product first, with whatever the shopper has picked above; if that
    // is incomplete the page says why and nothing is added.
    if (!addCurrent()) return;
    handleAddToCart(partner, inStock[0] || openingVariant(partner.variants));
    setNote(`Bundle added - you save ${formatINR(deal.savings)}.`);
  };

  return (
    <div className="space-y-3">
      {deals.map((deal) => {
        const partner = mapProduct(bundlePartner(deal, product.id));
        const current = deal.products.find((p) => p.id === product.id);
        const canBuy = (current?.in_stock ?? true) && partner.inStock;
        return (
          <div key={deal.id} className="rounded-card border border-line bg-surface p-4">
            <div className="flex items-center gap-2">
              <Tag className="w-4 h-4 text-accent" />
              <h3 className="flex-1 text-base font-black text-ink">Buy together &amp; save</h3>
              <span className="text-xs font-black text-success bg-success-soft rounded-pill px-2.5 py-1">
                Save {formatINR(deal.savings)}
              </span>
            </div>
            {deal.name && <p className="text-sm text-ink-muted mt-0.5">{deal.name}</p>}

            <div className="mt-3 flex items-start gap-3">
              <Thumb product={mapProduct(current || product)} />
              <Plus className="w-5 h-5 text-ink-subtle mt-8 shrink-0" />
              <Thumb product={partner} />
            </div>

            <div className="mt-3 flex items-end gap-2">
              <span className="text-xl font-black text-ink">{formatINR(deal.bundle_price)}</span>
              <span className="text-sm text-ink-subtle line-through mb-0.5">{formatINR(deal.compare_at_price)}</span>
              <button
                type="button"
                disabled={!canBuy}
                onClick={() => addBoth(deal, partner)}
                className="ml-auto inline-flex items-center gap-1.5 bg-primary text-on-primary px-4 py-2 rounded-control text-sm font-bold disabled:opacity-50"
              >
                <ShoppingBag className="w-4 h-4" /> {canBuy ? 'Add both' : 'Unavailable'}
              </button>
            </div>
          </div>
        );
      })}
      {note && <p role="status" className="text-xs font-semibold text-ink-muted">{note}</p>}
    </div>
  );
}
