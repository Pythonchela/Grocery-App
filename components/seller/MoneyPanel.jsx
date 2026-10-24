'use client';

import React, { useCallback, useEffect, useState } from 'react';
import { apiDownload, apiFetch, formatINR } from '../../lib/apiClient';

const input = 'w-full rounded-control border border-line bg-surface px-3 py-2 text-sm text-ink';
const button = 'rounded-control bg-accent px-3 py-2 text-xs font-bold text-on-accent disabled:opacity-50';
const ghost = 'rounded-control border border-line px-3 py-2 text-xs font-bold text-ink disabled:opacity-50';
const STATUS = { REQUESTED: 'Waiting for the team', PAID: 'Paid', REJECTED: 'Declined', CANCELLED: 'Cancelled' };

function monthLabel(month) {
  const [y, m] = month.split('-').map(Number);
  return new Date(y, m - 1, 1).toLocaleDateString('en-IN', { month: 'long', year: 'numeric' });
}

/** Getting paid: balance, a payout request, bank account, and monthly statements. */
export default function MoneyPanel({ token }) {
  const [money, setMoney] = useState(null);
  const [amount, setAmount] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const [editingBank, setEditingBank] = useState(false);
  const [bank, setBank] = useState({ bank_account_holder: '', bank_account_number: '', bank_ifsc: '', bank_name: '' });
  const [months, setMonths] = useState([]);
  const [month, setMonth] = useState('');
  const [statement, setStatement] = useState(null);

  const load = useCallback(async () => {
    try { setMoney((await apiFetch('/seller/money', { token })).data); }
    catch (e) { setError(e.message); }
  }, [token]);

  useEffect(() => { load(); }, [load]);
  useEffect(() => {
    apiFetch('/seller/statements', { token }).then((r) => { setMonths(r.data || []); setMonth((r.data || [])[0] || ''); }).catch(() => {});
  }, [token]);
  useEffect(() => {
    if (!month) return;
    setStatement(null);
    apiFetch(`/seller/statements/${month}`, { token }).then((r) => setStatement(r.data)).catch((e) => setError(e.message));
  }, [month, token]);

  const run = async (fn, done) => {
    setBusy(true); setError(''); setNotice('');
    try { await fn(); setNotice(done); await load(); }
    catch (e) { setError(e.message); }
    finally { setBusy(false); }
  };

  const open = money?.requests?.find((r) => r.status === 'REQUESTED');

  if (!money) return <p className="text-sm text-ink-muted">{error || 'Loading…'}</p>;

  return (
    <div className="space-y-6">
      <div className="grid gap-3 sm:grid-cols-3">
        {[['Balance', money.balance], ['Payable now', money.withdrawable], ['Pending (not yet payable)', money.pending]].map(([label, value]) => (
          <div key={label} className="rounded-card border border-line bg-surface p-4"><span className="text-xs text-ink-muted">{label}</span><strong className="block text-lg text-ink">{formatINR(value || 0)}</strong></div>
        ))}
      </div>
      {notice && <p role="status" className="rounded-card bg-success-soft p-3 text-sm text-success">{notice}</p>}
      {error && <p role="alert" className="rounded-card bg-danger-soft p-3 text-sm text-danger">{error}</p>}

      <section className="space-y-3 rounded-card border border-line bg-surface p-4" aria-label="Payout request">
        <h2 className="font-bold text-ink">Ask to be paid</h2>
        {open ? (
          <div className="space-y-2 text-sm text-ink">
            <p>You asked for <strong>{formatINR(open.amount)}</strong>. The team will send it to your bank account and add the reference here.</p>
            <button type="button" className={ghost} disabled={busy} onClick={() => run(() => apiFetch(`/seller/payout-requests/${open.id}`, { method: 'DELETE', token }), 'Request cancelled.')}>Cancel request</button>
          </div>
        ) : money.blocker ? (
          <p className="text-sm text-ink-muted">{money.blocker}</p>
        ) : (
          <form className="flex flex-wrap items-end gap-2" onSubmit={(e) => {
            e.preventDefault();
            run(() => apiFetch('/seller/payout-requests', { method: 'POST', token, body: amount ? { amount: Number(amount) } : {} }), 'Request sent.').then(() => setAmount(''));
          }}>
            <div className="min-w-40 flex-1">
              <label htmlFor="payout-amount" className="block text-xs font-bold text-ink">Amount (₹)</label>
              <input id="payout-amount" type="number" min="0" step="0.01" className={`${input} mt-1`} value={amount} onChange={(e) => setAmount(e.target.value)} placeholder={`All payable (${formatINR(money.withdrawable)})`} />
            </div>
            <button className={button} disabled={busy || money.withdrawable <= 0}>Request payout</button>
            <p className="w-full text-xs text-ink-muted">Smallest request: {formatINR(money.minimum_payout)}. Earnings become payable once an order is delivered and the return window has passed.</p>
          </form>
        )}
        {money.requests?.length > 0 && (
          <ul className="divide-y divide-line text-sm text-ink">
            {money.requests.map((r) => (
              <li key={r.id} className="flex flex-wrap justify-between gap-2 py-2">
                <span>{formatINR(r.amount)} · {STATUS[r.status] || r.status}{r.reference ? ` · ${r.reference}` : ''}{r.decision_note ? ` · ${r.decision_note}` : ''}</span>
                <span className="text-xs text-ink-muted">{new Date(r.requested_at || r.created_at).toLocaleDateString('en-IN')}</span>
              </li>
            ))}
          </ul>
        )}
      </section>

      <section className="space-y-3 rounded-card border border-line bg-surface p-4" aria-label="Bank account">
        <h2 className="font-bold text-ink">Bank account for payouts</h2>
        {money.bank ? (
          <p className="text-sm text-ink">{money.bank.holder} · {money.bank.bank} {money.bank.ifsc} · ••••{money.bank.account_last4}</p>
        ) : <p className="text-sm text-ink-muted">No bank account on file. Add it in your application.</p>}
        {money.pending_bank && (
          <div className="rounded-card bg-warning-soft p-3 text-xs text-ink">
            New account ending {money.pending_bank.account_last4} is waiting to be confirmed. Payouts continue to the current account until it is.
            <button type="button" className="ml-2 font-bold text-accent" disabled={busy} onClick={() => run(() => apiFetch('/seller/bank/pending', { method: 'DELETE', token }), 'Change withdrawn.')}>Withdraw</button>
          </div>
        )}
        {money.bank && !money.pending_bank && !editingBank && <button type="button" className={ghost} onClick={() => setEditingBank(true)}>Change bank account</button>}
        {editingBank && (
          <form className="grid gap-2 sm:grid-cols-2" onSubmit={(e) => {
            e.preventDefault();
            run(() => apiFetch('/seller/bank', { method: 'POST', token, body: bank }), 'Sent for confirmation. Payouts continue to the current account until then.').then(() => setEditingBank(false));
          }}>
            {[['bank_account_holder', 'Account holder'], ['bank_account_number', 'Account number'], ['bank_ifsc', 'IFSC'], ['bank_name', 'Bank name']].map(([key, label]) => (
              <div key={key}>
                <label htmlFor={`bank-${key}`} className="block text-xs font-bold text-ink">{label}</label>
                <input id={`bank-${key}`} className={`${input} mt-1`} value={bank[key]} onChange={(e) => setBank((v) => ({ ...v, [key]: e.target.value }))} required={key !== 'bank_name'} />
              </div>
            ))}
            <p className="text-xs text-ink-muted sm:col-span-2">The team confirms new bank details before any money moves to them.</p>
            <div className="flex gap-2 sm:col-span-2"><button className={button} disabled={busy}>Send for confirmation</button><button type="button" className={ghost} onClick={() => setEditingBank(false)}>Cancel</button></div>
          </form>
        )}
      </section>

      <section className="space-y-3 rounded-card border border-line bg-surface p-4" aria-label="Statements">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <h2 className="font-bold text-ink">Monthly statement</h2>
          <div className="flex gap-2">
            <select aria-label="Month" className={`${input} w-48`} value={month} onChange={(e) => setMonth(e.target.value)}>
              {months.map((m) => <option key={m} value={m}>{monthLabel(m)}</option>)}
            </select>
            <button type="button" className={ghost} disabled={!month} onClick={() => apiDownload(`/seller/statements/${month}/csv`, { token, filename: `statement-${month}.csv` }).catch((e) => setError(e.message))}>Download CSV</button>
          </div>
        </div>
        {statement ? (
          <dl className="grid gap-x-6 gap-y-1 text-sm text-ink sm:grid-cols-2">
            {[
              ['Opening balance', statement.opening_balance], ['Orders', statement.orders, true], ['Gross sales', statement.gross_sales], ['Refunds', -statement.refunds],
              ['Commission', -statement.commission], ['GST on commission', -statement.gst_on_commission], ['TCS', -statement.tcs], ['TDS', -statement.tds],
              ['Earnings', statement.earnings], ['Adjustments', statement.adjustments], ['Paid out', -statement.payouts], ['Closing balance', statement.closing_balance],
            ].map(([label, value, plain]) => (
              <div key={label} className="flex justify-between border-b border-line py-1"><dt className="text-ink-muted">{label}</dt><dd className="font-bold">{plain ? value : formatINR(value)}</dd></div>
            ))}
          </dl>
        ) : <p className="text-sm text-ink-muted">Loading…</p>}
        <p className="text-xs text-ink-muted">Tax lines use the rates the marketplace had set at the time of each sale, and are for your records, not tax advice.</p>
      </section>
    </div>
  );
}
