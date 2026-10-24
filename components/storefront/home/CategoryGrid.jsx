'use client';

import React from 'react';
import Link from 'next/link';
import * as Icons from 'lucide-react';

/**
 * Category picker for the home page: a round picture per category with its name
 * beneath. A scrolling row on phones, a wrapping grid on larger screens.
 *
 * The picture comes from the category's own image (set in the admin panel). A
 * category without one falls back to its icon, so a store can add pictures one
 * category at a time without anything looking broken.
 */
function CategoryThumb({ cat, size = 'lg' }) {
  const box = size === 'lg' ? 'w-[72px] h-[72px] sm:w-20 sm:h-20' : 'w-12 h-12';
  const image = cat.coverImageUrl || cat.imageUrl || cat.image_url || cat.cover_image_url;

  if (image) {
    return (
      <span className={`${box} rounded-pill overflow-hidden bg-surface-sunken border border-line block`}>
        <img src={image} alt="" loading="lazy" className="w-full h-full object-cover" />
      </span>
    );
  }

  const iconName = cat.iconUrl || cat.icon_url;
  const Icon = (iconName && Icons[iconName]) || Icons.Sparkles;
  return (
    <span className={`${box} rounded-pill bg-accent-soft text-accent flex items-center justify-center`}>
      <Icon className="w-6 h-6" />
    </span>
  );
}

export default function CategoryGrid({ categories = [] }) {
  if (!categories.length) return null;

  return (
    <section className="space-y-3">
      <div className="flex items-center justify-between">
        <h2 className="text-lg font-bold text-ink tracking-tight">Shop by category</h2>
        <Link href="/search" className="text-xs font-semibold text-accent hover:underline">
          See all
        </Link>
      </div>

      <div className="flex gap-4 sm:gap-6 overflow-x-auto sm:flex-wrap sm:overflow-visible pb-1 -mx-4 px-4 sm:mx-0 sm:px-0 snap-x">
        {categories.map((cat) => (
          <Link
            key={cat.id || cat.slug}
            href={`/category/${cat.slug}`}
            className="group shrink-0 w-[76px] sm:w-24 flex flex-col items-center text-center gap-2 snap-start"
          >
            <span className="transition-transform duration-200 group-hover:scale-105">
              <CategoryThumb cat={cat} />
            </span>
            <span className="text-xs font-medium text-ink leading-tight line-clamp-2 group-hover:text-accent transition-colors">
              {cat.name}
            </span>
          </Link>
        ))}
      </div>
    </section>
  );
}
