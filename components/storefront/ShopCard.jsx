'use client';

import React from 'react';
import Link from 'next/link';
import { Star, Store, Clock } from 'lucide-react';
import { formatINR } from '../../lib/apiClient';
import { shopMetaLine, shopSubtitle } from '../../lib/shops';

/** One shop in a list: who it is, what it sells, whether it is taking orders now. */
export default function ShopCard({ shop }) {
  const meta = shopMetaLine(shop, formatINR);

  return (
    <Link
      href={`/shop/${shop.slug}`}
      className={`group block bg-surface border border-line rounded-panel overflow-hidden hover:border-line-strong hover:shadow-card transition ${shop.isOpen ? '' : 'opacity-75'}`}
    >
      <div className="relative h-28 bg-surface-muted">
        {shop.bannerUrl && <img src={shop.bannerUrl} alt="" className="w-full h-full object-cover" loading="lazy" />}
        {!shop.isOpen && (
          <span className="absolute left-3 bottom-3 inline-flex items-center gap-1 bg-inverse/80 text-ink-inverse text-[11px] font-bold px-2 py-1 rounded-pill">
            <Clock className="w-3 h-3" /> {shop.closedText || 'Closed now'}
          </span>
        )}
      </div>

      <div className="p-4 flex gap-3">
        <div className="w-12 h-12 -mt-9 rounded-card border-2 border-surface bg-surface-muted overflow-hidden shrink-0 flex items-center justify-center">
          {shop.logoUrl
            ? <img src={shop.logoUrl} alt="" className="w-full h-full object-cover" loading="lazy" />
            : <Store className="w-5 h-5 text-ink-subtle" />}
        </div>
        <div className="min-w-0 flex-1">
          <div className="flex items-start justify-between gap-2">
            <h3 className="text-sm font-black text-ink truncate group-hover:text-accent">{shop.name}</h3>
            {shop.rating > 0 && (
              <span className="inline-flex items-center gap-0.5 bg-success-soft text-success text-[11px] font-black px-1.5 py-0.5 rounded-control shrink-0">
                {shop.rating.toFixed(1)} <Star className="w-3 h-3 fill-current" />
              </span>
            )}
          </div>
          {shopSubtitle(shop) && <p className="text-xs text-ink-muted font-medium truncate mt-0.5">{shopSubtitle(shop)}</p>}
          <p className="text-[11px] text-ink-subtle font-semibold mt-1">
            {[meta, shop.productCount ? `${shop.productCount} items` : null].filter(Boolean).join(' · ')}
          </p>
        </div>
      </div>
    </Link>
  );
}
