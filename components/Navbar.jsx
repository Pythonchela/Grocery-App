'use client';

import React, { useState, useEffect } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import {
  Search,
  Mic,
  ShoppingBag,
  Video,
  ChevronDown,
  Menu,
  X,
  Sparkles,
  UserRound,
} from 'lucide-react';
import NotificationBell from './NotificationBell';
import { ThemeToggle } from './ThemeToggle';
import { useStore } from './providers/StoreProvider';
import { apiFetch } from '../lib/apiClient';
import { brand } from '@ds/brand';
import { useBrandLogo } from './providers/BrandProvider';
import { Button } from '@ds/ui';

export default function Navbar({
  cartCount,
  onOpenCart,
  onOpenVoice,
  currentView,
  onToggleView,
}) {
  const { authUser } = useStore();
  // A single-business store has no one to sell for it, so no invitation to.
  const [selectedLang, setSelectedLang] = useState('English');
  const [selectedStore, setSelectedStore] = useState('Bengaluru HSR Store');
  const [showStoreMenu, setShowStoreMenu] = useState(false);
  const [showLangMenu, setShowLangMenu] = useState(false);
  const [activeDropdown, setActiveDropdown] = useState(null); // 'products' | 'why' | null
  const [showMobileMenu, setShowMobileMenu] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');
  // Reels are opt-in per product — most stores will have none. Rather than
  // advertise a feature that leads to an empty page, the nav checks once
  // whether anything is actually live and only then shows the links.
  const [hasReels, setHasReels] = useState(false);
  // The real categories, for the menu: the shop is whatever the owner has put in it.
  const [categories, setCategories] = useState([]);

  useEffect(() => {
    let alive = true;
    apiFetch('/categories')
      .then((res) => { if (alive) setCategories(res.data || []); })
      .catch(() => { /* the menu just stays short */ });
    return () => { alive = false; };
  }, []);

  useEffect(() => {
    let alive = true;
    apiFetch('/reels?per_page=1')
      .then((res) => {
        if (alive) setHasReels((res.meta?.total ?? 0) > 0);
      })
      .catch(() => {
        // A failed check just keeps the links hidden — reels are optional, so
        // this must never surface as a navbar error.
      });
    return () => {
      alive = false;
    };
  }, []);
  const router = useRouter();
  const logoUrl = useBrandLogo();

  const handleSearch = (e) => {
    e.preventDefault();
    if (searchQuery.trim()) {
      router.push(`/search?q=${encodeURIComponent(searchQuery.trim())}`);
    }
  };

  const stores = ['Bengaluru HSR Store', 'Mumbai Bandra Store', 'Delhi CP Store', 'Kolkata Park St Store', 'Hyderabad Jubilee Store'];
  const languages = ['English', 'हिंदी (Hindi)', 'தமிழ் (Tamil)', 'తెలుగు (Telugu)', 'Hinglish'];

  return (
    <header className="sticky top-0 z-50 bg-surface text-ink border-b border-line font-sans shadow-subtle">
      

      {/* 2. MAIN NORDIC MINIMALIST HEADER BAR */}
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-3.5 flex items-center justify-between gap-6">
        
        {/* Left Section: Logo & Nav Links */}
        <div className="flex items-center gap-8">
          
          {/* Brand Logo */}
          <Link href="/" className="flex items-center gap-2.5 group">
            {logoUrl ? (
              <img src={logoUrl} alt="" className="w-10 h-10 object-contain" />
            ) : (
              <div className="w-10 h-10 rounded-card bg-inverse p-0.5 shadow-subtle group-hover:bg-danger transition">
                <div className="w-full h-full bg-surface rounded-[14px] flex items-center justify-center font-black text-ink text-xl tracking-wider">
                  {brand.logoInitials.charAt(0)}<span className="text-danger">{brand.logoInitials.charAt(1)}</span>
                </div>
              </div>
            )}
            <div>
              <span className="font-black text-2xl tracking-tight text-ink">
                {brand.nameDisplay}<span className="text-danger">{brand.nameAccent}</span>
              </span>
              <span className="block text-[10px] font-black tracking-widest text-ink-subtle uppercase -mt-1">
                {brand.tagline}
              </span>
            </div>
          </Link>

          {/* Desktop Nav Links */}
          <nav className="hidden lg:flex items-center gap-6 text-xs font-bold text-ink-muted">

            {/* Shop by Category mega-menu */}
            <button
              onClick={() => setActiveDropdown(activeDropdown === 'products' ? null : 'products')}
              className={`flex items-center gap-1.5 transition py-2 font-black ${
                activeDropdown === 'products' ? 'text-ink border-b-2 border-line-strong' : 'hover:text-ink'
              }`}
            >
              <span>Categories</span>
              <ChevronDown className={`w-3.5 h-3.5 text-ink-subtle transition-transform ${activeDropdown === 'products' ? 'rotate-180 text-ink' : ''}`} />
            </button>

            <Link href="/search" className="hover:text-ink transition py-2">All items</Link>

            {hasReels && (
              <Link href="/reels" className="hover:text-ink transition py-2 flex items-center gap-1">
                <Video className="w-3.5 h-3.5 text-accent" />
                <span>Reels</span>
              </Link>
            )}
          </nav>
        </div>

        {/* Right Section: Search & Pill Action Buttons */}
        <div className="flex items-center gap-4">
          
          {/* Vernacular Search */}
          <form onSubmit={handleSearch} role="search" className="relative hidden md:block w-64">
            {/* Visually hidden rather than absent: a placeholder is not a label
                — it disappears on input and is not reliably announced. */}
            <label htmlFor="navbar-search" className="sr-only">
              Search the catalogue
            </label>
            <input
              id="navbar-search"
              type="search"
              placeholder="Search for 'milk', 'biryani'..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="w-full bg-surface-sunken border border-line rounded-pill pl-9 pr-10 py-2 text-xs font-semibold text-ink placeholder-ink-subtle focus:outline-none focus:border-line-strong focus:bg-surface transition"
            />
            <button type="submit" aria-label="Search" className="absolute left-3 top-2.5 text-ink-subtle hover:text-ink">
              <Search className="w-3.5 h-3.5" />
            </button>
            <button
              type="button"
              onClick={onOpenVoice}
              title="Vernacular Voice Search"
              className="absolute right-1 top-1 bg-inverse hover:bg-danger text-ink-inverse p-1.5 rounded-pill transition"
            >
              <Mic className="w-3.5 h-3.5" />
            </button>
          </form>

          <ThemeToggle />

          <NotificationBell />

          <Link
            href="/account/orders"
            className="hidden sm:flex items-center gap-1.5 text-xs font-extrabold text-ink-muted hover:text-ink"
          >
            <UserRound className="w-4 h-4" />
            {authUser ? (authUser.name?.split(' ')[0] || 'Account') : 'Log in'}
          </Link>

          <Button
            size="sm"
            onClick={onOpenCart}
            leadingIcon={<ShoppingBag className="w-4 h-4" />}
          >
            <span>Cart</span>
            {cartCount > 0 && (
              <span className="bg-danger text-ink-inverse font-black text-[11px] w-5 h-5 rounded-pill flex items-center justify-center">
                {cartCount}
              </span>
            )}
          </Button>

          {/* Mobile menu trigger */}
          <button
            onClick={() => setShowMobileMenu(!showMobileMenu)}
            className="lg:hidden p-2 text-ink-muted hover:text-ink"
          >
            {showMobileMenu ? <X className="w-6 h-6" /> : <Menu className="w-6 h-6" />}
          </button>
        </div>
      </div>

      {/* Categories: the real ones, each with its picture */}
      {activeDropdown === 'products' && (
        <div
          className="absolute left-0 top-full w-full bg-surface border-y border-line shadow-panel z-50 text-ink"
          onMouseLeave={() => setActiveDropdown(null)}
        >
          <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
            <ul className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-5">
              {categories.map((c) => (
                <li key={c.id}>
                  <Link href={`/category/${c.slug}`} onClick={() => setActiveDropdown(null)} className="flex items-center gap-3 rounded-card p-2 text-sm font-bold text-ink hover:bg-surface-sunken">
                    <span className="flex h-12 w-12 shrink-0 items-center justify-center overflow-hidden rounded-pill bg-surface-sunken">
                      {c.cover_image_url || c.image_url ? <img src={c.cover_image_url || c.image_url} alt="" className="h-full w-full object-cover" loading="lazy" /> : <Sparkles className="h-5 w-5 text-accent" />}
                    </span>
                    {c.name}
                  </Link>
                </li>
              ))}
            </ul>
          </div>
        </div>
      )}
      {/* MOBILE MENU */}
      {showMobileMenu && (
        <div className="lg:hidden bg-surface border-b border-line p-4 space-y-3">
          {categories.map((c) => (
            <Link key={c.id} href={`/category/${c.slug}`} onClick={() => setShowMobileMenu(false)} className="block py-2 text-sm font-bold text-ink">
              {c.name}
            </Link>
          ))}
          <Link href="/search" onClick={() => setShowMobileMenu(false)} className="block py-2 text-sm font-bold text-ink">
            All items
          </Link>
          {hasReels && (
            <Link href="/reels" onClick={() => setShowMobileMenu(false)} className="block py-2 text-sm font-bold text-accent">
              Reels
            </Link>
          )}
          <Link href="/account/orders" onClick={() => setShowMobileMenu(false)} className="block py-2 text-sm font-bold text-ink">
            My Orders
          </Link>
        </div>
      )}

    </header>
  );
}
