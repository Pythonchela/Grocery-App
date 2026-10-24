import Anthropic from '@anthropic-ai/sdk';

/** The model every AI feature here runs on. */
export const MODEL = 'claude-opus-5';

/**
 * Opting into server-side fallbacks: if a safety classifier declines a request,
 * the API retries it on a fallback model in the same call rather than handing
 * back a refusal. Shopping queries are not the kind of thing classifiers
 * usually decline, but a refusal here surfaces to a shopper as a dead
 * assistant, so the cheap insurance is worth taking.
 */
export const FALLBACK_BETA = 'server-side-fallback-2026-07-01';

/**
 * Returns null rather than throwing when no key is configured.
 *
 * The AI features are additive: without a key the storefront must still work,
 * the assistant must still open, and search must still return results — each
 * caller degrades to its non-AI path instead of surfacing a stack trace to a
 * shopper.
 */
export function getClient() {
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) return null;
  return new Anthropic({ apiKey });
}

export const MISSING_KEY_MESSAGE =
  'The AI assistant is not configured yet — ANTHROPIC_API_KEY is missing from the environment.';
