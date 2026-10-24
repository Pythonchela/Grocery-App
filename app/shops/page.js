import { redirect } from 'next/navigation';
import { apiFetch } from '../../lib/apiClient';
import { mapShop } from '../../lib/shops';
import { readStoreConfig } from '../../lib/shopRules';
import ShopsClient from '../../components/storefront/ShopsClient';

export const metadata = {
  title: 'Shops | BazaarX',
  description: 'Order from the shops near you.',
};

export default async function ShopsPage({ searchParams }) {
  const { search = '', category = '', open = '' } = (await searchParams) || {};

  // A single-business store has no shop directory: there is only the one shop.
  const config = readStoreConfig((await apiFetch('/config').catch(() => ({}))).data);
  if (!config.shows_shops) redirect('/');

  const params = new URLSearchParams({ per_page: '50' });
  if (search) params.set('search', search);
  if (category) params.set('category', category);
  if (open) params.set('open', '1');

  const res = await apiFetch(`/shops?${params}`);

  return (
    <ShopsClient
      shops={(res.data || []).map(mapShop)}
      categories={res.facets?.categories || []}
      active={{ search, category, open: Boolean(open) }}
    />
  );
}
