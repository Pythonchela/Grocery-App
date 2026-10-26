'use client';

import React, { useState } from 'react';
import { BookOpen, ChevronDown, Copy, ExternalLink } from 'lucide-react';

/** Text in `backticks` is shown as code. Nothing else is interpreted. */
function Rich({ text }) {
  return String(text)
    .split(/(`[^`]+`)/g)
    .map((piece, i) =>
      piece.length > 2 && piece.startsWith('`') && piece.endsWith('`') ? (
        <code key={i} className="font-mono text-[0.9em] bg-surface-muted border border-line rounded px-1 py-0.5 break-words">
          {piece.slice(1, -1)}
        </code>
      ) : (
        <React.Fragment key={i}>{piece}</React.Fragment>
      ),
    );
}

function CodeBlock({ code }) {
  const [copied, setCopied] = useState(false);

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(code);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      setCopied(false);
    }
  };

  return (
    <div className="mt-2 relative">
      <pre className="overflow-x-auto rounded-control bg-surface-muted border border-line px-3 py-2.5 pr-20 text-xs font-mono text-ink whitespace-pre">{code}</pre>
      <button
        type="button"
        onClick={copy}
        className="absolute top-1.5 right-1.5 flex items-center gap-1 px-2 py-1 rounded-pill border border-line bg-surface text-2xs font-bold text-ink-muted hover:text-ink"
      >
        <Copy className="w-3 h-3" /> {copied ? 'Copied' : 'Copy'}
      </button>
    </div>
  );
}

function Steps({ steps }) {
  return (
    <ol className="space-y-4">
      {steps.map((step, i) => (
        <li key={step.title} className="flex gap-3">
          <span
            aria-hidden="true"
            className="shrink-0 w-6 h-6 rounded-full bg-accent-soft text-accent text-xs font-black flex items-center justify-center mt-0.5"
          >
            {i + 1}
          </span>
          <div className="min-w-0 flex-1">
            <p className="text-sm font-bold text-ink">{step.title}</p>
            <p className="text-sm text-ink-muted mt-0.5 leading-relaxed"><Rich text={step.body} /></p>
            {step.code && <CodeBlock code={step.code} />}
            {step.link && step.link.href.startsWith('https://') && (
              <a
                href={step.link.href}
                target="_blank"
                rel="noopener noreferrer"
                className="inline-flex items-center gap-1 mt-1.5 text-sm font-bold text-accent hover:underline"
              >
                {step.link.label} <ExternalLink className="w-3 h-3" aria-hidden="true" />
              </a>
            )}
          </div>
        </li>
      ))}
    </ol>
  );
}

function SmallTable({ head, rows, caption }) {
  return (
    <div className="overflow-x-auto rounded-control border border-line">
      <table className="w-full text-left text-sm">
        {caption && <caption className="sr-only">{caption}</caption>}
        <thead className="bg-surface-muted border-b border-line">
          <tr className="text-2xs uppercase tracking-wider text-ink-subtle">
            {head.map((h) => <th key={h} scope="col" className="px-3 py-2 font-black">{h}</th>)}
          </tr>
        </thead>
        <tbody>
          {rows.map((row) => (
            <tr key={row[0]} className="border-b border-line last:border-0 align-top">
              {row.map((cell, i) => (
                <td key={i} className={`px-3 py-2 ${i === 0 ? 'font-bold text-ink whitespace-nowrap' : 'text-ink-muted'}`}>
                  <Rich text={cell} />
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

/**
 * The step-by-step help for one tab: where to get the keys, what goes where, and
 * what to do when it does not work. Open until the integration is set up, then
 * folded away (it is one click to bring back).
 */
export default function Guide({ guide, defaultOpen = true, skipTo }) {
  const [open, setOpen] = useState(defaultOpen);
  if (!guide) return null;

  return (
    <section aria-label={guide.title} className="rounded-card border border-accent/25 bg-accent-soft/40">
      <button
        type="button"
        onClick={() => setOpen((o) => !o)}
        aria-expanded={open}
        className="w-full flex items-center gap-3 px-5 py-3.5 text-left"
      >
        <BookOpen className="w-4 h-4 text-accent shrink-0" aria-hidden="true" />
        <span className="flex-1 text-base font-black text-ink">{guide.title}</span>
        <span className="text-xs font-bold text-ink-muted">{open ? 'Hide guide' : 'Show guide'}</span>
        <ChevronDown className={`w-4 h-4 text-ink-muted transition-transform ${open ? 'rotate-180' : ''}`} aria-hidden="true" />
      </button>

      {open && (
        <div className="px-5 pb-5 space-y-5 border-t border-accent/15 pt-4">
          <p className="text-sm text-ink-muted leading-relaxed"><Rich text={guide.intro} /></p>

          {skipTo && (
            <button
              type="button"
              onClick={() => document.getElementById(skipTo)?.scrollIntoView({ behavior: 'smooth', block: 'start' })}
              className="text-sm font-bold text-accent hover:underline"
            >
              Already have the keys? Skip to the settings ↓
            </button>
          )}

          {guide.facts?.length > 0 && (
            <dl className="grid gap-x-6 gap-y-2 sm:grid-cols-[auto_1fr] text-sm">
              {guide.facts.map(([label, value]) => (
                <React.Fragment key={label}>
                  <dt className="font-bold text-ink">{label}</dt>
                  <dd className="text-ink-muted"><Rich text={value} /></dd>
                </React.Fragment>
              ))}
            </dl>
          )}

          {guide.parts.map((part, i) => (
            <div key={part.title ?? i} className={part.title ? 'rounded-control bg-surface border border-line p-4' : ''}>
              {part.title && <h3 className="text-sm font-black text-ink mb-3">{part.title}</h3>}
              <Steps steps={part.steps} />
            </div>
          ))}

          {guide.table && (
            <div>
              <h3 className="text-sm font-black text-ink mb-2">{guide.table.title}</h3>
              <SmallTable head={guide.table.head} rows={guide.table.rows} caption={guide.table.title} />
              {guide.table.note && <p className="text-xs text-ink-subtle mt-1.5">{guide.table.note}</p>}
            </div>
          )}

          {guide.fill?.length > 0 && (
            <div>
              <h3 className="text-sm font-black text-ink mb-2">What goes where</h3>
              <SmallTable head={['Field below', 'What to enter']} rows={guide.fill} caption="What goes where" />
            </div>
          )}

          {guide.trouble?.length > 0 && (
            <div>
              <h3 className="text-sm font-black text-ink mb-2">If it does not work</h3>
              <ul className="space-y-2">
                {guide.trouble.map(([problem, fix]) => (
                  <li key={problem} className="text-sm">
                    <span className="font-bold text-ink"><Rich text={problem} />.</span>{' '}
                    <span className="text-ink-muted"><Rich text={fix} /></span>
                  </li>
                ))}
              </ul>
            </div>
          )}
        </div>
      )}
    </section>
  );
}
