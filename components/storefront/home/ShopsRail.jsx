'use client';

import React, { useEffect, useState } from 'react';
import Link from 'next/link';
import { Store } from 'lucide-react';
import { useStore } from '../../providers/StoreProvider';
import { apiFetch } from '../../../lib/apiClient';
import { mapShop } from '../../../lib/shops';
import ShopCard from '../ShopCard';

/**
 * A row of shops for the home page. Nothing in a single-business store (there
 * is only the one shop), nothing where the store has chosen to list products
 * directly, and nothing until there is a shop to show.
 */
export default function ShopsRail() {
  const { storeConfig } = useStore();
  const [shops, setShops] = useState([]);
  const show = storeConfig.shows_shops && storeConfig.home_shows_shops !== false;

  useEffect(() => {
    if (!show) return undefined;
    let cancelled = false;
    apiFetch('/shops?per_page=6')
      .then((res) => { if (!cancelled) setShops((res.data || []).map(mapShop)); })
      .catch(() => {});
    return () => { cancelled = true; };
  }, [show]);

  if (!show || shops.length === 0) return null;

  return (
    <section aria-labelledby="shops-rail-title" className="space-y-3">
      <div className="flex items-center justify-between">
        <h2 id="shops-rail-title" className="flex items-center gap-2 text-lg font-black text-ink">
          <Store className="w-4 h-4 text-accent" /> Shops near you
        </h2>
        <Link href="/shops" className="text-xs font-bold text-accent hover:underline">See all shops →</Link>
      </div>
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
        {shops.slice(0, 3).map((shop) => <ShopCard key={shop.id} shop={shop} />)}
      </div>
    </section>
  );
}
