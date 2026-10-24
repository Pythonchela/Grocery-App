'use client';

import React, { useCallback, useEffect, useState } from 'react';
import { apiFetch } from '../../lib/apiClient';

export const CATEGORIES = [
  ['ORDER_ISSUE', 'A problem with an order'],
  ['DELIVERY', 'Delivery or tracking'],
  ['PAYMENT', 'Payment'],
  ['REFUND', 'Refund or return'],
  ['PRODUCT', 'A product'],
  ['ACCOUNT', 'My account'],
  ['PAYOUT', 'Payouts and earnings'],
  ['SHOP_SETUP', 'Setting up my shop'],
  ['OTHER', 'Something else'],
];
export const STATUS_LABELS = {
  OPEN: 'Waiting for us', IN_PROGRESS: 'We are on it', WAITING_ON_REQUESTER: 'Waiting for your reply', RESOLVED: 'Resolved', CLOSED: 'Closed',
};

const input = 'w-full rounded-control border border-line bg-surface px-3 py-2 text-sm text-ink';
const button = 'rounded-control bg-accent px-4 py-2 text-xs font-bold text-on-accent disabled:opacity-50';
const ghost = 'rounded-control border border-line px-4 py-2 text-xs font-bold text-ink disabled:opacity-50';

function when(iso) {
  return iso ? new Date(iso).toLocaleString('en-IN', { day: 'numeric', month: 'short', hour: 'numeric', minute: '2-digit' }) : '';
}

/**
 * Help for shoppers and sellers: raise a ticket, follow the conversation,
 * reply, say it is sorted and rate how it went.
 *
 * `sellerView` hides the shopper-only categories, and `orderId` (from a "get
 * help with this order" link) pre-fills the order the ticket is about.
 */
export default function SupportClient({ token, sellerView = false, orderId = '' }) {
  const [tickets, setTickets] = useState([]);
  const [open, setOpen] = useState(null);
  const [composing, setComposing] = useState(Boolean(orderId));
  const [form, setForm] = useState({ category: orderId ? 'ORDER_ISSUE' : sellerView ? 'PAYOUT' : 'ORDER_ISSUE', subject: '', message: '' });
  const [reply, setReply] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [loaded, setLoaded] = useState(false);

  const categories = CATEGORIES.filter(([key]) => (sellerView ? !['ACCOUNT'].includes(key) : !['PAYOUT', 'SHOP_SETUP'].includes(key)));

  const load = useCallback(async () => {
    try { setTickets((await apiFetch('/support/tickets', { token })).data || []); setLoaded(true); }
    catch (e) { setError(e.message); }
  }, [token]);
  useEffect(() => { load(); }, [load]);

  const show = async (id) => {
    setError('');
    try { setOpen((await apiFetch(`/support/tickets/${id}`, { token })).data); }
    catch (e) { setError(e.message); }
  };

  const run = async (fn) => {
    setBusy(true); setError('');
    try { await fn(); } catch (e) { setError(e.message); } finally { setBusy(false); }
  };

  const create = (e) => {
    e.preventDefault();
    run(async () => {
      const res = await apiFetch('/support/tickets', { method: 'POST', token, body: { ...form, ...(orderId ? { order_id: orderId } : {}) } });
      setComposing(false); setForm({ ...form, subject: '', message: '' });
      setOpen(res.data); load();
    });
  };

  const send = (e) => {
    e.preventDefault();
    run(async () => {
      const res = await apiFetch(`/support/tickets/${open.id}/messages`, { method: 'POST', token, body: { body: reply } });
      setReply(''); setOpen(res.data); load();
    });
  };

  if (open) {
    const done = ['RESOLVED', 'CLOSED'].includes(open.status);
    return (
      <section className="space-y-4" aria-label="Ticket">
        <button type="button" className="text-xs font-bold text-accent" onClick={() => { setOpen(null); load(); }}>← All tickets</button>
        <header>
          <h2 className="text-lg font-black text-ink">{open.subject}</h2>
          <p className="text-xs text-ink-muted">{open.number} · {STATUS_LABELS[open.status] || open.status}{open.order_number ? ` · order ${open.order_number}` : ''}</p>
        </header>
        {error && <p role="alert" className="rounded-card bg-danger-soft p-3 text-sm text-danger">{error}</p>}
        <ol className="space-y-3">
          {open.messages.map((m) => (
            <li key={m.id} className={`max-w-[85%] rounded-card p-3 text-sm ${m.author === 'STAFF' ? 'bg-accent-soft text-ink' : 'ml-auto bg-surface-muted text-ink'}`}>
              <p className="whitespace-pre-wrap">{m.body}</p>
              <p className="mt-1 text-[10px] text-ink-muted">{m.author === 'STAFF' ? 'Support team' : 'You'} · {when(m.created_at)}</p>
            </li>
          ))}
        </ol>
        {open.status !== 'CLOSED' && (
          <form onSubmit={send} className="space-y-2">
            <label htmlFor="support-reply" className="block text-xs font-bold text-ink">{done ? 'Not sorted? Reply to reopen it' : 'Your reply'}</label>
            <textarea id="support-reply" required rows={3} maxLength={4000} className={input} value={reply} onChange={(e) => setReply(e.target.value)} />
            <div className="flex gap-2">
              <button className={button} disabled={busy || !reply.trim()}>Send</button>
              {!done && <button type="button" className={ghost} disabled={busy} onClick={() => run(async () => { setOpen((await apiFetch(`/support/tickets/${open.id}/close`, { method: 'POST', token })).data); load(); })}>It&apos;s sorted — close</button>}
            </div>
          </form>
        )}
        {done && !open.rating && (
          <div className="space-y-2 rounded-card border border-line p-3">
            <p className="text-sm font-bold text-ink">How did we do?</p>
            <div className="flex gap-1" role="group" aria-label="Rating">
              {[1, 2, 3, 4, 5].map((n) => (
                <button key={n} type="button" className={ghost} disabled={busy} aria-label={`${n} out of 5`}
                  onClick={() => run(async () => setOpen((await apiFetch(`/support/tickets/${open.id}/rating`, { method: 'POST', token, body: { rating: n } })).data))}>{n}★</button>
              ))}
            </div>
          </div>
        )}
        {open.rating && <p className="text-xs text-ink-muted">You rated this {open.rating} out of 5. Thank you.</p>}
      </section>
    );
  }

  return (
    <section className="space-y-4" aria-label="Help and support">
      <header className="flex flex-wrap items-center justify-between gap-2">
        <div>
          <h2 className="text-lg font-black text-ink">Help &amp; support</h2>
          <p className="text-xs text-ink-muted">Tell us what went wrong. We reply here and send you a notification.</p>
        </div>
        {!composing && <button type="button" className={button} onClick={() => setComposing(true)}>New request</button>}
      </header>
      {error && <p role="alert" className="rounded-card bg-danger-soft p-3 text-sm text-danger">{error}</p>}

      {composing && (
        <form onSubmit={create} className="space-y-3 rounded-card border border-line bg-surface p-4">
          {orderId && <p className="text-xs text-ink-muted">This request will be linked to your order.</p>}
          <div>
            <label htmlFor="support-category" className="block text-xs font-bold text-ink">What is it about?</label>
            <select id="support-category" className={`${input} mt-1`} value={form.category} onChange={(e) => setForm({ ...form, category: e.target.value })}>
              {categories.map(([key, label]) => <option key={key} value={key}>{label}</option>)}
            </select>
          </div>
          <div>
            <label htmlFor="support-subject" className="block text-xs font-bold text-ink">In a few words</label>
            <input id="support-subject" required minLength={3} maxLength={160} className={`${input} mt-1`} value={form.subject} onChange={(e) => setForm({ ...form, subject: e.target.value })} />
          </div>
          <div>
            <label htmlFor="support-message" className="block text-xs font-bold text-ink">What happened?</label>
            <textarea id="support-message" required minLength={3} maxLength={4000} rows={5} className={`${input} mt-1`} value={form.message} onChange={(e) => setForm({ ...form, message: e.target.value })} />
          </div>
          <div className="flex gap-2"><button className={button} disabled={busy}>Send request</button><button type="button" className={ghost} onClick={() => setComposing(false)}>Cancel</button></div>
        </form>
      )}

      {loaded && tickets.length === 0 && !composing && <p className="rounded-card border border-dashed border-line p-8 text-center text-sm text-ink-muted">You have not asked for help yet.</p>}
      <ul className="space-y-2">
        {tickets.map((t) => (
          <li key={t.id}>
            <button type="button" onClick={() => show(t.id)} className="w-full rounded-card border border-line bg-surface p-3 text-left hover:border-accent">
              <span className="flex items-start justify-between gap-2">
                <strong className="text-sm text-ink">{t.subject}</strong>
                <span className="shrink-0 rounded-pill bg-surface-muted px-2 py-0.5 text-[10px] font-bold text-ink-muted">{STATUS_LABELS[t.status] || t.status}</span>
              </span>
              <span className="text-xs text-ink-muted">{t.number}{t.order_number ? ` · order ${t.order_number}` : ''} · {when(t.last_message_at)}</span>
            </button>
          </li>
        ))}
      </ul>
    </section>
  );
}
