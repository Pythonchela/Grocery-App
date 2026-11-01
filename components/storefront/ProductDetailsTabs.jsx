'use client';

import React, { useState } from 'react';

/** How many specification rows show before "See all". */
const COLLAPSED_ROWS = 10;

const MANUFACTURER_LABELS = [
  ['generic_name', 'Generic name'],
  ['country_of_origin', 'Country of origin'],
  ['manufacturer_name', 'Manufacturer'],
  ['manufacturer_address', 'Manufacturer address'],
  ['packer_name', 'Packer'],
  ['packer_address', 'Packer address'],
];

/**
 * "All details": Specifications, Description and Manufacturer info as tabs, the
 * way marketplace product pages lay them out. A tab only appears when it has
 * something to show.
 *
 * The description is HTML that the server has already reduced to a small safe
 * set of tags (paragraphs, lists, headings, links), so it is drawn as it is.
 */
export default function ProductDetailsTabs({ product }) {
  const groups = (product.specifications || []).filter((g) => (g.rows || []).length);
  const manufacturer = MANUFACTURER_LABELS
    .map(([key, label]) => [label, product.manufacturer?.[key]])
    .filter(([, value]) => value);
  const hasDescription = Boolean(product.descriptionHtml || product.description);

  const tabs = [
    groups.length > 0 && { id: 'specifications', label: 'Specifications' },
    hasDescription && { id: 'description', label: 'Description' },
    manufacturer.length > 0 && { id: 'manufacturer', label: 'Manufacturer info' },
  ].filter(Boolean);

  const [active, setActive] = useState(tabs[0]?.id);
  const [expanded, setExpanded] = useState(false);
  const current = tabs.find((t) => t.id === active) ? active : tabs[0]?.id;

  if (tabs.length === 0) return null;

  // A long table shows its first rows, then "See all", the way the phone app does.
  const totalRows = groups.reduce((n, g) => n + g.rows.length, 0);
  const collapsible = totalRows > COLLAPSED_ROWS;
  let budget = expanded || !collapsible ? totalRows : COLLAPSED_ROWS;
  const shown = [];
  for (const group of groups) {
    if (budget <= 0) break;
    const rows = group.rows.slice(0, budget);
    budget -= rows.length;
    shown.push({ ...group, rows });
  }

  return (
    <div className="pt-6 border-t border-line">
      <h3 className="text-lg font-black text-ink mb-3">All details</h3>

      <div role="tablist" aria-label="Product details" className="flex flex-wrap gap-2 mb-4">
        {tabs.map((tab) => (
          <button
            key={tab.id}
            id={`pd-tab-${tab.id}`}
            type="button"
            role="tab"
            aria-selected={current === tab.id}
            aria-controls={`pd-panel-${tab.id}`}
            onClick={() => setActive(tab.id)}
            className={`px-4 py-2 rounded-pill text-sm font-bold border transition ${
              current === tab.id
                ? 'bg-primary text-on-primary border-primary'
                : 'bg-surface text-ink-muted border-line hover:border-line-strong'
            }`}
          >
            {tab.label}
          </button>
        ))}
      </div>

      {current === 'specifications' && (
        <div id="pd-panel-specifications" role="tabpanel" aria-labelledby="pd-tab-specifications" className="space-y-5">
          {shown.map((group, gi) => (
            <section key={gi}>
              <h4 className="text-sm font-black text-ink mb-1">{group.title}</h4>
              <dl className="grid grid-cols-1 sm:grid-cols-2 gap-x-8">
                {group.rows.map((row, ri) => (
                  <div key={ri} className="py-2 border-b border-line">
                    <dt className="text-xs text-ink-subtle font-medium">{row.label}</dt>
                    <dd className="text-sm text-ink font-semibold">{row.value}</dd>
                  </div>
                ))}
              </dl>
            </section>
          ))}
          {collapsible && (
            <button
              type="button"
              onClick={() => setExpanded((v) => !v)}
              aria-expanded={expanded}
              className="px-4 py-2 rounded-pill text-sm font-bold border border-line text-ink hover:border-line-strong"
            >
              {expanded ? 'See less' : `See all ${totalRows}`}
            </button>
          )}
        </div>
      )}

      {current === 'description' && (
        <div id="pd-panel-description" role="tabpanel" aria-labelledby="pd-tab-description">
          {product.descriptionHtml ? (
            <div className="rich-text" dangerouslySetInnerHTML={{ __html: product.descriptionHtml }} />
          ) : (
            <p className="text-sm text-ink-muted font-medium leading-relaxed whitespace-pre-line">{product.description}</p>
          )}
        </div>
      )}

      {current === 'manufacturer' && (
        <dl id="pd-panel-manufacturer" role="tabpanel" aria-labelledby="pd-tab-manufacturer" className="grid grid-cols-1 sm:grid-cols-2 gap-x-8">
          {manufacturer.map(([label, value]) => (
            <div key={label} className="py-2 border-b border-line">
              <dt className="text-xs text-ink-subtle font-medium">{label}</dt>
              <dd className="text-sm text-ink font-semibold">{value}</dd>
            </div>
          ))}
        </dl>
      )}
    </div>
  );
}
