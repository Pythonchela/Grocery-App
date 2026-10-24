import { notFound } from 'next/navigation';
import { apiFetch, mapProduct } from '../../../lib/apiClient';
import { mapShop } from '../../../lib/shops';
import ShopClient from '../../../components/storefront/ShopClient';

export async function generateMetadata({ params }) {
  const { slug } = await params;
  try {
    const shop = mapShop((await apiFetch(`/shops/${slug}`)).data);
    return { title: `${shop.name} | BazaarX`, description: shop.tagline || `Order from ${shop.name}.` };
  } catch {
    return { title: 'Shop | BazaarX' };
  }
}

export default async function ShopPage({ params }) {
  const { slug } = await params;

  let shopRes;
  try {
    shopRes = await apiFetch(`/shops/${slug}`);
  } catch {
    notFound();
  }

  // The shop's whole list in one call: ShopClient filters it by section in the browser.
  const productsRes = await apiFetch(`/products?seller=${encodeURIComponent(slug)}&per_page=100`);

  return <ShopClient shop={mapShop(shopRes.data)} products={productsRes.data.map(mapProduct)} />;
}
