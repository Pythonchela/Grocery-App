'use client';

import React, { useMemo, useState } from 'react';
import Link from 'next/link';
import { ChevronLeft, Clock, MapPin, Phone, Star, Store } from 'lucide-react';
import ProductCard from '../ProductCard';
import { useStore } from '../providers/StoreProvider';
import { formatINR } from '../../lib/apiClient';
import { shopMetaLine, shopSubtitle } from '../../lib/shops';

/**
 * One shop: who it is, whether it is open, what it sells. The category chips
 * are whatever this shop's own goods are filed under.
 */
export default function ShopClient({ shop, products }) {
  const { handleAddToCart, storeConfig } = useStore();
  const [category, setCategory] = useState('');
  const [showHours, setShowHours] = useState(false);

  const categories = useMemo(() => {
    const seen = new Map();
    products.forEach((p) => { if (p.categorySlug && !seen.has(p.categorySlug)) seen.set(p.categorySlug, p.category); });
    return [...seen].map(([slug, name]) => ({ slug, name }));
  }, [products]);

  const visible = category ? products.filter((p) => p.categorySlug === category) : products;
  const meta = shopMetaLine(shop, formatINR);

  const chip = (selected) =>
    `px-3.5 py-1.5 rounded-pill border text-xs font-bold whitespace-nowrap transition ${
      selected ? 'bg-inverse text-ink-inverse border-inverse' : 'bg-surface text-ink-muted border-line hover:border-line-strong'
    }`;

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6 space-y-5">
      {storeConfig.shows_shops && (
        <Link href="/shops" className="inline-flex items-center gap-1 text-xs font-bold text-ink-muted hover:text-ink">
          <ChevronLeft className="w-4 h-4" /> All shops
        </Link>
      )}

      <section className="bg-surface border border-line rounded-panel overflow-hidden">
        <div className="h-36 sm:h-48 bg-surface-muted">
          {shop.bannerUrl && <img src={shop.bannerUrl} alt="" className="w-full h-full object-cover" />}
        </div>

        <div className="p-5 flex flex-col sm:flex-row gap-4">
          <div className="w-16 h-16 -mt-14 sm:-mt-12 rounded-panel border-4 border-surface bg-surface-muted overflow-hidden shrink-0 flex items-center justify-center">
            {shop.logoUrl ? <img src={shop.logoUrl} alt="" className="w-full h-full object-cover" /> : <Store className="w-7 h-7 text-ink-subtle" />}
          </div>

          <div className="flex-1 min-w-0 space-y-1.5">
            <div className="flex items-start justify-between gap-3">
              <h1 className="text-xl font-black text-ink">{shop.name}</h1>
              {shop.rating > 0 && (
                <span className="inline-flex items-center gap-1 bg-success-soft text-success text-xs font-black px-2 py-1 rounded-control shrink-0">
                  {shop.rating.toFixed(1)} <Star className="w-3 h-3 fill-current" />
                  <span className="font-semibold text-ink-subtle">({shop.reviewsCount})</span>
                </span>
              )}
            </div>
            {shopSubtitle(shop) && <p className="text-sm text-ink-muted font-medium">{shopSubtitle(shop)}</p>}
            {meta && <p className="text-xs text-ink-subtle font-semibold">{meta}</p>}
            {shop.about && <p className="text-sm text-ink-muted font-medium pt-1">{shop.about}</p>}

            <div className="flex flex-wrap items-center gap-x-4 gap-y-1 pt-1 text-xs font-semibold text-ink-muted">
              {shop.hours.length > 0 && (
                <button onClick={() => setShowHours((v) => !v)} aria-expanded={showHours} className="inline-flex items-center gap-1 hover:text-ink">
                  <Clock className="w-3.5 h-3.5" /> Opening hours
                </button>
              )}
              {shop.servicePincodes.length > 0 && (
                <span className="inline-flex items-center gap-1"><MapPin className="w-3.5 h-3.5" /> Delivers to {shop.servicePincodes.length} PIN codes</span>
              )}
              {shop.supportPhone && (
                <a href={`tel:${shop.supportPhone}`} className="inline-flex items-center gap-1 hover:text-ink"><Phone className="w-3.5 h-3.5" /> {shop.supportPhone}</a>
              )}
            </div>

            {showHours && (
              <dl className="grid grid-cols-[auto_1fr] gap-x-6 gap-y-0.5 pt-2 text-xs max-w-xs">
                {shop.hours.map((h) => (
                  <React.Fragment key={h.day}>
                    <dt className="font-bold text-ink">{h.day}</dt>
                    <dd className={h.hours === 'Closed' ? 'text-danger font-semibold' : 'text-ink-muted font-semibold'}>{h.hours}</dd>
                  </React.Fragment>
                ))}
              </dl>
            )}
          </div>
        </div>

        {!shop.isOpen && (
          <div role="status" className="border-t border-line bg-warning-soft text-warning px-5 py-2.5 text-sm font-bold flex items-center gap-2">
            <Clock className="w-4 h-4" /> Closed now{shop.closedText ? `. ${shop.closedText}.` : '.'} You can browse, but orders open when the shop does.
          </div>
        )}
      </section>

      {categories.length > 1 && (
        <div className="flex gap-2 overflow-x-auto pb-1" aria-label="Filter this shop's items">
          <button onClick={() => setCategory('')} aria-pressed={!category} className={chip(!category)}>All</button>
          {categories.map((c) => (
            <button key={c.slug} onClick={() => setCategory(category === c.slug ? '' : c.slug)} aria-pressed={category === c.slug} className={chip(category === c.slug)}>
              {c.name}
            </button>
          ))}
        </div>
      )}

      {visible.length === 0 ? (
        <div className="bg-surface-muted border border-line rounded-panel p-12 text-center">
          <h2 className="text-base font-bold text-ink">Nothing here yet</h2>
          <p className="text-sm text-ink-subtle font-medium mt-1">This shop has no items in this section right now.</p>
        </div>
      ) : (
        <div className="grid grid-cols-2 sm:grid-cols-3 xl:grid-cols-4 gap-4">
          {visible.map((product) => (
            <ProductCard
              key={product.id}
              product={product}
              onAddToCart={(p) => handleAddToCart(p, p.variants?.[0] || null)}
              onQuickView={() => {}}
              onToggleCompare={() => {}}
              isCompared={false}
            />
          ))}
        </div>
      )}
    </div>
  );
}
