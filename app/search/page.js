import { apiFetch, mapProduct } from '../../lib/apiClient';
import SearchClient from '../../components/storefront/SearchClient';

export const metadata = {
  title: 'Search Results | Haatvia',
  description: 'Search for the best products on Haatvia.',
};

export default async function SearchPage({ searchParams }) {
  const query = (await searchParams)?.q || '';

  const params = new URLSearchParams();
  if (query) params.set('search', query);
  // SearchClient's own filter panel (price, rating, attributes) runs entirely
  // client-side over this array, so — same reasoning as the homepage and
  // category pages — this needs the full result set, not the 48-item default.
  params.set('per_page', '100');

  const res = await apiFetch(`/products?${params.toString()}`);
  const mappedProducts = res.data.map(mapProduct);

  return <SearchClient query={query} products={mappedProducts} />;
}
