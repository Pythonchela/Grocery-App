import { betaTool } from '@anthropic-ai/sdk/helpers/beta/json-schema';
import { getClient, MODEL, FALLBACK_BETA, MISSING_KEY_MESSAGE } from '../../../../lib/ai/client';
import { searchCatalog, getCategoryFilters } from '../../../../lib/ai/catalog';
import { checkRateLimit, rateLimitResponse } from '../../../../lib/ai/rateLimit';

export const runtime = 'nodejs';

/**
 * The shopping concierge.
 *
 * Two rules do the real work here. First, it asks before it recommends — the
 * previous version answered every message with three products immediately,
 * which is what a search box already does; the point of a conversation is to
 * narrow the requirement first. Second, every product claim has to come back
 * from `search_products`, so the assistant can't invent an item or a price.
 *
 * Written against the model's defaults rather than around them: Opus 5 is
 * verbose and inclined to expand scope unless told otherwise, so conciseness
 * and staying-in-scope are stated explicitly instead of being trimmed later.
 */
const SYSTEM_PROMPT = `You are the shopping assistant for an Indian online marketplace. You help a shopper arrive at a small set of products that genuinely fit what they need.

## Ask before you recommend

A vague opening request ("something for my kitchen", "a gift", "shoes") is not enough to recommend against. Ask one or two short questions that would actually change which products qualify — budget, who it's for, the use case, a hard requirement — then search.

Ask about what the catalog can actually filter on. Call list_category_filters to see the filter groups defined for a category, and ask about those; they are the attributes this catalog records for that product type. Don't ask about attributes the catalog doesn't track — you won't be able to act on the answer.

Never ask more than two questions before searching. If the shopper has already given you enough to narrow sensibly, or tells you to just show them something, search immediately. A shopper who says "under 2000" and "for running" has given you enough — don't keep interviewing.

## Never invent products

Every product, price, rating and specification you mention must come from a search_products result in this conversation. You have no product knowledge of your own — this catalog's inventory is not something you can guess at. If a search returns nothing, say so plainly and suggest loosening a constraint; do not fill the gap with a plausible-sounding product.

Prices are Indian rupees. Write them as ₹1,299.

## Answering

Keep replies short — a couple of sentences around the products, not a catalogue description of each. The shopper can see the product cards; don't restate their titles and prices in prose. Say what distinguishes the options from each other and what you'd suggest, then stop.

Answer in the language the shopper writes in.

Recommend from what the search returned, at the scope they asked for. If nothing fits well, say that rather than presenting the closest three as though they do.`;

/** Guards against a stray client payload driving unbounded model spend. */
const MAX_HISTORY = 24;

export async function POST(request) {
  // Checked before anything else: the point is to refuse without spending, so
  // it has to come ahead of the model call and the catalog queries alike.
  const limit = checkRateLimit(request);
  if (!limit.ok) return rateLimitResponse(limit);

  const client = getClient();
  if (!client) {
    return Response.json({ error: MISSING_KEY_MESSAGE, code: 'ai_unconfigured' }, { status: 503 });
  }

  let body;
  try {
    body = await request.json();
  } catch {
    return Response.json({ error: 'Invalid JSON body.' }, { status: 400 });
  }

  const history = Array.isArray(body?.messages) ? body.messages.slice(-MAX_HISTORY) : [];
  if (history.length === 0) {
    return Response.json({ error: 'messages is required.' }, { status: 400 });
  }

  const messages = history
    .filter((m) => (m?.role === 'user' || m?.role === 'assistant') && typeof m.content === 'string')
    .map((m) => ({ role: m.role, content: m.content }));

  if (messages.length === 0 || messages[0].role !== 'user') {
    return Response.json({ error: 'Conversation must start with a user message.' }, { status: 400 });
  }

  // Products the model actually looked at this turn. The chat response is
  // prose, but the UI renders real cards — so the rows behind the answer are
  // collected here rather than re-parsed out of the model's text.
  const shownProducts = new Map();

  const searchProducts = betaTool({
    name: 'search_products',
    description:
      "Search the real product catalog. This is the only source of product facts — every product you mention must come from a result here. Filter as narrowly as what the shopper told you supports, using `attributes` for the per-category filter groups from list_category_filters. Returns the matching products plus total_matches, which is how many matched in total (results are capped).",
    inputSchema: {
      type: 'object',
      properties: {
        search: { type: 'string', description: 'Free text matched against title, brand and description.' },
        category: { type: 'string', description: 'Category slug from list_category_filters.' },
        brand: { type: 'string' },
        min_price: { type: 'number', description: 'Rupees.' },
        max_price: { type: 'number', description: 'Rupees.' },
        min_rating: { type: 'number' },
        in_stock: { type: 'boolean' },
        attributes: {
          type: 'object',
          description:
            "Per-category filters keyed by the filter group id, e.g. {\"fabric\": \"cotton\"}. A group's values are OR'd; separate groups are AND'd.",
          additionalProperties: true,
        },
        sort: { type: 'string', enum: ['price_asc', 'price_desc', 'rating', 'popularity', 'newest'] },
        limit: { type: 'number', description: 'Max products to return (default 8, cap 20).' },
      },
      required: [],
    },
    run: async (input) => {
      try {
        const result = await searchCatalog(input);
        for (const p of result.products) shownProducts.set(p.id, p);
        return JSON.stringify(result);
      } catch (err) {
        // Handed back as a tool result rather than thrown, so the model can
        // tell the shopper the catalog is unreachable instead of stalling.
        return JSON.stringify({ error: `Catalog unavailable: ${err.message}` });
      }
    },
  });

  const listCategoryFilters = betaTool({
    name: 'list_category_filters',
    description:
      "Lists the catalog's categories and, for each, the filter groups defined for that product type — the attributes this catalog actually records and can filter on. Call this before asking a shopper what they need in a category, so your questions match what you can filter by.",
    inputSchema: { type: 'object', properties: {}, required: [] },
    run: async () => {
      try {
        return JSON.stringify(await getCategoryFilters());
      } catch (err) {
        return JSON.stringify({ error: `Categories unavailable: ${err.message}` });
      }
    },
  });

  try {
    const finalMessage = await client.beta.messages.toolRunner({
      model: MODEL,
      max_tokens: 4096,
      system: SYSTEM_PROMPT,
      tools: [searchProducts, listCategoryFilters],
      messages,
      betas: [FALLBACK_BETA],
      fallbacks: 'default',
    });

    if (finalMessage.stop_reason === 'refusal') {
      return Response.json(
        { reply: "I can't help with that one — try asking about something in the store.", products: [] },
        { status: 200 }
      );
    }

    const reply = finalMessage.content
      .filter((block) => block.type === 'text')
      .map((block) => block.text)
      .join('')
      .trim();

    return Response.json({
      reply: reply || 'Sorry, I could not put together an answer for that.',
      products: [...shownProducts.values()],
    });
  } catch (err) {
    console.error('[ai/chat]', err);
    return Response.json({ error: 'The assistant could not answer just now.' }, { status: 502 });
  }
}
