import React from 'react';
import HomeClient from '../components/storefront/HomeClient';
import { apiFetch, mapProduct, mapCategory } from '../lib/apiClient';

export const dynamic = 'force-dynamic';

export default async function HomePage() {
  let categories = [];
  let products = [];
  let hasReels = false;
  let sections = [];

  try {
    const [categoriesRes, productsRes, reelsRes, sectionsRes] = await Promise.all([
      apiFetch('/categories'),
      // HomeClient filters/sorts this array entirely client-side (category
      // rows, "new arrivals", best sellers) rather than fetching per section,
      // so it needs the whole catalog in one call. `/products` now paginates
      // (48 by default) to protect the admin list and search from loading an
      // unbounded catalog, so this asks for the controller's full page-size
      // ceiling explicitly rather than silently losing everything past #48.
      apiFetch('/products?per_page=100'),
      apiFetch('/reels?per_page=1'),
      // The layout an admin builds in Storefront Builder. A failure here falls
      // back to the built-in layout rather than failing the page.
      apiFetch('/storefront/sections').catch(() => null),
    ]);

    categories = (categoriesRes?.data || []).map(mapCategory);
    products = (productsRes?.data || []).map(mapProduct);
    hasReels = (reelsRes?.meta?.total ?? 0) > 0;
    sections = sectionsRes?.data || [];
  } catch (e) {
    console.error('Failed to fetch home page data from API:', e.message);
  }

  return <HomeClient categories={categories} products={products} hasReels={hasReels} sections={sections} />;
}
