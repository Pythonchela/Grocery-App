'use client';

import React, { useState } from 'react';
import Link from 'next/link';
import { Tag } from 'lucide-react';
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

/** A heading, then the first items as small tiles: a picture on a soft green square, and the name. */
function TileGrid({ title, href, products }) {
  if (!products.length) return null;
  return (
    <section>
      <div className="mb-3 flex items-end justify-between gap-3">
        <h2 className="text-xl font-black text-ink">{title}</h2>
        {href && <Link href={href} className="text-sm font-black text-accent hover:underline">See all</Link>}
      </div>
      <div className="grid grid-cols-4 gap-x-3 gap-y-4 sm:grid-cols-6 lg:grid-cols-8">
        {products.map((p) => (
          <Link key={p.id} href={`/product/${p.id}`} className="group text-center">
            <span className="block aspect-square overflow-hidden rounded-[18px] bg-pastel-green p-1.5 transition group-hover:shadow-card">
              {p.images?.[0] && <img src={p.images[0]} alt="" loading="lazy" className="h-full w-full rounded-[13px] object-cover" />}
            </span>
            <span className="mt-1.5 block text-[11px] font-semibold leading-tight text-ink sm:text-xs">{p.title.replace(/^Sample: /, '')}</span>
          </Link>
        ))}
      </div>
    </section>
  );
}

export default function QuickHome({ categories, products, popular, onAddToCart }) {
  const [vegOnly, setVegOnly] = useState(false);
  const [offersOnly, setOffersOnly] = useState(false);
  const [tab, setTab] = useState(null); // a category id, or null for All

  const keep = (p) => !(vegOnly && (p.diet === 'non_veg' || p.diet === 'egg')) && !(offersOnly && !(p.discount > 0));
  const shown = products.filter(keep);
  const ready = readyRange(products);

  const chip = (on) =>
    `inline-flex items-center gap-2 rounded-pill border px-4 py-2 text-sm font-bold transition ${
      on ? 'border-on-accent bg-surface text-accent' : 'border-on-accent/40 bg-transparent text-on-accent hover:border-on-accent'
    }`;

  return (
    <div className="space-y-8">
      <section className="rounded-[28px] bg-accent p-5 text-on-accent sm:p-8">
        <p className="text-sm font-semibold opacity-90">{brand.name} in</p>
        <h1 className="mt-0.5 text-4xl font-black leading-tight sm:text-5xl">{ready || 'minutes'}</h1>
        <p className="mt-1 text-sm font-medium opacity-90">Delivered fresh by {brand.name}.</p>
        <div className="mt-4 flex flex-wrap gap-2">
          <button type="button" aria-pressed={vegOnly} onClick={() => setVegOnly((v) => !v)} className={chip(vegOnly)}>
            <DietMark diet="veg" /> Veg only
          </button>
          <button type="button" aria-pressed={offersOnly} onClick={() => setOffersOnly((v) => !v)} className={chip(offersOnly)}>
            <Tag className="h-4 w-4" /> Offers
          </button>
        </div>
        {categories.length > 1 && (
          <div role="tablist" aria-label="Aisles" className="-mx-1 mt-5 flex gap-1 overflow-x-auto">
            {[{ id: null, name: 'All' }, ...categories].map((c) => (
              <button
                key={c.id ?? 'all'}
                type="button"
                role="tab"
                aria-selected={tab === c.id}
                onClick={() => setTab(c.id)}
                className={`shrink-0 border-b-[3px] px-3 py-2 text-sm transition ${tab === c.id ? 'border-on-accent font-black' : 'border-transparent font-semibold opacity-80 hover:opacity-100'}`}
              >
                {c.name}
              </button>
            ))}
          </div>
        )}
      </section>

      {categories.length > 0 && tab === null && (
        <section aria-label="Categories">
          <div className="grid grid-cols-3 gap-4 sm:grid-cols-4 md:grid-cols-6 lg:grid-cols-8">
            {categories.map((c) => (
              <Link key={c.id} href={`/category/${c.slug}`} className="group flex flex-col items-center gap-2 text-center">
                <span className="flex h-20 w-20 items-center justify-center overflow-hidden rounded-[22px] bg-pastel-green p-1.5 transition group-hover:shadow-card">
                  {c.coverImageUrl || c.imageUrl ? (
                    <img src={c.coverImageUrl || c.imageUrl} alt="" className="h-full w-full rounded-[16px] object-cover" loading="lazy" />
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

      {tab === null && <Rail title="Popular right now" products={(popular.length ? popular : products.slice(0, 10)).filter(keep)} onAddToCart={onAddToCart} />}

      {categories.filter((c) => tab === null || c.id === tab).map((c) => (
        <TileGrid
          key={c.id}
          title={c.name}
          href={`/category/${c.slug}`}
          products={shown.filter((p) => p.categoryId === c.id).slice(0, tab === null ? 8 : 40)}
        />
      ))}

      {!shown.length && <p className="py-10 text-center text-sm font-medium text-ink-subtle">Nothing matches those filters right now.</p>}
    </div>
  );
}
