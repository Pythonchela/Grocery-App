import { getClient, MODEL, FALLBACK_BETA } from '../../../../lib/ai/client';
import { searchCatalog, getCategoryFilters } from '../../../../lib/ai/catalog';
import { checkRateLimit, rateLimitResponse } from '../../../../lib/ai/rateLimit';

export const runtime = 'nodejs';

/**
 * Intent search: a sentence in any language becomes catalog filters.
 *
 * The existing Postgres search is good at what it is — tsvector ranking plus a
 * trigram fallback that survives typos — but it matches *words against product
 * text*. "मेरी माँ के लिए ₹500 से कम का तोहफा" shares no words with any product
 * title, and neither does "something to keep my coffee warm at my desk". This
 * route resolves the sentence into the structured filters the shopper would
 * have picked by hand, then hands the actual retrieval back to Postgres.
 *
 * The model never sees the catalog here and never returns products — it only
 * produces filters. Retrieval stays in the database, so results are exactly the
 * rows the storefront's own filters would return.
 */
export async function POST(request) {
  const limit = checkRateLimit(request);
  if (!limit.ok) return rateLimitResponse(limit);

  let body;
  try {
    body = await request.json();
  } catch {
    return Response.json({ error: 'Invalid JSON body.' }, { status: 400 });
  }

  const query = typeof body?.query === 'string' ? body.query.trim() : '';
  if (!query) return Response.json({ error: 'query is required.' }, { status: 400 });

  const client = getClient();

  // Without a key this is still a working search box — it just falls back to
  // the plain keyword path instead of understanding the sentence.
  if (!client) {
    const result = await searchCatalog({ search: query, limit: body?.limit ?? 24 });
    return Response.json({ ...result, interpreted: null, ai: false });
  }

  try {
    const categories = await getCategoryFilters();

    const response = await client.beta.messages.create({
      model: MODEL,
      max_tokens: 1024,
      betas: [FALLBACK_BETA],
      fallbacks: 'default',
      system: `You turn a shopper's sentence into catalog filters for an Indian marketplace. Reply with JSON only — no prose, no code fences.

{"search": string|null, "category": string|null, "min_price": number|null, "max_price": number|null, "min_rating": number|null, "attributes": object, "sort": string|null, "notes": string|null}

- The sentence may be in any language (English, Hindi, Hinglish, Tamil, Bengali, …). Understand it in that language; emit filter VALUES in English, since that is how the catalog stores them.
- "search" is the product noun only — "running shoes", not the whole sentence. Null if the sentence names no product type.
- Prices are rupees. "under 500" → max_price 500. "budget"/"cheap" with no number → leave null rather than inventing a threshold.
- "category" must be a slug from the provided list, or null. Never invent one.
- "attributes" keys must be filter group ids from the chosen category, values from that group's options. Empty object if none apply.
- Read intent, not just nouns: "gift for my mother under ₹500" is a price ceiling plus a recipient, and the recipient may imply a category. "something to keep my coffee warm" is a product type the shopper hasn't named — infer it.
- "notes" is one short line, in the shopper's own language, on how you read the request. Null if it was unambiguous.`,
      messages: [
        {
          role: 'user',
          content: `CATEGORIES AND THEIR FILTER GROUPS:\n${JSON.stringify(categories)}\n\nSHOPPER'S QUERY:\n${query}`,
        },
      ],
    });

    if (response.stop_reason === 'refusal') {
      const result = await searchCatalog({ search: query, limit: body?.limit ?? 24 });
      return Response.json({ ...result, interpreted: null, ai: false });
    }

    const raw = response.content
      .filter((b) => b.type === 'text')
      .map((b) => b.text)
      .join('')
      .trim();

    let filters;
    try {
      // Tolerate a stray fence even though the prompt forbids one — a parse
      // failure here shouldn't cost the shopper their search.
      filters = JSON.parse(raw.replace(/^```(?:json)?\s*|\s*```$/g, ''));
    } catch {
      const result = await searchCatalog({ search: query, limit: body?.limit ?? 24 });
      return Response.json({ ...result, interpreted: null, ai: false });
    }

    const validSlugs = new Set(categories.map((c) => c.slug));
    const category = filters.category && validSlugs.has(filters.category) ? filters.category : undefined;

    const result = await searchCatalog({
      search: filters.search || undefined,
      category,
      min_price: filters.min_price ?? undefined,
      max_price: filters.max_price ?? undefined,
      min_rating: filters.min_rating ?? undefined,
      attributes: filters.attributes && typeof filters.attributes === 'object' ? filters.attributes : {},
      sort: filters.sort || undefined,
      limit: body?.limit ?? 24,
    });

    // A confidently-wrong interpretation returning nothing is worse than a
    // loose keyword match, so fall back rather than showing an empty page.
    if (result.total_matches === 0) {
      const plain = await searchCatalog({ search: query, limit: body?.limit ?? 24 });
      if (plain.total_matches > 0) {
        return Response.json({ ...plain, interpreted: filters, ai: true, relaxed: true });
      }
    }

    return Response.json({ ...result, interpreted: filters, ai: true });
  } catch (err) {
    console.error('[ai/search]', err);
    const result = await searchCatalog({ search: query, limit: body?.limit ?? 24 });
    return Response.json({ ...result, interpreted: null, ai: false });
  }
}
