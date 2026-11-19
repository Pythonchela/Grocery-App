'use client';

import React, { useState } from 'react';
import Link from 'next/link';
import { Clock, Heart, Minus, Plus } from 'lucide-react';
import { useStore } from './providers/StoreProvider';
import { apiFetch } from '../lib/apiClient';
import { hasRequiredOptions } from '../lib/productOptions';
import DietMark from './DietMark';

/** "500 g": the pack size, when the product has exactly one and it says something. */
export function unitOf(product) {
  const variants = product.variants || [];
  if (variants.length === 1) {
    const size = (variants[0].size || '').trim();
    return size && !/^(standard|free size)$/i.test(size) ? size : null;
  }
  return variants.length > 1 ? `${variants.length} options` : null;
}

/**
 * The tile every list in the food and grocery store shares. A square picture with the ADD button
 * sitting on its lower corner (so adding is one tap, without opening the product), then how soon it
 * is ready, the name, the pack size and the price. It turns into "- 2 +" once it is in the basket.
 */
export default function ProductCard({ product, onAddToCart }) {
  const { authToken, handleAddToCart, handleUpdateQty, cartItems } = useStore();
  const [wishlisted, setWishlisted] = useState(false);
  const [busy, setBusy] = useState(false);

  // Cards are rendered from places that pass no handler (e.g. "Related products").
  const addToCart = onAddToCart || handleAddToCart;
  const inStock = product.inStock !== false;
  const variants = product.variants || [];
  // A choice the shopper must make (pack size, portion) is made on the product page: adding the
  // product with no choice would put an arbitrary one in the basket.
  const needsChoice = variants.length > 1 || hasRequiredOptions(product.optionGroups || []);

  const lines = cartItems.filter((i) => i.id === product.id);
  const inCart = lines.reduce((n, i) => n + i.quantity, 0);
  const last = lines[lines.length - 1];
  const unit = unitOf(product);
  const ready = Number(product.deliveryInfo?.prep_minutes) || Number(product.prepMinutes) || 0;
  const href = `/product/${product.id}`;

  const toggleWishlist = async (e) => {
    e.preventDefault();
    e.stopPropagation();
    if (!authToken) { window.location.href = '/account/wishlist'; return; }
    setBusy(true);
    try {
      await apiFetch('/wishlist-items', { method: 'POST', token: authToken, body: { product_id: product.id } });
      setWishlisted(true);
    } finally {
      setBusy(false);
    }
  };

  const add = (e) => {
    e.preventDefault();
    e.stopPropagation();
    if (needsChoice) { window.location.assign(href); return; }
    addToCart(product, variants[0] || null);
  };

  return (
    <div className="group relative flex h-full flex-col rounded-card border border-line bg-surface p-2.5">
      <div className="relative">
        <Link href={href} className="block aspect-square overflow-hidden rounded-control bg-surface-sunken">
          <img src={product.image} alt={product.title} loading="lazy" className="h-full w-full object-cover transition duration-300 group-hover:scale-105" />
        </Link>

        {product.discount > 0 && inStock && (
          <span className="absolute left-0 top-0 rounded-br-chip rounded-tl-control bg-accent px-1.5 py-0.5 text-2xs font-black text-on-accent">
            {product.discount}% OFF
          </span>
        )}
        {!inStock && (
          <span className="absolute inset-0 flex items-center justify-center rounded-control bg-surface/60 text-xs font-black text-ink">Sold out</span>
        )}

        <button
          type="button"
          onClick={toggleWishlist}
          disabled={busy}
          aria-label={wishlisted ? 'Saved to wishlist' : 'Add to wishlist'}
          className={`absolute right-1.5 top-1.5 flex h-7 w-7 items-center justify-center rounded-pill shadow-subtle transition disabled:opacity-50 ${
            wishlisted ? 'bg-danger text-ink-inverse' : 'bg-surface/90 text-ink-muted hover:text-danger'
          }`}
        >
          <Heart className={`h-3.5 w-3.5 ${wishlisted ? 'fill-current' : ''}`} />
        </button>

        {inStock && (
          <div className="absolute -bottom-4 right-1.5">
            {inCart === 0 ? (
              <button
                type="button"
                onClick={add}
                className="rounded-control border border-accent bg-surface px-5 py-1.5 text-sm font-black text-accent shadow-card transition hover:bg-accent-soft"
              >
                ADD
                {needsChoice && <span className="block text-2xs font-semibold leading-none text-ink-subtle">options</span>}
              </button>
            ) : (
              <div className="flex items-center overflow-hidden rounded-control bg-accent text-on-accent shadow-card">
                <button type="button" aria-label="Remove one" onClick={(e) => { e.preventDefault(); handleUpdateQty(last.cartItemId, last.quantity - 1); }} className="p-2 hover:bg-accent-hover">
                  <Minus className="h-3.5 w-3.5" />
                </button>
                <span className="min-w-6 text-center text-sm font-black">{inCart}</span>
                <button
                  type="button"
                  aria-label="Add one more"
                  onClick={(e) => { e.preventDefault(); if (needsChoice) window.location.assign(href); else handleUpdateQty(last.cartItemId, last.quantity + 1); }}
                  className="p-2 hover:bg-accent-hover"
                >
                  <Plus className="h-3.5 w-3.5" />
                </button>
              </div>
            )}
          </div>
        )}
      </div>

      <div className="mt-6 flex flex-1 flex-col">
        {ready > 0 && (
          <p className="mb-0.5 flex items-center gap-1 text-2xs font-black uppercase tracking-wide text-ink-subtle">
            <Clock className="h-3 w-3" /> {ready} min
          </p>
        )}
        <Link href={href} className="flex items-start gap-1.5 text-sm font-semibold leading-snug text-ink">
          <DietMark diet={product.diet} size="sm" />
          <span className="line-clamp-2">{product.title}</span>
        </Link>
        {unit && <p className="mt-0.5 text-xs font-medium text-ink-subtle">{unit}</p>}
        <p className="mt-auto flex items-baseline gap-1.5 pt-2">
          <span className="text-base font-black text-ink">₹{product.price.toLocaleString('en-IN')}</span>
          {product.mrp > product.price && <span className="text-xs font-medium text-ink-subtle line-through">₹{product.mrp.toLocaleString('en-IN')}</span>}
        </p>
      </div>
    </div>
  );
}
