'use client';

import React, { useCallback, useEffect, useState } from 'react';
import { apiFetch, formatINR } from '../../lib/apiClient';
import { CATEGORIES } from '../support/SupportClient';
import { useAdminAuth } from './AdminAuthContext';

const STATUSES = ['OPEN', 'IN_PROGRESS', 'WAITING_ON_REQUESTER', 'RESOLVED', 'CLOSED'];
const STATUS_TEXT = { OPEN: 'Open', IN_PROGRESS: 'In progress', WAITING_ON_REQUESTER: 'Waiting on requester', RESOLVED: 'Resolved', CLOSED: 'Closed' };
const PRIORITIES = ['LOW', 'NORMAL', 'HIGH', 'URGENT'];
const PRIORITY_TONE = { URGENT: 'text-danger', HIGH: 'text-warning', NORMAL: 'text-ink-muted', LOW: 'text-ink-subtle' };
const FILTERS = [['', 'Needs us'], ['overdue', 'Overdue'], ['unassigned', 'Unassigned'], ['mine', 'Mine'], ['all', 'Everything']];
const field = 'w-full bg-surface border border-line rounded-control px-3 py-2 text-xs font-semibold text-ink';

const categoryLabel = (key) => (CATEGORIES.find(([k]) => k === key) || [key, key])[1];
const when = (iso) => (iso ? new Date(iso).toLocaleString('en-IN', { day: 'numeric', month: 'short', hour: 'numeric', minute: '2-digit' }) : '');

/** The team's support inbox: tickets from shoppers and sellers, with the clock on each. */
export default function SupportInboxClient() {
  const { token, user } = useAdminAuth();
  const [filter, setFilter] = useState('');
  const [kind, setKind] = useState('');
  const [q, setQ] = useState('');
  const [list, setList] = useState({ counts: {}, data: [] });
  const [agents, setAgents] = useState([]);
  const [ticket, setTicket] = useState(null);
  const [reply, setReply] = useState('');
  const [internal, setInternal] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  const load = useCallback(async () => {
    const params = new URLSearchParams();
    if (filter === 'all') params.set('all', '1');
    else if (filter) params.set(filter, '1');
    if (kind) params.set('kind', kind);
    if (q.trim()) params.set('q', q.trim());
    try { setList(await apiFetch(`/admin/support/tickets?${params}`, { token })); }
    catch (e) { setError(e.message); }
  }, [token, filter, kind, q]);

  useEffect(() => { load(); const id = setInterval(() => { if (!document.hidden) load(); }, 30000); return () => clearInterval(id); }, [load]);
  useEffect(() => { apiFetch('/admin/support/agents', { token }).then((r) => setAgents(r.data || [])).catch(() => {}); }, [token]);

  const open = async (id) => {
    setError('');
    try { setTicket((await apiFetch(`/admin/support/tickets/${id}`, { token })).data); setReply(''); setInternal(false); }
    catch (e) { setError(e.message); }
  };

  const run = async (fn) => {
    setBusy(true); setError('');
    try { await fn(); await load(); } catch (e) { setError(e.message); } finally { setBusy(false); }
  };

  const change = (body) => run(async () => setTicket((await apiFetch(`/admin/support/tickets/${ticket.id}`, { method: 'PUT', token, body })).data));
  const send = (e) => {
    e.preventDefault();
    run(async () => { setTicket((await apiFetch(`/admin/support/tickets/${ticket.id}/messages`, { method: 'POST', token, body: { body: reply, internal } })).data); setReply(''); setInternal(false); });
  };

  const counts = list.counts || {};

  return (
    <div className="space-y-4">
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        {[['Open', counts.open], ['Waiting on requester', counts.waiting], ['Overdue', counts.overdue, true], ['Unassigned', counts.unassigned]].map(([label, n, bad]) => (
          <div key={label} className="bg-surface border border-line rounded-card p-3">
            <strong className={`block text-xl font-black ${bad && n > 0 ? 'text-danger' : 'text-ink'}`}>{n ?? '—'}</strong>
            <span className="text-xs font-bold text-ink-muted">{label}</span>
          </div>
        ))}
      </div>
      {error && <p role="alert" className="text-xs font-bold text-danger">{error}</p>}

      <div className="grid gap-4 lg:grid-cols-[minmax(0,5fr)_minmax(0,7fr)]">
        <section aria-label="Tickets" className="space-y-3">
          <div className="flex flex-wrap gap-1">
            {FILTERS.map(([key, label]) => (
              <button key={label} type="button" aria-pressed={filter === key} onClick={() => setFilter(key)}
                className={`px-3 py-1.5 rounded-control text-xs font-bold ${filter === key ? 'bg-inverse text-ink-inverse' : 'bg-surface border border-line text-ink-muted'}`}>{label}</button>
            ))}
          </div>
          <div className="flex gap-2">
            <input aria-label="Search tickets" className={field} placeholder="Search number, subject or person" value={q} onChange={(e) => setQ(e.target.value)} />
            <select aria-label="Who raised it" className={`${field} max-w-32`} value={kind} onChange={(e) => setKind(e.target.value)}>
              <option value="">Everyone</option><option value="customer">Shoppers</option><option value="seller">Sellers</option>
            </select>
          </div>
          {list.data.length === 0 && <p className="rounded-card border border-dashed border-line p-6 text-center text-xs text-ink-muted">Nothing here.</p>}
          <ul className="space-y-2">
            {list.data.map((t) => (
              <li key={t.id}>
                <button type="button" onClick={() => open(t.id)} className={`w-full text-left bg-surface border rounded-card p-3 space-y-1 ${ticket?.id === t.id ? 'border-accent' : t.overdue ? 'border-danger' : 'border-line'}`}>
                  <span className="flex items-start justify-between gap-2">
                    <strong className="text-sm text-ink">{t.subject}</strong>
                    <span className={`text-[10px] font-black uppercase ${PRIORITY_TONE[t.priority]}`}>{t.priority}</span>
                  </span>
                  <span className="block text-[11px] text-ink-muted">{t.number} · {t.kind === 'SELLER' ? `Seller${t.shop ? ` ${t.shop}` : ''}` : 'Shopper'} · {t.requester_name}</span>
                  <span className="block text-[11px] text-ink-muted">{categoryLabel(t.category)} · {STATUS_TEXT[t.status]}{t.assignee_name ? ` · ${t.assignee_name}` : ' · unassigned'}</span>
                  {t.overdue && <span className="block text-[11px] font-black text-danger">No reply yet — due {when(t.sla_due_at)}</span>}
                </button>
              </li>
            ))}
          </ul>
        </section>

        <section aria-label="Conversation" className="min-w-0">
          {!ticket ? <p className="rounded-card border border-dashed border-line p-10 text-center text-sm text-ink-muted">Choose a ticket to read it.</p> : (
            <div className="space-y-3 bg-surface border border-line rounded-card p-4">
              <header>
                <h2 className="text-base font-black text-ink">{ticket.subject}</h2>
                <p className="text-xs text-ink-muted">{ticket.number} · {ticket.requester?.name} ({ticket.requester?.email}){ticket.requester?.phone ? ` · ${ticket.requester.phone}` : ''}</p>
              </header>
              <div className="grid gap-2 sm:grid-cols-3">
                <label className="text-[10px] font-bold uppercase text-ink-subtle">Status
                  <select className={`${field} mt-1`} value={ticket.status} disabled={busy} onChange={(e) => change({ status: e.target.value })}>{STATUSES.map((s) => <option key={s} value={s}>{STATUS_TEXT[s]}</option>)}</select>
                </label>
                <label className="text-[10px] font-bold uppercase text-ink-subtle">Priority
                  <select className={`${field} mt-1`} value={ticket.priority} disabled={busy} onChange={(e) => change({ priority: e.target.value })}>{PRIORITIES.map((p) => <option key={p} value={p}>{p}</option>)}</select>
                </label>
                <label className="text-[10px] font-bold uppercase text-ink-subtle">Assigned to
                  <select className={`${field} mt-1`} value={ticket.assigned_to || ''} disabled={busy} onChange={(e) => change({ assigned_to: e.target.value || null })}>
                    <option value="">Nobody</option>
                    {agents.map((a) => <option key={a.id} value={a.id}>{a.name}{a.id === user?.id ? ' (me)' : ''}</option>)}
                  </select>
                </label>
              </div>
              {ticket.order && (
                <div className="rounded-control bg-surface-muted p-3 text-xs text-ink">
                  <strong>Order {ticket.order.order_number}</strong> · {ticket.order.status} · {formatINR(ticket.order.total_amount)} · {ticket.order.payment_method}
                  <ul className="mt-1 text-ink-muted">{ticket.order.items.map((i, n) => <li key={n}>{i.title} × {i.quantity}{i.shop ? ` · ${i.shop}` : ''}</li>)}</ul>
                </div>
              )}
              <ol className="space-y-2">
                {ticket.messages.map((m) => (
                  <li key={m.id} className={`max-w-[90%] rounded-card p-3 text-sm ${m.internal ? 'bg-warning-soft border border-warning' : m.author === 'STAFF' ? 'ml-auto bg-accent-soft' : 'bg-surface-muted'}`}>
                    <p className="whitespace-pre-wrap text-ink">{m.body}</p>
                    <p className="mt-1 text-[10px] text-ink-muted">{m.internal ? 'Internal note · ' : ''}{m.name || (m.author === 'STAFF' ? 'Team' : 'Requester')} · {when(m.created_at)}</p>
                  </li>
                ))}
              </ol>
              {ticket.rating && <p className="text-xs text-ink-muted">Rated {ticket.rating}/5{ticket.rating_note ? ` — “${ticket.rating_note}”` : ''}</p>}
              <form onSubmit={send} className="space-y-2">
                <label htmlFor="staff-reply" className="sr-only">Reply</label>
                <textarea id="staff-reply" required rows={3} maxLength={4000} className={field} placeholder={internal ? 'Note for the team (the requester never sees this)' : 'Reply to the requester'} value={reply} onChange={(e) => setReply(e.target.value)} />
                <div className="flex flex-wrap items-center gap-3">
                  <button className="btn-primary px-4 py-2 text-xs disabled:opacity-50" disabled={busy || !reply.trim()}>{internal ? 'Add note' : 'Send reply'}</button>
                  <span className="flex items-center gap-1.5 text-xs font-bold text-ink-muted">
                    <input id="staff-internal" type="checkbox" checked={internal} onChange={(e) => setInternal(e.target.checked)} />
                    <label htmlFor="staff-internal">Internal note</label>
                  </span>
                </div>
              </form>
            </div>
          )}
        </section>
      </div>
    </div>
  );
}
