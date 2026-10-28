import React from 'react';

/**
 * The frame for a policy page: a readable column, a heading, the date it last
 * changed, and a contents list. Server-rendered, no scripts, so it loads fast
 * and reads the same in the Play Store's in-app browser.
 */
export default function LegalPage({ title, updated, intro, sections, children }) {
  return (
    <article className="max-w-3xl mx-auto px-6 py-12 text-ink">
      <header className="mb-8">
        <h1 className="text-3xl font-black tracking-tight">{title}</h1>
        <p className="text-sm text-ink-subtle font-semibold mt-1">Last updated: {updated}</p>
        {intro && <p className="text-base text-ink-muted mt-4 leading-relaxed">{intro}</p>}
      </header>

      {sections?.length > 0 && (
        <nav aria-label="Contents" className="mb-10 rounded-card border border-line bg-surface p-5">
          <p className="text-xs font-black uppercase tracking-widest text-ink-subtle mb-3">Contents</p>
          <ol className="space-y-1.5 text-sm font-semibold text-ink-muted list-decimal pl-5">
            {sections.map((s) => (
              <li key={s.id}>
                <a href={`#${s.id}`} className="hover:text-ink underline-offset-2 hover:underline">{s.title}</a>
              </li>
            ))}
          </ol>
        </nav>
      )}

      <div className="space-y-10">{children}</div>
    </article>
  );
}

export function Section({ id, title, children }) {
  return (
    <section id={id} aria-labelledby={`${id}-title`} className="scroll-mt-24">
      <h2 id={`${id}-title`} className="text-xl font-black mb-3">{title}</h2>
      <div className="space-y-3 text-base text-ink-muted leading-relaxed">{children}</div>
    </section>
  );
}

export function List({ items }) {
  return (
    <ul className="list-disc pl-5 space-y-1.5">
      {items.map((item) => <li key={item}>{item}</li>)}
    </ul>
  );
}
