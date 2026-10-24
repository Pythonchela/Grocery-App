'use client';

import React, { useCallback, useEffect, useRef, useState } from 'react';
import { AlertCircle, Clock, RefreshCw } from 'lucide-react';
import { apiFetch, formatINR } from '../../lib/apiClient';
import { CANCEL_CODES } from './OrdersClient';

/** Why a line is turned down, as codes the store can later count by cause. */
const DECLINE_REASONS = [
  ['OUT_OF_STOCK', 'Out of stock'],
  ['SHOP_CLOSED', 'Shop is closed'],
  ['CANNOT_PREPARE', 'Cannot prepare it in time'],
  ['DAMAGED', 'Item is damaged'],
  ['OTHER', 'Another reason'],
];

const POLL_MS = 15000;
const COLUMNS = [
  ['awaiting_seller', 'Waiting for the shop', 'A shop has not said yes or no. It cancels itself when the timer ends.'],
  ['to_pack', 'Being prepared', 'Accepted; waiting to be packed and handed to a courier.'],
  ['in_transit', 'On the way', 'With the courier.'],
];
const fieldCls = 'w-full bg-surface border border-line rounded-card px-3 py-2 text-xs font-semibold text-ink';

/** mm:ss (or h:mm) until a time, on the server's clock; negative becomes "late by …". */
function Clock2({ at, offset }) {
  const [now, setNow] = useState(() => Date.now() + offset);
  useEffect(() => {
    const id = setInterval(() => setNow(Date.now() + offset), 1000);
    return () => clearInterval(id);
  }, [offset]);
  if (!at) return null;
  const diff = Math.floor((new Date(at).getTime() - now) / 1000);
  const abs = Math.abs(diff);
  const text = abs >= 3600
    ? `${Math.floor(abs / 3600)}h ${String(Math.floor((abs % 3600) / 60)).padStart(2, '0')}m`
    : `${String(Math.floor(abs / 60)).padStart(2, '0')}:${String(abs % 60).padStart(2, '0')}`;
  return <span className={`font-mono font-black ${diff < 0 ? 'text-danger' : diff < 120 ? 'text-warning' : 'text-ink'}`}>{diff < 0 ? `late ${text}` : text}</span>;
}

/**
 * The operations board: orders that are still moving, in three columns, with
 * the clocks that decide whether a customer is let down. It refreshes itself,
 * and lets staff step in — decline for a shop that is not answering, or cancel
 * an order with a reason code.
 */
export default function LiveBoardClient({ token, onOpenOrders }) {
  const [board, setBoard] = useState({ counts: {}, data: [] });
  const [offset, setOffset] = useState(0);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const [loaded, setLoaded] = useState(false);
  const [filter, setFilter] = useState('');
  const [action, setAction] = useState(null); // { type: 'cancel' | 'decline', order, item? }
  const [code, setCode] = useState('CUSTOMER_REQUEST');
  const [reason, setReason] = useState('OUT_OF_STOCK');
  const [note, setNote] = useState('');
  const [busy, setBusy] = useState(false);
  const mounted = useRef(true);

  const load = useCallback(async () => {
    try {
      const res = await apiFetch('/admin/live-orders', { token });
      if (!mounted.current) return;
      setBoard({ counts: res.counts || {}, data: res.data || [] });
      if (res.server_time) setOffset(new Date(res.server_time).getTime() - Date.now());
      setLoaded(true);
    } catch (e) { if (mounted.current) setError(e.message); }
  }, [token]);

  useEffect(() => {
    mounted.current = true;
    load();
    const id = setInterval(() => { if (!document.hidden) load(); }, POLL_MS);
    return () => { mounted.current = false; clearInterval(id); };
  }, [load]);

  const closeAction = () => { setAction(null); setNote(''); setError(''); };

  const submit = async () => {
    setBusy(true); setError(''); setNotice('');
    try {
      if (action.type === 'cancel') {
        await apiFetch(`/orders/${action.order.id}/cancel`, { method: 'POST', token, body: { reason_code: code, reason: note.trim() || undefined } });
        setNotice(`${action.order.order_number} cancelled${action.order.payment_status === 'PAID' ? ' and refunded' : ''}.`);
      } else {
        await apiFetch(`/admin/order-items/${action.item.id}/reject`, { method: 'POST', token, body: { reason, note: note.trim() || undefined } });
        setNotice('Declined for the shop. The customer has been refunded for that item.');
      }
      closeAction();
      await load();
    } catch (e) { setError(e.message); }
    finally { setBusy(false); }
  };

  const visible = board.data.filter((o) => {
    if (filter === 'late') return o.late_to_pack;
    if (filter === 'overdue') return o.overdue;
    return true;
  });
  const counts = board.counts;
  const tiles = [
    ['', 'Open orders', board.data.length],
    ['late', 'Late to pack', counts.late_to_pack || 0],
    ['overdue', 'Past delivery promise', counts.overdue || 0],
  ];

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="grid grid-cols-3 gap-3 flex-1 min-w-72">
          {tiles.map(([key, label, n]) => (
            <button key={label} type="button" onClick={() => setFilter(key)} aria-pressed={filter === key}
              className={`text-left bg-surface border rounded-card p-3 ${filter === key ? 'border-accent' : 'border-line'} ${key && n > 0 ? 'text-danger' : 'text-ink'}`}>
              <strong className="block text-xl font-black">{n}</strong>
              <span className="text-xs font-bold text-ink-muted">{label}</span>
            </button>
          ))}
        </div>
        <div className="flex items-center gap-3">
          <button type="button" onClick={onOpenOrders} className="text-xs font-bold text-accent">All orders</button>
          <button type="button" onClick={load} aria-label="Refresh" className="p-2.5 bg-surface border border-line rounded-card text-ink-muted hover:text-ink"><RefreshCw className="w-4 h-4" /></button>
        </div>
      </div>

      {notice && <p role="status" className="rounded-card bg-success-soft p-3 text-sm text-success">{notice}</p>}
      {error && !action && <p role="alert" className="rounded-card bg-danger-soft p-3 text-sm text-danger flex items-center gap-2"><AlertCircle className="w-4 h-4" /> {error}</p>}

      <div className="grid gap-4 lg:grid-cols-3">
        {COLUMNS.map(([stage, title, hint]) => {
          const orders = visible.filter((o) => o.stage === stage);
          return (
            <section key={stage} aria-label={title} className="space-y-3">
              <header>
                <h2 className="font-black text-sm text-ink">{title} <span className="text-ink-muted">({orders.length})</span></h2>
                <p className="text-xs text-ink-muted">{hint}</p>
              </header>
              {loaded && orders.length === 0 && <p className="rounded-card border border-dashed border-line p-6 text-center text-xs text-ink-muted">Nothing here.</p>}
              {orders.map((o) => (
                <article key={o.id} className={`bg-surface border rounded-card p-3 space-y-2 text-xs ${o.overdue || o.late_to_pack ? 'border-danger' : 'border-line'}`}>
                  <div className="flex items-start justify-between gap-2">
                    <div>
                      <strong className="text-sm text-ink">{o.order_number}</strong>
                      <p className="text-ink-muted">{o.customer?.name || 'Customer'}{o.city ? ` · ${o.city}` : ''}</p>
                      <p className="text-ink-muted">{formatINR(o.total_amount)} · {o.payment_method === 'COD' ? 'Cash on delivery' : o.payment_status === 'PAID' ? 'Paid' : o.payment_status}</p>
                    </div>
                    <div className="text-right space-y-0.5">
                      {stage === 'awaiting_seller' && o.accept_by && <p><Clock className="inline w-3 h-3 mr-1" /><Clock2 at={o.accept_by} offset={offset} /></p>}
                      {o.promised_by && stage !== 'awaiting_seller' && <p className="text-ink-muted">Promised <Clock2 at={o.promised_by} offset={offset} /></p>}
                      {o.late_to_pack && <p className="font-black text-danger">Late to pack</p>}
                      {o.overdue && <p className="font-black text-danger">Past delivery promise</p>}
                    </div>
                  </div>
                  <ul className="space-y-1 border-t border-line pt-2">
                    {o.items.map((i) => (
                      <li key={i.id} className="flex items-start justify-between gap-2">
                        <span className={i.seller_response === 'REJECTED' ? 'text-ink-subtle line-through' : 'text-ink'}>
                          {i.title} × {i.quantity}
                        </span>
                        {i.seller_response === 'PENDING' && (
                          <button type="button" className="font-bold text-danger shrink-0" onClick={() => { setAction({ type: 'decline', order: o, item: i }); setReason('SHOP_CLOSED'); }}>Decline for shop</button>
                        )}
                      </li>
                    ))}
                  </ul>
                  <div className="flex justify-end">
                    <button type="button" className="font-bold text-danger" onClick={() => { setAction({ type: 'cancel', order: o }); setCode(o.stage === 'awaiting_seller' ? 'SELLER_UNRESPONSIVE' : 'CUSTOMER_REQUEST'); }}>Cancel order</button>
                  </div>
                </article>
              ))}
            </section>
          );
        })}
      </div>

      {action && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-inverse/70 p-4" role="dialog" aria-modal="true" aria-label={action.type === 'cancel' ? 'Cancel order' : 'Decline for shop'}>
          <div className="w-full max-w-sm space-y-3 rounded-panel bg-surface p-5">
            <h3 className="font-black text-ink">{action.type === 'cancel' ? `Cancel ${action.order.order_number}` : `Decline ${action.item.title}`}</h3>
            <p className="text-xs text-ink-muted">Stock goes back on sale and the customer is refunded{action.type === 'decline' ? ' for that item' : ''}.</p>
            {action.type === 'cancel' ? (
              <select aria-label="Why is it being cancelled" value={code} onChange={(e) => setCode(e.target.value)} className={fieldCls}>
                {CANCEL_CODES.map(([value, label]) => <option key={value} value={value}>{label}</option>)}
              </select>
            ) : (
              <select aria-label="Reason" value={reason} onChange={(e) => setReason(e.target.value)} className={fieldCls}>
                {DECLINE_REASONS.map(([value, label]) => <option key={value} value={value}>{label}</option>)}
              </select>
            )}
            <input aria-label="Note" value={note} maxLength={300} onChange={(e) => setNote(e.target.value)} placeholder="Note (optional)" className={fieldCls} />
            {error && <p role="alert" className="text-xs text-danger">{error}</p>}
            <div className="flex gap-2">
              <button type="button" onClick={submit} disabled={busy} className="bg-danger text-on-primary px-4 py-2 rounded-card text-xs font-black disabled:opacity-50">{busy ? 'Working…' : action.type === 'cancel' ? 'Cancel order' : 'Decline'}</button>
              <button type="button" onClick={closeAction} className="text-xs font-bold text-ink-muted px-3">Back</button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
