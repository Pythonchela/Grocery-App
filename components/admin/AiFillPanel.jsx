'use client';

import React, { useState } from 'react';
import { AlertTriangle, CheckCircle2, Loader2, Sparkles, X } from 'lucide-react';
import { parseImport } from '../../lib/importApi';
import { ACCEPT, PHOTOS_PER_REQUEST, isReady } from '../../lib/importRows';

/**
 * "Fill from photos or a document" for the product form. The owner adds photos of the
 * product, a supplier's PDF or Word sheet, or pastes the details, and the form is filled
 * in. Only fields still empty are filled: what has been typed is never overwritten.
 */
export default function AiFillPanel({ token, onFill }) {
  const [open, setOpen] = useState(false);
  const [files, setFiles] = useState([]);
  const [text, setText] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [outcome, setOutcome] = useState(null); // { filled, issues, more }

  const run = async () => {
    setBusy(true); setError(''); setOutcome(null);
    try {
      const data = await parseImport({ files, text }, token);
      const row = data.rows?.[0];

      if (!row) {
        setError(data.problems?.join(' ') || 'No product was found in that. Try a clearer photo or add some text.');
        return;
      }

      const { filled } = onFill(row);
      setOutcome({
        filled,
        issues: [...(data.problems || []), ...(row.issues || [])],
        more: data.rows.length - 1,
        ready: isReady({ ...row }),
      });
      setFiles([]); setText('');
    } catch (err) {
      setError(err.message);
    } finally { setBusy(false); }
  };

  if (!open) {
    return (
      <button
        type="button"
        onClick={() => setOpen(true)}
        className="w-full flex items-center justify-center gap-2 border-2 border-dashed border-accent/50 text-accent rounded-card py-3 text-xs font-black hover:bg-accent/5 transition"
      >
        <Sparkles className="w-4 h-4" /> Fill this form from photos or a document
      </button>
    );
  }

  return (
    <div className="border border-accent/40 bg-accent/5 rounded-card p-4 space-y-3">
      <div className="flex items-center justify-between gap-3">
        <h4 className="text-xs font-black text-ink flex items-center gap-2"><Sparkles className="w-4 h-4 text-accent" /> Fill from photos or a document</h4>
        <button type="button" onClick={() => setOpen(false)} aria-label="Close" className="text-ink-subtle hover:text-ink"><X className="w-4 h-4" /></button>
      </div>

      <p className="text-[11px] text-ink-muted font-medium">
        Add up to {PHOTOS_PER_REQUEST} photos of this product, a supplier sheet (PDF, Word, Excel), or paste the details.
        Only empty fields are filled. Check everything before saving.
      </p>

      <input
        type="file"
        multiple
        accept={ACCEPT}
        aria-label="Photos or document"
        onChange={(e) => setFiles(Array.from(e.target.files || []).slice(0, PHOTOS_PER_REQUEST))}
        className="block w-full text-[11px] file:mr-3 file:rounded-control file:border-0 file:bg-primary file:text-on-primary file:px-3 file:py-1.5 file:font-bold"
      />
      <textarea
        value={text}
        onChange={(e) => setText(e.target.value)}
        rows={3}
        aria-label="Paste product details"
        placeholder="Or paste the details here"
        className="w-full bg-surface border border-line rounded-card px-3 py-2 text-[11px] font-medium focus:outline-none focus:border-accent resize-y"
      />

      <button
        type="button"
        onClick={run}
        disabled={busy || (files.length === 0 && !text.trim())}
        className="btn-primary text-xs py-2 px-4 disabled:opacity-50 inline-flex items-center gap-2"
      >
        {busy ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : <Sparkles className="w-3.5 h-3.5" />}
        {busy ? 'Reading…' : 'Read and fill'}
      </button>

      {error && (
        <p role="alert" className="text-[11px] font-bold text-danger flex items-start gap-1.5"><AlertTriangle className="w-3.5 h-3.5 shrink-0 mt-0.5" /> {error}</p>
      )}

      {outcome && (
        <div role="status" className="space-y-1.5">
          <p className="text-[11px] font-bold text-success flex items-start gap-1.5">
            <CheckCircle2 className="w-3.5 h-3.5 shrink-0 mt-0.5" />
            {outcome.filled.length ? `Filled: ${outcome.filled.join(', ')}.` : 'Everything it found was already filled in.'}
          </p>
          {outcome.more > 0 && (
            <p className="text-[11px] font-semibold text-warning">
              {outcome.more} more product{outcome.more === 1 ? ' was' : 's were'} in there. This form took the first. Use Import for the rest.
            </p>
          )}
          {outcome.issues.map((i) => (
            <p key={i} className="text-[11px] font-semibold text-warning flex items-start gap-1.5"><AlertTriangle className="w-3 h-3 shrink-0 mt-0.5" /> {i}</p>
          ))}
        </div>
      )}
    </div>
  );
}
