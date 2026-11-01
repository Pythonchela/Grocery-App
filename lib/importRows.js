/**
 * The product importer's screen logic, kept apart from the components so it can be
 * tested: how uploaded files are grouped into requests, how rows are judged ready,
 * and how a parsed row fills the product form.
 */

const TABLES = ['csv', 'tsv', 'xlsx', 'json'];
const PICTURES = ['jpg', 'jpeg', 'png', 'webp'];

/** Photos per request. The server shrinks them, but each one still has to be read. */
export const PHOTOS_PER_REQUEST = 6;

/** What the file picker offers. */
export const ACCEPT = '.pdf,.docx,.xlsx,.csv,.tsv,.txt,.md,.json,.jpg,.jpeg,.png,.webp';

export function extensionOf(file) {
  const name = file?.name || '';
  const dot = name.lastIndexOf('.');
  return dot === -1 ? '' : name.slice(dot + 1).toLowerCase();
}

export const isPicture = (file) => PICTURES.includes(extensionOf(file));
export const isTable = (file) => TABLES.includes(extensionOf(file));

/**
 * Groups files into the requests to send. Each request stays inside the server's
 * time limit, and the screen can show progress between them.
 *
 *  - A spreadsheet or CSV is read on its own: it is exact and can be long.
 *  - Photos go in groups of six.
 *  - With `together`, photos and one or two documents travel in one request, so a
 *    price list can be matched to the pictures of the products it prices.
 *  - Pasted text is its own request unless it travels with the photos.
 */
export function planBatches(files, text = '', { together = false } = {}) {
  const tables = files.filter(isTable);
  const pictures = files.filter(isPicture);
  const documents = files.filter((f) => !isTable(f) && !isPicture(f));
  const batches = tables.map((f) => ({ files: [f], text: '' }));
  const pasted = text.trim();

  const canJoin = together && pictures.length > 0 && pictures.length <= PHOTOS_PER_REQUEST + 2
    && documents.length + (pasted ? 1 : 0) <= 2;

  if (canJoin) {
    batches.push({ files: [...documents, ...pictures], text: pasted });
    return batches;
  }

  documents.forEach((f) => batches.push({ files: [f], text: '' }));
  if (pasted) batches.push({ files: [], text: pasted });
  for (let i = 0; i < pictures.length; i += PHOTOS_PER_REQUEST) {
    batches.push({ files: pictures.slice(i, i + PHOTOS_PER_REQUEST), text: '' });
  }

  return batches;
}

/** Joins the answers of several requests into one list, numbered afresh. */
export function mergeResults(results) {
  const rows = [];
  const problems = [];
  const notes = [];
  const drivers = new Set();
  let categories = [];

  results.forEach((r) => {
    if (!r) return;
    (r.rows || []).forEach((row) => rows.push({ ...row }));
    problems.push(...(r.problems || []));
    notes.push(...(r.notes || []));
    String(r.driver || '').split(' + ').filter((d) => d && d !== 'none').forEach((d) => drivers.add(d));
    if (r.categories?.length) categories = r.categories;
  });

  rows.forEach((row, i) => { row.index = i; });

  return {
    rows,
    categories,
    problems: [...new Set(problems)],
    notes: [...new Set(notes)],
    drivers: [...drivers],
  };
}

/** Whether the server will accept this row as it stands. */
export function isReady(row) {
  return Boolean(row.title && row.title.trim() && row.price != null && row.price !== '' && row.mrp != null && row.mrp !== '' && row.category_id);
}

/**
 * How much a row needs the owner's eyes: 'check' when a number is doubtful or a
 * required field is missing, 'note' when there is only something to be aware of,
 * 'ok' otherwise.
 */
export function attention(row) {
  if (!isReady(row)) return 'check';
  const conf = row.confidence || {};
  if ((conf.price != null && conf.price < 0.5) || (conf.mrp != null && conf.mrp < 0.5 && row.mrp !== row.price) || (conf.title != null && conf.title < 0.5)) {
    return 'check';
  }
  if (row.possible_duplicate) return 'check';
  return (row.issues || []).length ? 'note' : 'ok';
}

/** A row the owner has not looked at, and the first thing to look at. */
export function sortedForReview(rows) {
  const order = { check: 0, note: 1, ok: 2 };
  return [...rows].sort((a, b) => order[attention(a)] - order[attention(b)] || a.index - b.index);
}

/** The body the commit endpoint takes, from the rows the owner left ticked. */
export function commitBody(rows, status) {
  return {
    status,
    rows: rows.filter((r) => r.include && isReady(r)).map((r) => ({
      title: r.title.trim(),
      description: r.description || null,
      brand: r.brand || null,
      price: Number(r.price),
      mrp: Number(r.mrp),
      category_id: r.category_id,
      images: r.images || [],
      tags: r.tags || [],
      features: (r.features || []).filter(Boolean),
      specifications: r.specifications || [],
      manufacturer: r.manufacturer || {},
      weight_grams: r.weight_grams || null,
      length_cm: r.length_cm || null,
      width_cm: r.width_cm || null,
      height_cm: r.height_cm || null,
      variants: (r.variants || []).map((v) => ({
        color: v.color || null,
        size: v.size || null,
        sku: v.sku || null,
        stock: Number.isFinite(Number(v.stock)) ? Math.max(0, Math.round(Number(v.stock))) : 0,
        price: v.price === '' || v.price == null ? null : Number(v.price),
        mrp: v.mrp === '' || v.mrp == null ? null : Number(v.mrp),
      })),
    })),
  };
}

const text = (v) => (v == null ? '' : String(v));

function plainToHtml(value) {
  const esc = (t) => t.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  return text(value)
    .split(/\n{2,}/)
    .map((p) => p.trim())
    .filter(Boolean)
    .map((p) => `<p>${esc(p).replace(/\n/g, '<br>')}</p>`)
    .join('');
}

/**
 * Fills the product form from a parsed row, touching only what is still empty:
 * what the owner has already typed is never overwritten.
 *
 * @returns {{ form: object, filled: string[] }} the new form and the names of the parts filled
 */
export function formFromImportRow(form, row) {
  const next = { ...form };
  const filled = [];
  const take = (label, key, value) => {
    const current = next[key];
    const empty = Array.isArray(current) ? current.length === 0 : text(current).trim() === '';
    const has = Array.isArray(value) ? value.length > 0 : text(value).trim() !== '';
    if (empty && has) {
      next[key] = value;
      filled.push(label);
    }
  };

  take('title', 'title', row.title);
  take('brand', 'brand', row.brand);
  take('category', 'categoryId', row.category_id);
  take('price', 'price', row.price != null ? String(row.price) : '');
  take('MRP', 'mrp', row.mrp != null ? String(row.mrp) : '');
  take('description', 'description', row.description);
  if (!text(form.descriptionHtml).trim() && text(row.description).trim()) {
    next.descriptionHtml = plainToHtml(row.description);
  }
  take('features', 'features', row.features || []);
  take('specifications', 'specifications', row.specifications || []);
  take('tags', 'lifestyleBadges', (row.tags || []).slice(0, 6));
  take('weight', 'weightGrams', row.weight_grams ? String(row.weight_grams) : '');
  take('length', 'lengthCm', row.length_cm ? String(row.length_cm) : '');
  take('width', 'widthCm', row.width_cm ? String(row.width_cm) : '');
  take('height', 'heightCm', row.height_cm ? String(row.height_cm) : '');

  if (Object.keys(row.manufacturer || {}).length && Object.keys(form.manufacturer || {}).length === 0) {
    next.manufacturer = { ...row.manufacturer };
    filled.push('manufacturer details');
  }

  const [main, ...rest] = row.images || [];
  take('main photo', 'image', main || '');
  if (rest.length && (form.gallery || []).length === 0) {
    next.gallery = rest;
    filled.push('gallery photos');
  }

  // Variants replace only the untouched starter row.
  const pristine = (form.variants || []).every((v) => !text(v.color).trim() && !text(v.size).trim() && !text(v.sku).trim());
  const variants = (row.variants || []).filter((v) => v.color || v.size);
  if (pristine && variants.length) {
    next.variants = variants.map((v) => ({
      color: text(v.color),
      colorHex: '',
      size: text(v.size),
      sku: text(v.sku),
      stock: text(v.stock ?? 0),
      price: v.price != null ? String(v.price) : '',
      mrp: v.mrp != null ? String(v.mrp) : '',
      images: [],
    }));
    filled.push('colours and sizes');
  }

  return { form: next, filled };
}
