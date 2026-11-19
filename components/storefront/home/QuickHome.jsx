'use client';

import React, { useState } from 'react';
import Link from 'next/link';
import { Tag, Zap } from 'lucide-react';
import { brand } from '@ds/brand';
import ProductCard from '../../ProductCard';
import DietMark from '../../DietMark';

/**
 * The food and grocery store's home page, built the way quick-delivery apps are: the answer to
 * "how fast" first, the categories as a grid of aisles, then a rail of products for each, with
 * ADD on every item. Nothing here is a made-up promise: the time is the range of the preparation
 * times the products themselves declare, and it is left out when none do.
 */

function readyRange(products) {
  const minutes = products
    .map((p) => Number(p.deliveryInfo?.prep_minutes) || Number(p.prepMinutes) || 0)
    .filter((m) => m > 0)
    .sort((a, b) => a - b);
  if (!minutes.length) return null;
  const [low, high] = [minutes[0], minutes[minutes.length - 1]];
  return low === high ? `${low} min` : `${low}–${high} min`;
}

function Rail({ title, href, products, onAddToCart }) {
  if (!products.length) return null;
  return (
    <section>
      <div className="mb-3 flex items-end justify-between gap-3">
        <h2 className="text-xl font-black text-ink">{title}</h2>
        {href && <Link href={href} className="text-sm font-black text-accent hover:underline">See all</Link>}
      </div>
      <div className="-mx-4 flex snap-x gap-3 overflow-x-auto px-4 pb-6 sm:mx-0 sm:px-0">
        {products.map((p) => (
          <div key={p.id} className="w-44 shrink-0 snap-start sm:w-48">
            <ProductCard product={p} onAddToCart={onAddToCart} />
          </div>
        ))}
      </div>
    </section>
  );
}

export default function QuickHome({ categories, products, popular, onAddToCart }) {
  const [vegOnly, setVegOnly] = useState(false);
  const [offersOnly, setOffersOnly] = useState(false);

  const keep = (p) => !(vegOnly && (p.diet === 'non_veg' || p.diet === 'egg')) && !(offersOnly && !(p.discount > 0));
  const shown = products.filter(keep);
  const ready = readyRange(products);

  const chip = (on) =>
    `inline-flex items-center gap-2 rounded-pill border px-4 py-2 text-sm font-bold transition ${
      on ? 'border-accent bg-accent-soft text-accent' : 'border-line bg-surface text-ink-muted hover:border-line-strong'
    }`;

  return (
    <div className="space-y-8">
      <section className="rounded-panel bg-accent-soft p-5 sm:p-8">
        <p className="flex items-center gap-2 text-xs font-black uppercase tracking-widest text-accent">
          <Zap className="h-4 w-4" /> Quick delivery
        </p>
        <h1 className="mt-1 text-3xl font-black leading-tight text-ink sm:text-4xl">
          {ready ? `Ready in ${ready}` : `Fresh from ${brand.name}`}
        </h1>
        <p className="mt-1 text-sm font-medium text-ink-muted">Delivered fresh by {brand.name}.</p>
        <div className="mt-4 flex flex-wrap gap-2">
          <button type="button" aria-pressed={vegOnly} onClick={() => setVegOnly((v) => !v)} className={chip(vegOnly)}>
            <DietMark diet="veg" /> Veg only
          </button>
          <button type="button" aria-pressed={offersOnly} onClick={() => setOffersOnly((v) => !v)} className={chip(offersOnly)}>
            <Tag className="h-4 w-4" /> Offers
          </button>
        </div>
      </section>

      {categories.length > 0 && (
        <section aria-label="Categories">
          <div className="grid grid-cols-3 gap-4 sm:grid-cols-4 md:grid-cols-6 lg:grid-cols-8">
            {categories.map((c) => (
              <Link key={c.id} href={`/category/${c.slug}`} className="group flex flex-col items-center gap-2 text-center">
                <span className="flex h-20 w-20 items-center justify-center overflow-hidden rounded-pill bg-surface-sunken ring-1 ring-line transition group-hover:ring-accent">
                  {c.coverImageUrl || c.imageUrl ? (
                    <img src={c.coverImageUrl || c.imageUrl} alt="" className="h-full w-full object-cover" loading="lazy" />
                  ) : (
                    <span className="text-xl font-black text-accent">{c.name.slice(0, 1)}</span>
                  )}
                </span>
                <span className="text-xs font-bold leading-tight text-ink">{c.name}</span>
              </Link>
            ))}
          </div>
        </section>
      )}

      <Rail title="Popular right now" products={popular.filter(keep)} onAddToCart={onAddToCart} />

      {categories.map((c) => (
        <Rail
          key={c.id}
          title={c.name}
          href={`/category/${c.slug}`}
          products={shown.filter((p) => p.categoryId === c.id).slice(0, 12)}
          onAddToCart={onAddToCart}
        />
      ))}

      {!shown.length && <p className="py-10 text-center text-sm font-medium text-ink-subtle">Nothing matches those filters right now.</p>}
    </div>
  );
}
