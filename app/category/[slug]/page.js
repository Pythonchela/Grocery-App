import React from 'react';
import { notFound } from 'next/navigation';
import { apiFetch, mapProduct, mapCategory } from '../../../lib/apiClient';
import CategoryClient from '../../../components/storefront/CategoryClient';

export default async function CategoryPage({ params }) {
  const { slug } = await params;

  const categoriesRes = await apiFetch('/categories');
  const rawCategory = categoriesRes.data.find(c => c.slug === slug);

  if (!rawCategory) {
    notFound();
  }

  // CategoryClient filters/sorts this list entirely in the browser (price
  // range, attributes, sort order) with no further fetch — so, same as the
  // homepage, this needs the category's full product list in one call rather
  // than the paginated default.
  const productsRes = await apiFetch(`/products?category=${slug}&per_page=100`);
  const products = productsRes.data.map(mapProduct);
  const category = mapCategory(rawCategory);

  return <CategoryClient category={category} products={products} />;
}
