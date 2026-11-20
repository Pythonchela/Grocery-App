// The product form's data model, shared by the add-product page and the advanced editor:
// what a blank product looks like, how a saved product becomes form values, how form values
// become the API payload, and what is still missing before a product can go live.
//
// Fields the add-product page does not show (360° frames, hotspots, hover photo, SEO text,
// pickup details...) still travel through here untouched, so editing a product on the page
// never wipes what was set in the advanced editor.

import { currentKind } from './storeKind.js';

export const EMPTY_VARIANT = { color: '', colorHex: '', size: '', sku: '', stock: currentKind.defaultStock, price: '', mrp: '' };

export const EMPTY_FORM = {
  title: '',
  slug: '',
  categoryId: '',
  brand: '',
  price: '',
  mrp: '',
  isNew: false,
  status: 'ACTIVE',
  authenticityGrade: '',
  // 'veg' | 'non_veg' | 'egg' | '' (not set). Only the food and grocery app asks for it.
  diet: '',
  image: '',
  rolloverImage: '',
  gallery: [],
  hotspots: [],
  spinImages: [],
  lifestyleBadges: [],
  variants: [{ ...EMPTY_VARIANT }],
  localStoreAvailable: true,
  localStoreName: '',
  expressPincodes: [],
  features: [],
  seoDescription: '',
  description: '',
  descriptionHtml: '',
  specifications: [],
  manufacturer: {},
  reelVideoUrl: '',
  reelCaption: '',
  // 'inherit' = the category's option template, 'custom' = this product's own list, 'none' = no options.
  optionMode: 'inherit',
  customOptions: [],
  deliveryProfile: '',
  prepMinutes: '',
  weightGrams: '',
  lengthCm: '',
  widthCm: '',
  heightCm: '',
  requiresVehicle: currentKind.defaultVehicle,
  codAvailable: true,
};

export const autoSlug = (title) =>
  String(title || '').trim().toLowerCase().replace(/\s+/g, '-').replace(/[^a-z0-9-]/g, '').replace(/^-+|-+$/g, '');

/** Old products have only plain text; show it in the editor as paragraphs. */
export function plainToHtml(text) {
  const esc = (t) => t.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  return String(text || '')
    .split(/\n{2,}/)
    .map((para) => para.trim())
    .filter(Boolean)
    .map((para) => `<p>${esc(para).replace(/\n/g, '<br>')}</p>`)
    .join('');
}

const clone = (v) => JSON.parse(JSON.stringify(v));

/** A product as returned by mapProduct() -> the form's values. */
export function formFromProduct(product) {
  if (!product) return clone(EMPTY_FORM);
  const images = product.images || [];
  return {
    title: product.title || '',
    slug: product.slug || '',
    categoryId: product.categoryId || '',
    brand: product.brand || '',
    price: product.price?.toString() || '',
    mrp: product.mrp?.toString() || '',
    isNew: product.isNew ?? false,
    status: product.status || 'ACTIVE',
    authenticityGrade: product.authenticityGrade || '',
    diet: product.diet || '',
    // Not product.image: for a product without photos that is the storefront's stand-in picture.
    image: images[0] || '',
    rolloverImage: product.rolloverImage || '',
    gallery: images.slice(1),
    hotspots: clone(product.hotspots || []),
    spinImages: [...(product.spinImages || [])],
    lifestyleBadges: product.lifestyleBadges || [],
    variants: product.variants?.length
      ? product.variants.map((v) => ({
          id: v.id,
          color: v.color || '',
          colorHex: v.colorHex || '',
          size: v.size || '',
          sku: v.sku || '',
          stock: v.stock?.toString() ?? '0',
          price: v.price?.toString() ?? '',
          mrp: v.mrp?.toString() ?? '',
          images: v.images || [],
        }))
      : [{ ...EMPTY_VARIANT }],
    localStoreAvailable: product.localStoreAvailable ?? true,
    localStoreName: product.local_store_name || '',
    expressPincodes: [...(product.expressPincodes || [])],
    features: [...(product.features || [])],
    description: product.description || '',
    descriptionHtml: product.descriptionHtml || plainToHtml(product.description),
    specifications: clone(product.specifications || []),
    manufacturer: { ...(product.manufacturer || {}) },
    seoDescription: product.meta_description || product.metaDescription || '',
    reelVideoUrl: product.reelVideoUrl || '',
    reelCaption: product.reelCaption || '',
    optionMode: Array.isArray(product.customOptions)
      ? (product.customOptions.length ? 'custom' : 'none')
      : 'inherit',
    customOptions: Array.isArray(product.customOptions) ? clone(product.customOptions) : [],
    deliveryProfile: product.deliveryProfile || '',
    prepMinutes: (product.prepMinutes ?? '').toString(),
    weightGrams: (product.weight_grams ?? '').toString(),
    lengthCm: (product.length_cm ?? '').toString(),
    widthCm: (product.width_cm ?? '').toString(),
    heightCm: (product.height_cm ?? '').toString(),
    requiresVehicle: Boolean(product.requires_vehicle),
    codAvailable: product.codAvailable ?? true,
  };
}

/** Photos per colour: every size of a colour shows the same pictures. Keyed by lower-cased colour. */
export function colourPhotosOf(variants) {
  const out = {};
  for (const v of variants || []) {
    const name = (v.color || '').trim();
    if (!name) continue;
    const key = name.toLowerCase();
    if (!(key in out)) out[key] = { name, photos: [] };
    if (!out[key].photos.length && (v.images || []).length) out[key].photos = v.images;
  }
  return out;
}

const intOrNull = (s) => (s === '' || s == null ? null : parseInt(s, 10) || null);

/** Form values -> the body for POST/PUT /products. */
export function payloadFromForm(form) {
  // A draft can be saved with only a name and category; the server refuses to publish one
  // without a real price, so an empty price is stored as 0, never as NaN.
  const priceNum = Number.isFinite(parseFloat(form.price)) ? parseFloat(form.price) : 0;
  const mrpNum = Number.isFinite(parseFloat(form.mrp)) ? parseFloat(form.mrp) : priceNum;
  const photos = colourPhotosOf(form.variants);

  return {
    title: form.title.trim(),
    slug: form.slug || autoSlug(form.title),
    description_html: form.descriptionHtml || null,
    ...(form.descriptionHtml ? {} : { description: '' }),
    specifications: form.specifications,
    manufacturer: form.manufacturer,
    category_id: form.categoryId,
    brand: form.brand || null,
    price: priceNum,
    mrp: mrpNum,
    is_new: form.isNew,
    status: form.status,
    tags: form.lifestyleBadges,
    features: form.features,
    images: [form.image, ...form.gallery].filter(Boolean),
    rollover_image: form.rolloverImage || null,
    authenticity_grade: form.authenticityGrade || null,
    diet: form.diet || null,
    local_store_available: form.localStoreAvailable,
    local_store_name: form.localStoreName || null,
    express_pincodes: form.expressPincodes,
    hotspots: form.hotspots,
    spin_images: form.spinImages,
    meta_description: form.seoDescription || null,
    reel_video_url: (form.reelVideoUrl || '').trim() || null,
    reel_caption: (form.reelCaption || '').trim() || null,
    delivery_profile: form.deliveryProfile || null,
    prep_minutes: form.prepMinutes === '' ? null : parseInt(form.prepMinutes, 10) || 0,
    weight_grams: intOrNull(form.weightGrams),
    length_cm: intOrNull(form.lengthCm),
    width_cm: intOrNull(form.widthCm),
    height_cm: intOrNull(form.heightCm),
    requires_vehicle: form.requiresVehicle,
    cod_available: form.codAvailable,
    // null = inherit the category template; [] = none; a list = this product's own.
    custom_options: form.optionMode === 'inherit' ? null : form.optionMode === 'none' ? [] : form.customOptions,
    variants: form.variants.map((v) => ({
      // An existing variant is sent with its id, so the server updates it in place (keeping its
      // order history) instead of inserting a duplicate.
      ...(v.id ? { id: v.id } : {}),
      color: v.color || null,
      color_hex: v.colorHex || null,
      size: v.size || null,
      sku: v.sku || null,
      stock: parseInt(v.stock, 10) || 0,
      price: v.price ? parseFloat(v.price) : null,
      mrp: v.mrp ? parseFloat(v.mrp) : null,
      images: (v.color && photos[v.color.trim().toLowerCase()]?.photos) || [],
    })),
  };
}

/** True when the product has more than one buyable combination, or one that is named. */
export function hasVariantOptions(variants) {
  if (!variants || variants.length === 0) return false;
  if (variants.length > 1) return true;
  const v = variants[0];
  const plain = (s) => !s || /^(standard|free size)$/i.test(String(s).trim());
  return !(plain(v.color) && plain(v.size));
}

/**
 * What is missing before this product can go live. `required` blocks publishing (the server
 * would refuse it too); `suggested` is worth doing but never blocks.
 */
export function readiness(form, kind = currentKind) {
  const required = [];
  const suggested = [];
  const price = parseFloat(form.price);
  const mrp = parseFloat(form.mrp);

  if (!form.title.trim()) required.push({ step: 'basics', text: 'Add a product name' });
  if (!form.categoryId) required.push({ step: 'basics', text: 'Choose a category' });
  if (!form.image) required.push({ step: 'photos', text: 'Add at least one photo' });
  if (!(price > 0)) required.push({ step: 'price', text: 'Set a selling price above zero' });
  if (Number.isFinite(mrp) && Number.isFinite(price) && mrp > 0 && mrp < price) {
    required.push({ step: 'price', text: 'The printed price (MRP) cannot be lower than the selling price' });
  }

  // Heavy items: the truck is booked from the weight and size, and the default parcel size is wrong for them.
  if (kind.needs.weight && !(parseInt(form.weightGrams, 10) > 0)) {
    required.push({ step: 'delivery', text: 'Add the packed weight, so the right vehicle is booked' });
  }
  if (kind.needs.dimensions && ![form.lengthCm, form.widthCm, form.heightCm].every((v) => parseInt(v, 10) > 0)) {
    required.push({ step: 'delivery', text: 'Add the packed size (length, width and height)' });
  }

  const stock = form.variants.reduce((n, v) => n + (parseInt(v.stock, 10) || 0), 0);
  if (stock === 0) {
    suggested.push({ step: 'price', text: kind.id === 'instant' ? 'Stock is 0, so it shows as sold out' : 'Stock is 0, so shoppers will see it as sold out' });
  }
  if (kind.diet && !form.diet) suggested.push({ step: 'basics', text: 'Mark it veg or non-veg' });
  if (kind.delivery.weight === 'suggested' && !form.weightGrams) {
    suggested.push({ step: 'delivery', text: 'Add a weight so delivery prices are right' });
  }
  if (!form.descriptionHtml || !form.descriptionHtml.replace(/<[^>]*>/g, '').trim()) {
    suggested.push({ step: 'basics', text: 'Add a short description' });
  }
  return { required, suggested, ready: required.length === 0 };
}

/** The sizes and colours a product's rows already use, in the order they first appear. */
export function pickedOptions(variants) {
  const sizes = [];
  const colours = [];
  const plain = (s) => !s || /^(standard|free size)$/i.test(String(s).trim());
  for (const v of variants || []) {
    const size = String(v.size || '').trim();
    const colour = String(v.color || '').trim();
    if (!plain(size) && !sizes.some((s) => s.toLowerCase() === size.toLowerCase())) sizes.push(size);
    if (!plain(colour) && !colours.some((c) => c.name.toLowerCase() === colour.toLowerCase())) {
      colours.push({ name: colour, hex: v.colorHex || '' });
    }
  }
  return { sizes, colours };
}

/**
 * Rows for the sizes and colours picked: one per size and colour together (or one per size, or one per
 * colour). A row that already exists keeps its stock, price, SKU and photos; new ones start with the
 * default stock. With nothing picked, a single plain row is left.
 */
export function rebuildVariants(existing, sizes, colours) {
  const key = (size, colour) => `${String(size || '').trim().toLowerCase()}|${String(colour || '').trim().toLowerCase()}`;
  const byKey = new Map((existing || []).map((v) => [key(v.size, v.color), v]));
  const reuse = (size, colour, hex) => {
    const found = byKey.get(key(size, colour));
    if (found) return hex && !found.colorHex ? { ...found, colorHex: hex } : found;
    return { ...EMPTY_VARIANT, size: size || '', color: colour || '', colorHex: hex || '' };
  };

  if (sizes.length && colours.length) return sizes.flatMap((s) => colours.map((c) => reuse(s, c.name, c.hex)));
  if (sizes.length) return sizes.map((s) => reuse(s, '', ''));
  if (colours.length) return colours.map((c) => reuse('', c.name, c.hex));
  const first = (existing || [])[0];
  return [first ? { ...first, size: '', color: '', colorHex: '', price: '', mrp: '', images: [] } : { ...EMPTY_VARIANT }];
}
