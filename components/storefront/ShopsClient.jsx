'use client';

import React, { useState } from 'react';
import { useRouter } from 'next/navigation';
import { Search, Store } from 'lucide-react';
import ShopCard from './ShopCard';

/**
 * The shops a shopper can order from, with filters by what they sell. The
 * category chips come from whatever the shops sell - groceries, clothing,
 * food, medicines - never from a fixed list.
 */
export default function ShopsClient({ shops, categories, active }) {
  const router = useRouter();
  const [search, setSearch] = useState(active.search || '');

  const go = (next) => {
    const merged = { ...active, ...next };
    const params = new URLSearchParams();
    if (merged.search) params.set('search', merged.search);
    if (merged.category) params.set('category', merged.category);
    if (merged.open) params.set('open', '1');
    const qs = params.toString();
    router.push(qs ? `/shops?${qs}` : '/shops');
  };

  const chip = (selected) =>
    `px-3.5 py-1.5 rounded-pill border text-xs font-bold whitespace-nowrap transition ${
      selected ? 'bg-inverse text-ink-inverse border-inverse' : 'bg-surface text-ink-muted border-line hover:border-line-strong'
    }`;

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-5">
      <header className="flex flex-col sm:flex-row sm:items-end justify-between gap-3">
        <div>
          <h1 className="text-2xl font-black text-ink">Shops</h1>
          <p className="text-sm text-ink-muted font-medium">Pick a shop and order from it. Each basket holds one shop at a time.</p>
        </div>

        <form
          role="search"
          onSubmit={(e) => { e.preventDefault(); go({ search: search.trim() }); }}
          className="relative w-full sm:w-72"
        >
          <label htmlFor="shops-search" className="sr-only">Search shops</label>
          <input
            id="shops-search"
            type="search"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search shops"
            className="w-full bg-surface border border-line rounded-pill pl-9 pr-3 py-2 text-sm font-semibold text-ink placeholder-ink-subtle focus:outline-none focus:border-line-strong"
          />
          <Search className="w-4 h-4 text-ink-subtle absolute left-3 top-2.5" />
        </form>
      </header>

      <div className="flex gap-2 overflow-x-auto pb-1" aria-label="Filter shops">
        <button onClick={() => go({ open: !active.open })} aria-pressed={Boolean(active.open)} className={chip(active.open)}>
          Open now
        </button>
        <button onClick={() => go({ category: '' })} aria-pressed={!active.category} className={chip(!active.category)}>
          All
        </button>
        {categories.map((c) => (
          <button key={c.slug} onClick={() => go({ category: active.category === c.slug ? '' : c.slug })} aria-pressed={active.category === c.slug} className={chip(active.category === c.slug)}>
            {c.name}
          </button>
        ))}
      </div>

      {shops.length === 0 ? (
        <div className="bg-surface-muted border border-line rounded-panel p-12 text-center">
          <Store className="w-8 h-8 mx-auto text-ink-subtle mb-2" />
          <h2 className="text-base font-bold text-ink">No shops match</h2>
          <p className="text-sm text-ink-subtle font-medium mt-1">Try another search, or clear the filters.</p>
        </div>
      ) : (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
          {shops.map((shop) => <ShopCard key={shop.id} shop={shop} />)}
        </div>
      )}
    </div>
  );
}
