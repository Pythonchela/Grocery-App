'use client';

import React from 'react';

const DAYS = [
  ['mon', 'Monday'], ['tue', 'Tuesday'], ['wed', 'Wednesday'], ['thu', 'Thursday'],
  ['fri', 'Friday'], ['sat', 'Saturday'], ['sun', 'Sunday'],
];

const inputCls = 'bg-surface border border-line rounded-control px-2 py-1.5 text-sm font-semibold text-ink focus:outline-none focus:border-accent disabled:opacity-40';

/**
 * A shop's opening hours: a row for each weekday with an open and a close time,
 * or ticked closed. `value` is { mon: { open, close } | null, ... } or null for
 * "always open". A close time earlier than the open time means the shop stays
 * open past midnight.
 */
export default function OpeningHoursEditor({ value, onChange }) {
  const always = !value;

  const setAlways = (on) => onChange(on ? null : Object.fromEntries(DAYS.map(([d]) => [d, { open: '09:00', close: '21:00' }])));
  const setDay = (day, slot) => onChange({ ...value, [day]: slot });
  const copyMonday = () => {
    const monday = value?.mon;
    onChange(Object.fromEntries(DAYS.map(([d]) => [d, monday ? { ...monday } : null])));
  };

  return (
    <div className="space-y-2">
      <label className="flex items-center gap-2 text-xs font-bold text-ink cursor-pointer">
        <input type="checkbox" checked={always} onChange={(e) => setAlways(e.target.checked)} />
        Always open (no set hours)
      </label>

      {!always && (
        <>
          <div className="space-y-1.5">
            {DAYS.map(([day, label]) => {
              const slot = value[day];
              const closed = !slot;

              return (
                <div key={day} className="grid grid-cols-[84px_auto_1fr] items-center gap-2">
                  <span className="text-xs font-bold text-ink">{label}</span>
                  <label className="flex items-center gap-1 text-[11px] font-semibold text-ink-muted cursor-pointer">
                    <input
                      type="checkbox"
                      checked={closed}
                      onChange={(e) => setDay(day, e.target.checked ? null : { open: '09:00', close: '21:00' })}
                      aria-label={`${label} closed`}
                    />
                    Closed
                  </label>
                  <span className="flex items-center gap-1.5">
                    <input
                      type="time" disabled={closed} value={slot?.open || ''}
                      onChange={(e) => setDay(day, { ...slot, open: e.target.value })}
                      aria-label={`${label} opens`} className={inputCls}
                    />
                    <span className="text-ink-subtle text-xs">to</span>
                    <input
                      type="time" disabled={closed} value={slot?.close || ''}
                      onChange={(e) => setDay(day, { ...slot, close: e.target.value })}
                      aria-label={`${label} closes`} className={inputCls}
                    />
                  </span>
                </div>
              );
            })}
          </div>
          <button type="button" onClick={copyMonday} className="text-[11px] font-bold text-accent hover:underline">
            Copy Monday to every day
          </button>
        </>
      )}
    </div>
  );
}
