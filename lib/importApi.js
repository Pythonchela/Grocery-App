const API_BASE = process.env.NEXT_PUBLIC_API_URL || 'http://127.0.0.1:8000/api/v1';

/**
 * Sends one group of files (and/or pasted text) to be read into draft products.
 * Resolves to the server's `data`; rejects with a message fit to show.
 */
export async function parseImport({ files = [], text = '', hint = '', defaultStock = 10, categoryId = '' }, token) {
  const body = new FormData();
  files.forEach((f) => body.append('files[]', f));
  if (text.trim()) body.append('text', text);
  if (hint.trim()) body.append('hint', hint.trim());
  body.append('default_stock', String(defaultStock));
  if (categoryId) body.append('category_id', categoryId);

  let res;
  try {
    res = await fetch(`${API_BASE}/admin/products/import/parse`, {
      method: 'POST',
      headers: { Accept: 'application/json', Authorization: `Bearer ${token}` },
      body,
    });
  } catch {
    throw new Error('Could not reach the server. Check the connection and try again.');
  }

  const json = await res.json().catch(() => ({}));

  if (!res.ok) {
    if (res.status === 413) throw new Error('These files are too large to send at once. Upload fewer or smaller files.');
    if (res.status === 429) throw new Error('Too many requests. Wait a minute and try again.');
    const detail = json.errors ? Object.values(json.errors).flat().join(' ') : '';
    throw new Error(detail || json.message || `The server could not read this (error ${res.status}).`);
  }

  return json.data;
}
