/**
 * The only bridge between the AI features and the real catalog.
 *
 * Everything the assistant says about a product — that it exists, its price,
 * its rating — resolves to a row this module fetched from the Laravel API. The
 * model never supplies product facts itself; it supplies *filters*, and this
 * returns what actually matched. That boundary is the whole reason the feature
 * is safe to put in front of shoppers: a hallucinated ₹499 phone that doesn't
 * exist is a support ticket and a broken trust promise, not a cosmetic bug.
 */

const API_BASE = process.env.NEXT_PUBLIC_API_URL || 'http://127.0.0.1:8000/api/v1';

/** Trimmed to what a shopper decision needs — full rows would blow the token budget. */
function toModelShape(p) {
  return {
    id: p.id,
    title: p.title,
    slug: p.slug,
    brand: p.brand ?? null,
    price: Number(p.price ?? 0),
    mrp: Number(p.mrp ?? 0),
    discount: p.discount ?? null,
    rating: p.rating ?? null,
    reviews_count: p.reviews_count ?? null,
    in_stock: p.in_stock ?? null,
    category: p.category?.name ?? null,
    category_slug: p.category?.slug ?? null,
    image: Array.isArray(p.images) ? p.images[0] ?? null : null,
    // The defining, per-category features — what the assistant should reason
    // and compare over, rather than re-deriving specs out of prose.
    attributes: p.attributes ?? null,
    features: Array.isArray(p.features) ? p.features.slice(0, 6) : null,
  };
}

/**
 * Runs a catalog query with the same parameters the storefront's own filters
 * use, so the assistant can never reach a result set a shopper couldn't reach
 * by hand.
 */
export async function searchCatalog(params = {}) {
  const qs = new URLSearchParams();

  if (params.search) qs.set('search', String(params.search));
  if (params.category) qs.set('category', String(params.category));
  if (params.brand) qs.set('brand', String(params.brand));
  if (params.min_price != null) qs.set('min_price', String(params.min_price));
  if (params.max_price != null) qs.set('max_price', String(params.max_price));
  if (params.min_rating != null) qs.set('min_rating', String(params.min_rating));
  if (params.in_stock) qs.set('in_stock', '1');
  if (params.sort) qs.set('sort', String(params.sort));

  // Ask for exactly the page we intend to show. The catalog endpoint is paged,
  // so fetching its default page size and slicing locally would pull rows we
  // then throw away — and would make `total_matches` a page count.
  const limit = Math.min(Number(params.limit) || 8, 20);
  qs.set('per_page', String(limit));

  // Per-category attributes, in the ?attr[group][]=value shape the API expects.
  for (const [key, raw] of Object.entries(params.attributes || {})) {
    const values = Array.isArray(raw) ? raw : [raw];
    for (const v of values) {
      if (v !== '' && v != null) qs.append(`attr[${key}][]`, String(v));
    }
  }

  const res = await fetch(`${API_BASE}/products?${qs.toString()}`, {
    headers: { Accept: 'application/json' },
    cache: 'no-store',
  });
  if (!res.ok) throw new Error(`Catalog query failed (${res.status})`);

  const body = await res.json();
  const page = Array.isArray(body?.data) ? body.data : [];

  return {
    // The real match count from the server, not the size of this page — the
    // model tells the shopper "14 matched, here are 8", and that number has to
    // be true.
    total_matches: body?.meta?.total ?? body?.count ?? page.length,
    // Capped so a broad query can't flood the context window.
    products: page.slice(0, limit).map(toModelShape),
  };
}

/**
 * The category tree with each category's own filter groups.
 *
 * This is what makes per-category questioning possible: the assistant reads the
 * real filter groups defined for a category and asks about those, instead of
 * guessing which attributes that product type even has.
 */
export async function getCategoryFilters() {
  const res = await fetch(`${API_BASE}/categories`, {
    headers: { Accept: 'application/json' },
    cache: 'no-store',
  });
  if (!res.ok) throw new Error(`Category query failed (${res.status})`);

  const body = await res.json();
  const rows = Array.isArray(body?.data) ? body.data : [];

  return rows.map((c) => ({
    name: c.name,
    slug: c.slug,
    filter_groups: (c.filter_config?.groups || []).map((g) => ({
      id: g.id,
      label: g.label,
      type: g.type,
      options: (g.options || []).map((o) => o.value),
    })),
  }));
}
