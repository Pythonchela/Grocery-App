import React from 'react';

const TONES = {
  veg: { cls: 'border-success text-success', label: 'Vegetarian' },
  non_veg: { cls: 'border-danger text-danger', label: 'Non-vegetarian' },
  egg: { cls: 'border-warning text-warning', label: 'Contains egg' },
};

/** The small square mark food shoppers look for: green dot for veg, red for non-veg, amber for egg. */
export default function DietMark({ diet, size = 'md' }) {
  const tone = TONES[diet];
  if (!tone) return null;
  const box = size === 'lg' ? 'h-5 w-5' : size === 'sm' ? 'h-3.5 w-3.5' : 'h-4 w-4';
  const dot = size === 'lg' ? 'h-2.5 w-2.5' : size === 'sm' ? 'h-1.5 w-1.5' : 'h-2 w-2';
  return (
    <span
      role="img"
      aria-label={tone.label}
      title={tone.label}
      className={`inline-flex shrink-0 items-center justify-center rounded-sm border-2 ${box} ${tone.cls}`}
    >
      <span className={`rounded-pill bg-current ${dot}`} />
    </span>
  );
}
