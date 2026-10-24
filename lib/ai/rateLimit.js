/**
 * Rate limiting for the AI routes.
 *
 * These endpoints are unauthenticated by design — a shopper asks the assistant
 * for help before signing in — but each request runs a frontier model through a
 * tool loop, so an unlimited one is an open tap on the API bill. The Laravel API
 * has named limiters on every endpoint that costs money; these routes had none
 * at all, which made them the cheapest way to spend someone else's budget.
 *
 * Two ceilings, because they stop different things: a per-caller limit stops one
 * host looping, and a global limit stops a spread-out flood from taking the bill
 * with it.
 *
 * In-process, so each server instance counts separately — with several instances
 * behind a load balancer the effective limit is this times the instance count.
 * That is deliberate for now: it's a fixed, known multiple, and it needs no
 * infrastructure. Move the counters to Redis when you run more than one box and
 * want the ceiling to mean exactly what it says.
 */

const WINDOW_MS = 60_000;

/** Per caller, per window. Generous for a conversation, useless for a script. */
const PER_CALLER = 10;

/** Across all callers, per window. The backstop on total spend. */
const GLOBAL = 200;

const callers = new Map();
let globalHits = [];

function prune(list, now) {
  return list.filter((t) => now - t < WINDOW_MS);
}

/**
 * Best-effort caller identity. `x-forwarded-for` is spoofable, so this is a
 * speed bump against casual abuse rather than an access control — the global
 * ceiling is what actually bounds the spend.
 */
export function callerKey(request) {
  const forwarded = request.headers.get('x-forwarded-for');
  if (forwarded) return forwarded.split(',')[0].trim();
  return request.headers.get('x-real-ip') || 'unknown';
}

/**
 * @returns {{ok: true} | {ok: false, scope: 'caller'|'global', retryAfter: number}}
 */
export function checkRateLimit(request) {
  const now = Date.now();
  const key = callerKey(request);

  globalHits = prune(globalHits, now);
  if (globalHits.length >= GLOBAL) {
    return { ok: false, scope: 'global', retryAfter: retryAfterFrom(globalHits, now) };
  }

  const mine = prune(callers.get(key) || [], now);
  if (mine.length >= PER_CALLER) {
    callers.set(key, mine);
    return { ok: false, scope: 'caller', retryAfter: retryAfterFrom(mine, now) };
  }

  mine.push(now);
  callers.set(key, mine);
  globalHits.push(now);

  // Bound the map so a stream of distinct forwarded-for values can't grow it
  // without limit — that would just move the denial-of-service to memory.
  if (callers.size > 5000) {
    for (const [k, v] of callers) {
      if (prune(v, now).length === 0) callers.delete(k);
    }
  }

  return { ok: true };
}

function retryAfterFrom(hits, now) {
  const oldest = hits[0] ?? now;
  return Math.max(1, Math.ceil((WINDOW_MS - (now - oldest)) / 1000));
}

/** The 429 both AI routes return, so the shape stays identical across them. */
export function rateLimitResponse(result) {
  return Response.json(
    {
      error:
        result.scope === 'global'
          ? 'The assistant is busy right now. Please try again in a moment.'
          : 'You are sending messages too quickly. Please wait a moment.',
      code: 'rate_limited',
    },
    { status: 429, headers: { 'Retry-After': String(result.retryAfter) } }
  );
}
