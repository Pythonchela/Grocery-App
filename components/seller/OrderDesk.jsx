'use client';

import React, { useCallback, useEffect, useRef, useState } from 'react';
import { apiFetch, formatINR } from '../../lib/apiClient';

export const DECLINE_REASONS = [
  ['OUT_OF_STOCK', 'Out of stock'],
  ['SHOP_CLOSED', 'Shop is closed'],
  ['CANNOT_PREPARE', 'Cannot prepare it in time'],
  ['DAMAGED', 'Item is damaged'],
  ['OTHER', 'Another reason'],
];
const PREP_CHOICES = [10, 15, 20, 30, 45, 60, 120];
const input = 'w-full rounded-control border border-line bg-surface px-3 py-2 text-sm text-ink';
const button = 'rounded-control bg-accent px-3 py-2 text-xs font-bold text-on-accent disabled:opacity-50';
const ghost = 'rounded-control border border-line px-3 py-2 text-xs font-bold text-ink disabled:opacity-50';

function lineLabel(item) {
  const options = [item.variant?.color, item.variant?.size].filter(Boolean).join(' / ');
  return `${item.product?.title || 'Product'}${options ? ` (${options})` : ''} × ${item.quantity}`;
}

/** mm:ss until a deadline, using the server's clock so a wrong device clock does not matter. */
export function Countdown({ until, offsetMs = 0 }) {
  const [now, setNow] = useState(() => Date.now() + offsetMs);
  useEffect(() => {
    const id = setInterval(() => setNow(Date.now() + offsetMs), 1000);
    return () => clearInterval(id);
  }, [offsetMs]);

  if (!until) return null;
  const left = Math.max(0, Math.floor((new Date(until).getTime() - now) / 1000));
  const urgent = left < 120;
  return (
    <span role="timer" className={`font-mono text-sm font-black ${urgent ? 'text-danger' : 'text-ink'}`}>
      {String(Math.floor(left / 60)).padStart(2, '0')}:{String(left % 60).padStart(2, '0')}
    </span>
  );
}

/** Asks why, then turns the order line down (or cancels it before it ships). */
export function DeclineForm({ item, token, onDone, onCancel, title = 'Decline this order' }) {
  const [reason, setReason] = useState('OUT_OF_STOCK');
  const [note, setNote] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  const submit = async () => {
    setBusy(true); setError('');
    try {
      await apiFetch(`/seller/order-items/${item.id}/reject`, { method: 'POST', token, body: { reason, note: note.trim() || null } });
      onDone();
    } catch (e) { setError(e.message); }
    finally { setBusy(false); }
  };

  return (
    <div className="space-y-2 rounded-card bg-surface-muted p-3">
      <p className="text-xs font-bold text-ink">{title}</p>
      <select aria-label="Reason" className={input} value={reason} onChange={(e) => setReason(e.target.value)}>
        {DECLINE_REASONS.map(([value, label]) => <option key={value} value={value}>{label}</option>)}
      </select>
      <input aria-label="Note for the customer" className={input} maxLength={300} placeholder="Optional note" value={note} onChange={(e) => setNote(e.target.value)} />
      <p className="text-xs text-ink-muted">The customer is told and refunded automatically.{reason === 'OUT_OF_STOCK' ? ' This item will show as sold out until you restock it.' : ''}</p>
      {error && <p role="alert" className="text-xs text-danger">{error}</p>}
      <div className="flex gap-2">
        <button type="button" className="rounded-control bg-danger px-3 py-2 text-xs font-bold text-on-accent disabled:opacity-50" disabled={busy} onClick={submit}>Confirm decline</button>
        <button type="button" className={ghost} onClick={onCancel}>Keep order</button>
      </div>
    </div>
  );
}

/**
 * Orders waiting for the shop's answer, oldest deadline first, each with a
 * countdown. The list refreshes itself, so a new order simply appears.
 */
export function IncomingOrders({ token, defaultPrep, onChanged }) {
  const [rows, setRows] = useState([]);
  const [offset, setOffset] = useState(0);
  const [prep, setPrep] = useState({});
  const [declining, setDeclining] = useState(null);
  const [busy, setBusy] = useState(null);
  const [error, setError] = useState('');
  const [loaded, setLoaded] = useState(false);
  const mounted = useRef(true);

  const load = useCallback(async () => {
    try {
      const res = await apiFetch('/seller/order-items?stage=new&per_page=50', { token });
      if (!mounted.current) return;
      setRows(res.data || []);
      if (res.server_time) setOffset(new Date(res.server_time).getTime() - Date.now());
      setLoaded(true);
    } catch (e) { if (mounted.current) setError(e.message); }
  }, [token]);

  useEffect(() => {
    mounted.current = true;
    load();
    const id = setInterval(() => { if (!document.hidden) load(); }, 10000);
    return () => { mounted.current = false; clearInterval(id); };
  }, [load]);

  const accept = async (item) => {
    setBusy(item.id); setError('');
    try {
      const minutes = Number(prep[item.id] ?? defaultPrep ?? 20);
      await apiFetch(`/seller/order-items/${item.id}/accept`, { method: 'POST', token, body: { prep_minutes: minutes } });
      await load(); onChanged?.();
    } catch (e) { setError(e.message); }
    finally { setBusy(null); }
  };

  return (
    <section className="space-y-3" aria-label="Incoming orders">
      <p className="text-sm text-ink-muted">Accept an order to start preparing it. If you do nothing, it is cancelled when the timer runs out and the customer is refunded.</p>
      {error && <p role="alert" className="rounded-card bg-danger-soft p-3 text-sm text-danger">{error}</p>}
      {loaded && rows.length === 0 && <p className="rounded-card border border-dashed border-line p-8 text-center text-sm text-ink-muted">No orders waiting. New ones appear here by themselves.</p>}
      {rows.map((item) => (
        <article key={item.id} className="space-y-3 rounded-card border-2 border-accent bg-surface p-4 text-sm text-ink">
          <div className="flex items-start justify-between gap-3">
            <div>
              <strong className="block">{lineLabel(item)}</strong>
              <span className="text-xs text-ink-muted">
                {item.order?.order_number} · {item.order?.payment_method === 'COD' ? 'Cash on delivery' : 'Paid online'} · {item.order?.shipping_address?.city} {item.order?.shipping_address?.pincode}
              </span>
              <span className="mt-1 block text-xs text-ink-muted">You earn {formatINR(item.seller_earning)}</span>
            </div>
            <div className="text-right">
              <span className="block text-[10px] font-bold uppercase text-ink-muted">Answer within</span>
              <Countdown until={item.accept_by} offsetMs={offset} />
            </div>
          </div>
          {declining === item.id ? (
            <DeclineForm item={item} token={token} onCancel={() => setDeclining(null)} onDone={() => { setDeclining(null); load(); onChanged?.(); }} />
          ) : (
            <div className="flex flex-wrap items-end gap-2">
              <div className="text-xs font-bold text-ink">
                <label htmlFor={`prep-${item.id}`} className="block">Ready in</label>
                <select id={`prep-${item.id}`} className={`${input} mt-1 w-32`} value={prep[item.id] ?? defaultPrep ?? 20} onChange={(e) => setPrep((v) => ({ ...v, [item.id]: e.target.value }))}>
                  {[...new Set([Number(defaultPrep) || 20, ...PREP_CHOICES])].sort((a, b) => a - b).map((m) => <option key={m} value={m}>{m} min</option>)}
                </select>
              </div>
              <button type="button" className={button} disabled={busy === item.id} onClick={() => accept(item)}>Accept order</button>
              <button type="button" className={ghost} onClick={() => setDeclining(item.id)}>Decline</button>
            </div>
          )}
        </article>
      ))}
    </section>
  );
}

/** Pause the shop for a while, or reopen it; and choose manual or automatic acceptance. */
export function OrderDeskSettings({ profile, token, onSaved }) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const pausedUntil = profile?.paused_until && new Date(profile.paused_until) > new Date() ? new Date(profile.paused_until) : null;

  const save = async (body) => {
    setBusy(true); setError('');
    try {
      const res = await apiFetch('/seller/me', { method: 'PUT', token, body });
      onSaved?.(res.data);
    } catch (e) { setError(e.message); }
    finally { setBusy(false); }
  };

  const untilTomorrow = () => {
    const t = new Date(); t.setDate(t.getDate() + 1); t.setHours(9, 0, 0, 0);
    return Math.max(1, Math.round((t.getTime() - Date.now()) / 60000));
  };

  return (
    <div className="space-y-4 border-b border-line pb-4">
      <h2 className="font-bold text-ink">Taking orders</h2>
      <div className="flex items-start gap-2 text-sm text-ink">
        <input id="confirm-each-order" type="checkbox" className="mt-1" checked={profile?.auto_accept === false} disabled={busy}
          onChange={(e) => save({ auto_accept: !e.target.checked })} />
        <div>
          <label htmlFor="confirm-each-order" className="font-bold">Confirm each order myself</label>
          <p className="text-xs text-ink-muted">Off: orders are accepted automatically. On: every new order waits for you to accept it, and is cancelled if you do not answer in time.</p>
        </div>
      </div>
      <div className="space-y-2">
        <p className="text-sm text-ink">
          {pausedUntil ? <>Paused until <strong>{pausedUntil.toLocaleString([], { weekday: 'short', hour: 'numeric', minute: '2-digit' })}</strong>.</> : profile?.accepting_orders === false ? 'Orders are switched off.' : 'Your shop is taking orders (within your opening hours).'}
        </p>
        <div className="flex flex-wrap gap-2">
          {[[30, '30 min'], [60, '1 hour'], [120, '2 hours']].map(([m, label]) => <button key={m} type="button" className={ghost} disabled={busy} onClick={() => save({ pause_minutes: m })}>Pause {label}</button>)}
          <button type="button" className={ghost} disabled={busy} onClick={() => save({ pause_minutes: untilTomorrow() })}>Pause until tomorrow 9am</button>
          {(pausedUntil || profile?.accepting_orders === false) && <button type="button" className={button} disabled={busy} onClick={() => save({ pause_minutes: 0 })}>Resume orders</button>}
        </div>
      </div>
      {error && <p role="alert" className="text-xs text-danger">{error}</p>}
    </div>
  );
}

/** One item on or off for today (or for a while), without touching its stock. */
export function AvailabilityToggle({ product, token, onChanged }) {
  const [busy, setBusy] = useState(false);
  const [choosing, setChoosing] = useState(false);
  const [error, setError] = useState('');
  const live = product.status === 'ACTIVE';
  const switchable = live || product.status === 'OUT_OF_STOCK';
  if (!switchable) return null;

  const send = async (body) => {
    setBusy(true); setError('');
    try {
      await apiFetch(`/seller/products/${product.id}/availability`, { method: 'PUT', token, body });
      setChoosing(false); onChanged?.();
    } catch (e) { setError(e.message); }
    finally { setBusy(false); }
  };

  const hours = (h) => new Date(Date.now() + h * 3600000).toISOString();
  const tomorrow = () => { const t = new Date(); t.setDate(t.getDate() + 1); t.setHours(9, 0, 0, 0); return t.toISOString(); };

  return (
    <span className="inline-flex flex-col items-start gap-1">
      <button type="button" disabled={busy} aria-pressed={live}
        className={`rounded-control px-3 py-2 text-xs font-bold disabled:opacity-50 ${live ? 'bg-success-soft text-success' : 'bg-danger-soft text-danger'}`}
        onClick={() => (live ? setChoosing((v) => !v) : send({ available: true }))}>
        {live ? 'Available' : 'Sold out — switch on'}
      </button>
      {choosing && (
        <span className="flex flex-wrap gap-1 rounded-card bg-surface-muted p-2">
          <span className="w-full text-[10px] font-bold uppercase text-ink-muted">Switch off until</span>
          <button type="button" className={ghost} disabled={busy} onClick={() => send({ available: false, until: hours(2) })}>2 hours</button>
          <button type="button" className={ghost} disabled={busy} onClick={() => send({ available: false, until: tomorrow() })}>Tomorrow 9am</button>
          <button type="button" className={ghost} disabled={busy} onClick={() => send({ available: false })}>I switch it on</button>
        </span>
      )}
      {error && <span role="alert" className="text-[10px] text-danger">{error}</span>}
    </span>
  );
}
