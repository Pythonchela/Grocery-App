import { picksFromOrderItem } from './productOptions';

const API_BASE = process.env.NEXT_PUBLIC_API_URL || 'http://127.0.0.1:8000/api/v1';
const FALLBACK_IMAGE = 'https://images.unsplash.com/photo-1505740420928-5e560c06d30e?auto=format&fit=crop&w=800&q=80';

export async function apiFetch(path, { method = 'GET', body, token, cache } = {}) {
  const headers = { 'Content-Type': 'application/json', Accept: 'application/json' };
  if (token) headers.Authorization = `Bearer ${token}`;

  const res = await fetch(`${API_BASE}${path}`, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
    cache: cache ?? 'no-store',
  });

  const data = await res.json().catch(() => ({}));

  if (!res.ok) {
    // A 401 on a request we sent a token with means that token is dead
    // (expired/revoked//DB reset). Clear it and let the app fall back to its
    // login screen — otherwise callers silently render empty data as if the
    // account genuinely had none.
    if (res.status === 401 && token && typeof window !== 'undefined') {
      clearStoredAuth();
      localStorage.removeItem('bx_admin_session');
      window.dispatchEvent(new CustomEvent('haatvia:unauthorized'));
    }

    const message = data.errors
      ? Object.values(data.errors).flat().join(' ')
      : data.message || `Request failed (${res.status})`;
    const error = new Error(message);
    error.status = res.status;
    // Kept alongside the flattened message so a form can put each Laravel
    // validation error next to the field it belongs to, instead of showing one
    // run-on sentence above the whole form.
    error.fieldErrors = data.errors || null;
    throw error;
  }

  return data;
}

// ── Auth token persistence (client-side only) ─────────────────────────────
const TOKEN_KEY = 'haatvia_auth_token';
const USER_KEY = 'haatvia_auth_user';

/**
 * Downloads a file the API serves (a CSV statement) with the user's token, which
 * a plain link cannot send.
 */
export async function apiDownload(path, { token, filename } = {}) {
  const res = await fetch(`${API_BASE}${path}`, { headers: token ? { Authorization: `Bearer ${token}` } : {} });
  if (!res.ok) {
    const data = await res.json().catch(() => ({}));
    throw new Error(data.message || `Download failed (${res.status})`);
  }
  const url = URL.createObjectURL(await res.blob());
  const link = document.createElement('a');
  link.href = url;
  link.download = filename || 'download';
  document.body.appendChild(link);
  link.click();
  link.remove();
  URL.revokeObjectURL(url);
}

export function getStoredAuth() {
  if (typeof window === 'undefined') return { token: null, user: null };
  try {
    const token = localStorage.getItem(TOKEN_KEY);
    const user = JSON.parse(localStorage.getItem(USER_KEY) || 'null');
    return { token, user };
  } catch (e) {
    return { token: null, user: null };
  }
}

export function setStoredAuth(token, user) {
  localStorage.setItem(TOKEN_KEY, token);
  localStorage.setItem(USER_KEY, JSON.stringify(user));
}

export function clearStoredAuth() {
  localStorage.removeItem(TOKEN_KEY);
  localStorage.removeItem(USER_KEY);
}

// ── Shape normalizers: Laravel's snake_case JSON -> the shape every
//    storefront/admin component already expects (carried over from Prisma) ──
export function mapCategory(c) {
  if (!c) return c;
  return {
    ...c,
    iconUrl: c.icon_url,
    imageUrl: c.image_url,
    // What lists show: the admin's picture, else a photo of something in the
    // category. Kept apart so the admin form never mistakes it for an upload.
    coverImageUrl: c.cover_image_url || c.image_url || null,
    bannerUrl: c.banner_url,
    sortOrder: c.sort_order,
    isFeatured: c.is_featured,
    parentId: c.parent_id,
    filterConfig: c.filter_config,
    optionGroups: c.option_groups || [],
    // What shoppers choose between here: labels plus the sizes and colours to offer.
    variantSetup: c.variant_setup || null,
    deliveryProfile: c.delivery_profile || '',
    prepMinutes: c.prep_minutes ?? '',
    // Suggested specification rows for products in this category.
    specTemplate: c.spec_template || [],
    _count: { products: c.products_count ?? c._count?.products ?? 0 },
  };
}

export function mapVariant(v) {
  if (!v) return v;
  return {
    ...v,
    price: v.price !== null && v.price !== undefined ? Number(v.price) : undefined,
    mrp: v.mrp !== null && v.mrp !== undefined ? Number(v.mrp) : undefined,
    stock: Number(v.stock ?? 0),
    colorHex: v.color_hex || null,
    // This colour's own pictures; empty means the product's gallery is used.
    images: v.images || [],
  };
}

export function mapProduct(p) {
  if (!p) return p;
  const images = p.images || [];
  return {
    ...p,
    categoryId: p.category_id,
    categorySlug: p.category?.slug,
    // How this product's category names its choices (Size, Storage, Pack...), for labels on the product page.
    variantSetup: p.category?.variant_setup || null,
    category: p.category?.name || p.category,
    image: images[0] || FALLBACK_IMAGE,
    images,
    price: Number(p.price),
    mrp: Number(p.mrp),
    discount: p.discount ?? (p.mrp > p.price ? Math.round(((p.mrp - p.price) / p.mrp) * 100) : 0),
    isNew: p.is_new,
    lifestyleBadges: p.tags || [],
    rating: p.rating ?? 0,
    reviewsCount: p.reviews_count ?? 0,
    stockCount: p.stock_count ?? 0,
    inStock: p.in_stock ?? true,
    variants: (p.variants || []).map(mapVariant),
    rolloverImage: p.rollover_image,
    authenticityGrade: p.authenticity_grade,
    localStoreAvailable: p.local_store_available,
    localStoreName: p.local_store_name || 'Local Store Pickup',
    expressPincodes: p.express_pincodes || [],
    hotspots: p.hotspots || [],
    spinImages: p.spin_images || [],
    codAvailable: p.cod_available ?? true,
    reelVideoUrl: p.reel_video_url || null,
    reelCaption: p.reel_caption || '',
    hasReel: p.has_reel ?? Boolean(p.reel_video_url),
    // Custom selection options (portion, add-ons, ...): this product's own, or its category's.
    optionGroups: p.option_groups || [],
    customOptions: p.custom_options ?? null,
    // This product's own delivery setting; empty means "use the category's".
    deliveryProfile: p.delivery_profile || '',
    prepMinutes: p.prep_minutes ?? '',
    deliveryInfo: p.delivery_info || { profile: null, prep_minutes: 0 },
    // The "all details" content: formatted description, specification table
    // ([{ title, rows: [{ label, value }] }]) and the manufacturer panel.
    descriptionHtml: p.description_html || '',
    specifications: p.specifications || [],
    manufacturer: p.manufacturer || {},
    // The shop it is sold by, for the "Sold by" line and the one-shop basket.
    shopId: p.seller?.id || null,
    shopSlug: p.seller?.slug || null,
    soldBy: p.seller?.display_name || null,
  };
}

// Laravel's real order status vocabulary (replaces the old mismatched
// 'New'/'Confirmed'/... strings that never matched what got stored).
export const ORDER_STAGES = ['PENDING', 'CONFIRMED', 'PACKED', 'SHIPPED', 'OUT_FOR_DELIVERY', 'DELIVERED'];

export const STAGE_LABELS = {
  PENDING: 'Pending', CONFIRMED: 'Confirmed', PACKED: 'Packed', SHIPPED: 'Shipped',
  OUT_FOR_DELIVERY: 'Out for Delivery', DELIVERED: 'Delivered', CANCELLED: 'Cancelled',
};

export const RETURN_STATUS_LABELS = {
  REQUESTED: 'Requested', APPROVED: 'Approved', PICKUP_SCHEDULED: 'Pickup Scheduled',
  PICKED_UP: 'Picked Up', REFUNDED: 'Refunded', REJECTED: 'Rejected',
};

export function formatINR(value) {
  return `₹${Number(value || 0).toLocaleString('en-IN', { maximumFractionDigits: 2 })}`;
}

export function formatDate(value) {
  if (!value) return '';
  return new Date(value).toLocaleDateString('en-IN', { day: 'numeric', month: 'short', year: 'numeric' });
}

export function mapOrder(o) {
  if (!o) return o;
  const addr = o.shipping_address || {};
  return {
    ...o,
    id: o.order_number, // admin UI displays/keys by the human order number
    _id: o.id, // real UUID, used for API calls
    customerName: addr.name || o.user?.name || 'Guest',
    phone: addr.phone || o.user?.phone || '',
    address: [addr.line1, addr.line2].filter(Boolean).join(', '),
    city: addr.city,
    pincode: addr.pincode,
    totalAmount: Number(o.total_amount),
    paymentMethod: o.payment_method,
    paymentStatus: o.payment_status,
    status: o.status,
    createdAt: o.created_at ? new Date(o.created_at).toLocaleString('en-IN') : '',
    courier: o.courier,
    trackingNo: o.tracking_no,
    labelGenerated: o.label_generated,
    items: (o.items || []).map(item => ({
      title: item.product?.title || 'Product',
      qty: item.quantity,
      price: Number(item.price),
      picks: picksFromOrderItem(item.selected_options),
      // The shop that sold this line.
      seller: item.seller?.display_name || null,
    })),
    // The distinct shops with something in this order.
    shopNames: [...new Set((o.items || []).map(item => item.seller?.display_name).filter(Boolean))],
  };
}
