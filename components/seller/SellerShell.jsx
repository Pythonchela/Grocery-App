'use client';

import React, { useEffect, useState } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import {
  BellRing, ExternalLink, LayoutDashboard, LifeBuoy, LogOut, Menu, MessageSquare, Package,
  PackageCheck, RefreshCw, Store, Tag, Undo2, Upload, Wallet, X,
} from 'lucide-react';
import { brand } from '@ds/brand';
import { useBrandLogo } from '../providers/BrandProvider';
import { useStore } from '../providers/StoreProvider';

/**
 * The seller's left-hand navigation.
 *
 * Grouped by what a seller is doing (answering orders, keeping the catalogue,
 * reading customers, money, the shop itself), so the thing they open first, the
 * orders waiting for an answer, is never buried among settings. The same list
 * is a slide-in drawer on a phone-width screen.
 */
export const SELLER_NAV = [
  { items: [{ key: 'overview', label: 'Today', Icon: LayoutDashboard }] },
  {
    title: 'Orders',
    items: [
      { key: 'incoming', label: 'New orders', Icon: BellRing, badge: 'newOrders' },
      { key: 'orders', label: 'Orders', Icon: PackageCheck },
      { key: 'returns', label: 'Returns', Icon: Undo2 },
    ],
  },
  {
    title: 'Catalogue',
    items: [
      { key: 'products', label: 'Products', Icon: Package },
      { key: 'import', label: 'Bulk import', Icon: Upload },
      { key: 'coupons', label: 'Offers', Icon: Tag },
    ],
  },
  { title: 'Customers', items: [{ key: 'feedback', label: 'Reviews & Q&A', Icon: MessageSquare }] },
  { title: 'Money', items: [{ key: 'earnings', label: 'Earnings', Icon: Wallet }] },
  {
    title: 'Shop',
    items: [
      { key: 'shop', label: 'My shop', Icon: Store },
      { key: 'help', label: 'Help & support', Icon: LifeBuoy },
    ],
  },
];

function shopStanding(profile) {
  if (!profile) return null;
  const pausedUntil = profile.paused_until && new Date(profile.paused_until) > new Date();
  if (pausedUntil) return { label: 'Paused', dot: 'bg-warning' };
  if (profile.accepting_orders === false) return { label: 'Closed', dot: 'bg-danger' };
  return { label: 'Open', dot: 'bg-success' };
}

export default function SellerShell({ tab, onSelect, badges = {}, profile, onRefresh, children }) {
  const [open, setOpen] = useState(false);
  const router = useRouter();
  const logoUrl = useBrandLogo();
  const { logout } = useStore();
  const standing = shopStanding(profile);
  const current = SELLER_NAV.flatMap(g => g.items).find(i => i.key === tab);

  // A drawer left open behind a route change or an Escape press is a trap.
  useEffect(() => {
    if (!open) return undefined;
    const onKey = e => { if (e.key === 'Escape') setOpen(false); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [open]);

  const pick = key => { onSelect(key); setOpen(false); };

  const signOut = async () => {
    await logout();
    router.push('/');
  };

  const sidebar = (
    <div className="flex h-full flex-col">
      <div className="flex items-center gap-3 border-b border-line px-4 py-4">
        {logoUrl
          ? <img src={logoUrl} alt="" className="h-9 w-9 object-contain" />
          : <span className="flex h-9 w-9 items-center justify-center rounded-control bg-inverse text-sm font-black text-ink-inverse">{brand.logoInitials}</span>}
        <div className="min-w-0">
          <p className="truncate text-sm font-black text-ink">{brand.name}</p>
          <p className="text-2xs font-bold uppercase tracking-wider text-ink-subtle">Seller centre</p>
        </div>
        <button type="button" onClick={() => setOpen(false)} aria-label="Close menu" className="ml-auto rounded-control p-1.5 text-ink-muted hover:text-ink lg:hidden"><X className="h-5 w-5" /></button>
      </div>

      <button type="button" onClick={() => pick('shop')} className="mx-3 mt-3 rounded-card border border-line bg-surface-muted px-3 py-2.5 text-left hover:border-accent">
        <span className="block truncate text-sm font-bold text-ink">{profile?.display_name || 'My shop'}</span>
        {standing && <span className="mt-0.5 flex items-center gap-1.5 text-xs font-bold text-ink-muted"><span className={`h-2 w-2 rounded-full ${standing.dot}`} />{standing.label}</span>}
      </button>

      <nav aria-label="Seller dashboard" className="flex-1 space-y-4 overflow-y-auto px-3 py-4">
        {SELLER_NAV.map((group, i) => (
          <div key={group.title || i}>
            {group.title && <p className="mb-1 px-3 text-2xs font-black uppercase tracking-wider text-ink-subtle">{group.title}</p>}
            <ul className="space-y-0.5">
              {group.items.map(({ key, label, Icon, badge }) => {
                const selected = tab === key;
                const count = badge ? badges[badge] : 0;
                return (
                  <li key={key}>
                    <button
                      type="button"
                      onClick={() => pick(key)}
                      aria-current={selected ? 'page' : undefined}
                      className={`flex w-full items-center gap-3 rounded-control px-3 py-2 text-sm font-bold transition ${selected ? 'bg-accent-soft text-accent' : 'text-ink-muted hover:bg-surface-muted hover:text-ink'}`}
                    >
                      <Icon className="h-4 w-4 shrink-0" aria-hidden="true" />
                      <span className="flex-1 text-left">{label}</span>
                      {count > 0 && <span className="rounded-full bg-danger px-2 py-0.5 text-xs text-on-accent">{count}</span>}
                    </button>
                  </li>
                );
              })}
            </ul>
          </div>
        ))}
      </nav>

      <div className="space-y-0.5 border-t border-line p-3">
        <Link href="/" className="flex items-center gap-3 rounded-control px-3 py-2 text-sm font-bold text-ink-muted hover:bg-surface-muted hover:text-ink">
          <ExternalLink className="h-4 w-4" aria-hidden="true" /> Shop as a customer
        </Link>
        <button type="button" onClick={signOut} className="flex w-full items-center gap-3 rounded-control px-3 py-2 text-sm font-bold text-ink-muted hover:bg-surface-muted hover:text-danger">
          <LogOut className="h-4 w-4" aria-hidden="true" /> Sign out
        </button>
      </div>
    </div>
  );

  return (
    <div className="min-h-screen bg-canvas text-ink lg:flex">
      <aside className="hidden w-64 shrink-0 border-r border-line bg-surface lg:sticky lg:top-0 lg:block lg:h-screen">{sidebar}</aside>

      {open && (
        <div className="fixed inset-0 z-50 lg:hidden">
          <button type="button" aria-label="Close menu" className="absolute inset-0 bg-inverse/50" onClick={() => setOpen(false)} />
          <aside className="absolute inset-y-0 left-0 w-72 max-w-[85vw] bg-surface shadow-xl">{sidebar}</aside>
        </div>
      )}

      <div className="min-w-0 flex-1">
        <header className="sticky top-0 z-30 flex items-center gap-3 border-b border-line bg-surface px-4 py-3">
          <button type="button" onClick={() => setOpen(true)} aria-label="Open menu" className="rounded-control p-1.5 text-ink hover:bg-surface-muted lg:hidden"><Menu className="h-5 w-5" /></button>
          <h1 className="text-lg font-black text-ink">{current?.label || 'Dashboard'}</h1>
          {standing && <span className="hidden items-center gap-1.5 rounded-pill border border-line px-2.5 py-1 text-xs font-bold text-ink-muted sm:flex"><span className={`h-2 w-2 rounded-full ${standing.dot}`} />{standing.label}</span>}
          <button type="button" onClick={onRefresh} className="ml-auto flex items-center gap-1.5 rounded-control border border-line px-3 py-1.5 text-xs font-bold text-ink hover:border-accent"><RefreshCw className="h-3.5 w-3.5" aria-hidden="true" /> Refresh</button>
        </header>
        <main className="mx-auto max-w-5xl space-y-5 px-4 py-6">{children}</main>
      </div>
    </div>
  );
}
