'use client';

import React, { useState } from 'react';
import { Plus, Trash2, ArrowUp, ArrowDown, ClipboardPaste, Sparkles } from 'lucide-react';
import { Button } from '@ds/ui';

const inputCls = 'w-full bg-surface border border-line rounded-control px-3 py-2 text-sm font-semibold text-ink focus:outline-none focus:border-accent';

/**
 * Turns pasted text into rows. Each line is "Label: Value", "Label<tab>Value"
 * or "Label - Value", which covers a table copied from a supplier's sheet or
 * another site. Lines it cannot split are skipped.
 */
export function parsePastedRows(text) {
  return String(text || '')
    .split(/\r?\n/)
    .map((line) => {
      const match = line.match(/^\s*([^:\t]+?)\s*(?::|\t| - )\s*(.+?)\s*$/);
      return match ? { label: match[1].trim(), value: match[2].trim() } : null;
    })
    .filter(Boolean);
}

/** A group with a row for each suggested label. */
export function groupsFromTemplate(template) {
  return (template || []).map((g) => ({
    title: g.title || 'General',
    rows: (g.labels || []).map((label) => ({ label, value: '' })),
  }));
}

/**
 * The specification table of a product: groups of "name / value" rows.
 * `groups` is [{ title, rows: [{ label, value }] }]. `template` is the
 * category's suggested rows; blank rows are tidied away by the server on save.
 */
export default function SpecificationsEditor({ groups, onChange, template }) {
  const [pasteFor, setPasteFor] = useState(null);
  const [pasted, setPasted] = useState('');

  const setGroup = (gi, patch) => onChange(groups.map((g, i) => (i === gi ? { ...g, ...patch } : g)));
  const setRow = (gi, ri, patch) => setGroup(gi, { rows: groups[gi].rows.map((r, i) => (i === ri ? { ...r, ...patch } : r)) });
  const removeRow = (gi, ri) => setGroup(gi, { rows: groups[gi].rows.filter((_, i) => i !== ri) });
  const moveRow = (gi, ri, by) => {
    const rows = [...groups[gi].rows];
    const to = ri + by;
    if (to < 0 || to >= rows.length) return;
    [rows[ri], rows[to]] = [rows[to], rows[ri]];
    setGroup(gi, { rows });
  };
  const addRow = (gi) => setGroup(gi, { rows: [...groups[gi].rows, { label: '', value: '' }] });
  const addGroup = () => onChange([...groups, { title: groups.length ? '' : 'General', rows: [{ label: '', value: '' }] }]);
  const removeGroup = (gi) => onChange(groups.filter((_, i) => i !== gi));

  const applyPaste = (gi) => {
    const rows = parsePastedRows(pasted);
    if (rows.length) {
      // Fill an empty row left behind by "Add row" rather than leaving a gap.
      const kept = groups[gi].rows.filter((r) => r.label.trim() || r.value.trim());
      setGroup(gi, { rows: [...kept, ...rows] });
    }
    setPasteFor(null);
    setPasted('');
  };

  const hasTemplate = (template || []).some((g) => (g.labels || []).length);

  return (
    <div className="space-y-4">
      {groups.length === 0 && (
        <div className="rounded-card border border-dashed border-line p-6 text-center space-y-3">
          <p className="text-ink-muted font-semibold">No specifications yet.</p>
          <div className="flex flex-wrap justify-center gap-2">
            {hasTemplate && (
              <Button size="sm" onClick={() => onChange(groupsFromTemplate(template))} leadingIcon={<Sparkles className="w-3.5 h-3.5" />}>
                Start from this category&apos;s suggested rows
              </Button>
            )}
            <Button size="sm" variant="secondary" onClick={addGroup} leadingIcon={<Plus className="w-3.5 h-3.5" />}>
              Add a blank table
            </Button>
          </div>
        </div>
      )}

      {groups.map((group, gi) => (
        <div key={gi} className="rounded-card border border-line bg-surface-muted p-3 space-y-2">
          <div className="flex items-center gap-2">
            <input
              value={group.title}
              onChange={(e) => setGroup(gi, { title: e.target.value })}
              placeholder="Section heading, e.g. General"
              aria-label="Section heading"
              className={`${inputCls} font-black`}
            />
            <button type="button" onClick={() => removeGroup(gi)} title="Remove this section" aria-label="Remove this section" className="h-9 w-9 shrink-0 inline-flex items-center justify-center rounded-control text-ink-subtle hover:text-danger hover:bg-danger-soft">
              <Trash2 className="h-4 w-4" />
            </button>
          </div>

          <div className="grid grid-cols-[1fr_1fr_auto] gap-x-2 gap-y-1.5 items-center">
            <span className="text-[10px] font-bold uppercase tracking-wide text-ink-subtle px-1">Name</span>
            <span className="text-[10px] font-bold uppercase tracking-wide text-ink-subtle px-1">Value</span>
            <span />
            {group.rows.map((row, ri) => (
              <React.Fragment key={ri}>
                <input value={row.label} onChange={(e) => setRow(gi, ri, { label: e.target.value })} placeholder="Fabric" aria-label={`Row ${ri + 1} name`} className={inputCls} />
                <input value={row.value} onChange={(e) => setRow(gi, ri, { value: e.target.value })} placeholder="Polyester" aria-label={`Row ${ri + 1} value`} className={inputCls} />
                <span className="flex items-center">
                  <button type="button" onClick={() => moveRow(gi, ri, -1)} disabled={ri === 0} title="Move up" aria-label="Move row up" className="h-8 w-7 inline-flex items-center justify-center text-ink-subtle hover:text-ink disabled:opacity-25"><ArrowUp className="h-3.5 w-3.5" /></button>
                  <button type="button" onClick={() => moveRow(gi, ri, 1)} disabled={ri === group.rows.length - 1} title="Move down" aria-label="Move row down" className="h-8 w-7 inline-flex items-center justify-center text-ink-subtle hover:text-ink disabled:opacity-25"><ArrowDown className="h-3.5 w-3.5" /></button>
                  <button type="button" onClick={() => removeRow(gi, ri)} title="Remove row" aria-label="Remove row" className="h-8 w-7 inline-flex items-center justify-center text-ink-subtle hover:text-danger"><Trash2 className="h-3.5 w-3.5" /></button>
                </span>
              </React.Fragment>
            ))}
          </div>

          <div className="flex flex-wrap gap-2 pt-1">
            <Button size="sm" variant="secondary" onClick={() => addRow(gi)} leadingIcon={<Plus className="w-3.5 h-3.5" />}>Add row</Button>
            <Button size="sm" variant="ghost" onClick={() => { setPasteFor(pasteFor === gi ? null : gi); setPasted(''); }} leadingIcon={<ClipboardPaste className="w-3.5 h-3.5" />}>
              Paste rows
            </Button>
          </div>

          {pasteFor === gi && (
            <div className="space-y-2 rounded-control border border-line bg-surface p-3">
              <p className="text-[11px] text-ink-subtle font-medium">
                One per line, like <code>Fabric: Polyester</code>. A table copied from a spreadsheet or a supplier&apos;s page works too.
              </p>
              <textarea value={pasted} onChange={(e) => setPasted(e.target.value)} rows={5} aria-label="Pasted rows" className={`${inputCls} font-mono text-xs`} />
              <div className="flex gap-2">
                <Button size="sm" onClick={() => applyPaste(gi)} disabled={!parsePastedRows(pasted).length}>
                  Add {parsePastedRows(pasted).length || ''} rows
                </Button>
                <Button size="sm" variant="ghost" onClick={() => setPasteFor(null)}>Cancel</Button>
              </div>
            </div>
          )}
        </div>
      ))}

      {groups.length > 0 && (
        <Button size="sm" variant="secondary" onClick={addGroup} leadingIcon={<Plus className="w-3.5 h-3.5" />}>
          Add another section
        </Button>
      )}
    </div>
  );
}
