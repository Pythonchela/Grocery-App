'use client';

import React, { useCallback, useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import {
  Store, RefreshCw, AlertCircle, Search, Landmark, Ban, CheckCircle2, X, Plus,
} from 'lucide-react';
import { useAdminAuth } from './AdminAuthContext';
import { apiFetch, formatINR } from '../../lib/apiClient';
import ShopProfileSection from './ShopProfileSection';
import { useStoreConfig } from './useStoreConfig';

const STATUS_TABS = [
  { key: '', label: 'All' },
  { key: 'ACTIVE', label: 'Active' },
  { key: 'PENDING', label: 'Pending' },
  { key: 'SUSPENDED', label: 'Suspended' },
];

const STATUS_TONE = {
  ACTIVE: 'bg-success/10 text-success',
  PENDING: 'bg-warning/10 text-warning',
  SUSPENDED: 'bg-danger/10 text-danger',
};

/**
 * The full seller roster: every merchant regardless of status, with commission,
 * standing and payout controls.
 *
 * Separate screen from the applications queue on purpose — that one is a
 * worklist that empties as you clear it, this one is a directory you come back
 * to. An approved seller who needs their commission renegotiated or their
 * account suspended for a policy breach isn't "in review" any more, so they
 * would never surface in that queue again.
 */
export default function SellerRosterClient() {
  const { token } = useAdminAuth();
  const router = useRouter();
  const store = useStoreConfig();
  // A single-business store has no vendors: this screen is just the owner's own shop.
  const single = store ? !store.vendors_enabled : false;

  const [statusFilter, setStatusFilter] = useState('');
  const [search, setSearch] = useState('');
  const [rows, setRows] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [editing, setEditing] = useState(null); // the seller row being edited
  const [adding, setAdding] = useState(false);

  const load = useCallback(async () => {
    setLoading(true); setError('');
    try {
      const qs = statusFilter ? `?status=${statusFilter}` : '';
      const res = await apiFetch(`/admin/sellers${qs}`, { token });
      setRows(res.data || []);
    } catch (err) {
      setError(err.message);
    } finally { setLoading(false); }
  }, [token, statusFilter]);

  useEffect(() => { load(); }, [load]);

  // In a single-business store, go straight to the owner's shop.
  useEffect(() => {
    if (!single || editing) return;
    const house = rows.find(r => r.is_house);
    if (house) setEditing(house);
  }, [single, rows, editing]);

  const visible = search.trim()
    ? rows.filter(s =>
        s.display_name?.toLowerCase().includes(search.trim().toLowerCase())
        || s.user?.email?.toLowerCase().includes(search.trim().toLowerCase()))
    : rows;

  const onSaved = (updated) => {
    setRows(prev => prev.map(r => (r.id === updated.id ? { ...r, ...updated } : r)));
    // The owner's own shop stays open after saving; a vendor's drawer closes.
    setEditing(prev => (single ? { ...prev, ...updated } : null));
  };

  return (
    <div className="space-y-4">
      <header className="flex items-center justify-between gap-3">
        <div>
          <h2 className="text-lg font-black text-ink flex items-center gap-2">
            <Store className="w-5 h-5 text-accent" /> {single ? 'My shop' : 'All sellers'}
          </h2>
          <p className="text-xs text-ink-muted font-medium mt-0.5">
            {single
              ? 'How your shop shows to shoppers, when it is open, and where it ships from.'
              : 'Commission, standing and payout adjustments for every merchant.'}
          </p>
        </div>
        <div className="flex items-center gap-3">
          {!single && <button onClick={() => setAdding(true)} className="btn-primary flex items-center gap-1 px-3 py-2 text-xs"><Plus className="h-4 w-4" /> Add seller</button>}
          <button onClick={load} className="text-ink-subtle hover:text-ink" aria-label="Refresh"><RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} /></button>
        </div>
      </header>

      {!single && (
      <div className="flex items-center justify-between gap-3">
        <div className="flex gap-1 border-b border-line">
          {STATUS_TABS.map(t => (
            <button
              key={t.key || 'all'}
              onClick={() => setStatusFilter(t.key)}
              className={`px-4 py-2 text-xs font-black border-b-2 transition ${
                statusFilter === t.key
                  ? 'border-accent text-accent'
                  : 'border-transparent text-ink-subtle hover:text-ink'
              }`}
            >
              {t.label}
            </button>
          ))}
        </div>

        <div className="relative">
          <Search className="w-3.5 h-3.5 absolute left-2.5 top-1/2 -translate-y-1/2 text-ink-subtle" />
          <input
            value={search}
            onChange={e => setSearch(e.target.value)}
            placeholder="Search name or email"
            className="pl-8 pr-3 py-1.5 text-xs font-semibold bg-surface border border-line rounded-control focus:outline-none focus:border-accent w-48"
          />
        </div>
      </div>
      )}

      {error && (
        <p className="text-xs font-bold text-danger flex items-center gap-1">
          <AlertCircle className="w-3.5 h-3.5" /> {error}
        </p>
      )}

      {single ? null : loading ? (
        <div className="py-12 flex justify-center">
          <RefreshCw className="w-5 h-5 animate-spin text-accent" />
        </div>
      ) : visible.length === 0 ? (
        <div className="py-12 text-center text-ink-subtle">
          <Store className="w-8 h-8 mx-auto mb-2" />
          <p className="text-sm font-bold">No sellers here</p>
        </div>
      ) : (
        <div className="space-y-2">
          {visible.map(s => (
            <div key={s.id} className="flex items-center gap-3 p-3.5 border border-line rounded-card bg-surface">
              <div className="flex-1 min-w-0">
                <p className="text-sm font-black text-ink truncate">{s.display_name}</p>
                <p className="text-[11px] text-ink-subtle font-semibold truncate">
                  {s.user?.email || 'No linked account'} · {s.products_count ?? 0} product{s.products_count === 1 ? '' : 's'}
                </p>
              </div>
              <div className="text-right shrink-0">
                <p className="text-xs font-black text-ink">{formatINR(s.payout_balance)}</p>
                <p className="text-[10px] text-ink-subtle font-semibold">{s.commission_rate}% commission</p>
              </div>
              <span className={`text-[10px] font-black px-2 py-1 rounded-pill shrink-0 ${STATUS_TONE[s.status] || 'bg-surface-muted text-ink-muted'}`}>
                {s.status}
              </span>
              <button
                onClick={() => setEditing(s)}
                className="text-[11px] font-bold text-accent hover:underline shrink-0"
              >
                Manage
              </button>
            </div>
          ))}
        </div>
      )}

      {editing && (
        <ManageSellerDrawer
          seller={editing}
          token={token}
          onClose={() => (single ? router.push('/admin') : setEditing(null))}
          onSaved={onSaved}
        />
      )}
      {adding && <AddSellerDialog token={token} onClose={() => setAdding(false)} onCreated={() => { setAdding(false); load(); }} />}
    </div>
  );
}

function AddSellerDialog({ token, onClose, onCreated }) {
  const [email, setEmail] = useState('');
  const [user, setUser] = useState(null);
  const [name, setName] = useState('');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  const findUser = async () => {
    setBusy(true); setError(''); setUser(null);
    try {
      const res = await apiFetch(`/admin/users?q=${encodeURIComponent(email.trim())}`, { token });
      const match = (res.data || []).find(u => u.email?.toLowerCase() === email.trim().toLowerCase());
      if (!match) throw new Error('Ask this person to create a shopper account first, then search again.');
      if (match.role !== 'CUSTOMER') throw new Error('Choose a shopper account that is not already staff or a seller.');
      if (match.status !== 'ACTIVE') throw new Error('Unblock this account before adding a shop.');
      setUser(match); setName(match.name || '');
    } catch (e) { setError(e.message); }
    finally { setBusy(false); }
  };

  const create = async () => {
    setBusy(true); setError('');
    try {
      await apiFetch('/admin/sellers', { method: 'POST', token, body: { user_id: user.id, display_name: name.trim() } });
      onCreated();
    } catch (e) { setError(e.message); }
    finally { setBusy(false); }
  };

  return <div className="fixed inset-0 z-50 flex items-center justify-center bg-inverse/70 p-4" role="dialog" aria-modal="true" aria-label="Add seller">
    <div className="w-full max-w-md space-y-4 rounded-panel bg-surface p-5">
      <div className="flex items-center justify-between"><h3 className="font-black text-ink">Add seller</h3><button onClick={onClose} aria-label="Close"><X className="h-4 w-4" /></button></div>
      <p className="text-xs text-ink-muted">The seller needs an existing account. Their shop stays pending until verification is approved.</p>
      <label className="block text-xs font-bold text-ink">Account email<input type="email" value={email} onChange={e => { setEmail(e.target.value); setUser(null); }} className="mt-1 w-full rounded-control border border-line p-2" /></label>
      <button type="button" onClick={findUser} disabled={busy || !email.trim()} className="rounded-control border border-line px-3 py-2 text-xs font-bold text-ink">Find account</button>
      {user && <><p className="text-xs text-ink-muted">{user.name} · {user.email}</p><label className="block text-xs font-bold text-ink">Shop name<input value={name} onChange={e => setName(e.target.value)} className="mt-1 w-full rounded-control border border-line p-2" /></label><button onClick={create} disabled={busy || !name.trim()} className="btn-primary px-4 py-2 text-xs">Create pending shop</button></>}
      {error && <p role="alert" className="text-xs text-danger">{error}</p>}
    </div>
  </div>;
}

/** How the shop has been doing: the numbers behind keeping, coaching or suspending it. */
function PerformanceSection({ seller, token }) {
  const [days, setDays] = useState(30);
  const [data, setData] = useState(null);
  const [error, setError] = useState('');

  useEffect(() => {
    let cancelled = false;
    setData(null);
    setError('');
    apiFetch(`/admin/sellers/${seller.id}/performance?days=${days}`, { token })
      .then(res => { if (!cancelled) setData(res.data); })
      .catch(err => { if (!cancelled) setError(err.message); });
    return () => { cancelled = true; };
  }, [seller.id, token, days]);

  const pct = v => (v == null ? '—' : `${v}%`);
  const tiles = data && [
    ['Orders', data.orders],
    ['Sales', formatINR(data.sales)],
    ['Shop earned', formatINR(data.earned)],
    ['Orders accepted', pct(data.acceptance_rate)],
    ['Declined', data.declined],
    ['Missed (no answer)', data.missed],
    ['Late to pack now', data.late_to_pack_now],
    ['Returns', `${data.returns}${data.return_rate == null ? '' : ` (${data.return_rate}%)`}`],
    ['Live products', data.products_live],
    ['Drafts', data.products_draft],
    ['Low stock', data.products_low_stock],
  ];

  return (
    <section className="space-y-3" aria-label="Performance">
      <div className="flex items-center justify-between gap-2">
        <h4 className="text-xs font-black text-ink uppercase tracking-wide">Performance</h4>
        <div className="flex gap-1">
          {[7, 30, 90].map(d => (
            <button key={d} type="button" onClick={() => setDays(d)} aria-pressed={days === d}
              className={`px-2.5 py-1 rounded-pill text-[11px] font-bold ${days === d ? 'bg-primary text-on-primary' : 'bg-surface-muted text-ink-muted'}`}>
              {d} days
            </button>
          ))}
        </div>
      </div>
      {error && <p className="text-xs font-bold text-danger">{error}</p>}
      {!data && !error && <p className="text-xs text-ink-subtle">Loading…</p>}
      {tiles && (
        <div className="grid grid-cols-2 gap-2">
          {tiles.map(([label, value]) => (
            <div key={label} className="rounded-control border border-line bg-surface-muted px-3 py-2">
              <p className="text-base font-black text-ink">{value}</p>
              <p className="text-[10px] font-bold text-ink-subtle uppercase">{label}</p>
            </div>
          ))}
        </div>
      )}
    </section>
  );
}

/** Edit commission/standing, and issue a one-off payout adjustment. */
function ManageSellerDrawer({ seller, token, onClose, onSaved }) {
  const [commission, setCommission] = useState(String(seller.commission_rate));
  const [status, setStatus] = useState(seller.status);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');

  const [adjAmount, setAdjAmount] = useState('');
  const [adjNote, setAdjNote] = useState('');

  const [pickup, setPickup] = useState({
    pickup_line1: seller.pickup_line1 || '',
    pickup_city: seller.pickup_city || '',
    pickup_state: seller.pickup_state || '',
    pickup_pincode: seller.pickup_pincode || '',
    pickup_phone: seller.pickup_phone || '',
    pickup_code: seller.pickup_code || '',
  });

  const savePickup = async () => {
    setBusy(true); setError(''); setNotice('');
    try {
      // Empty means "not set": the API treats these as nullable.
      const body = Object.fromEntries(Object.entries(pickup).map(([k, v]) => [k, v.trim() === '' ? null : v.trim()]));
      const res = await apiFetch(`/admin/sellers/${seller.id}`, { method: 'PUT', token, body });
      onSaved(res.data);
      setNotice('Pickup address saved.');
    } catch (err) {
      setError(err.message);
    } finally { setBusy(false); }
  };

  const saveTerms = async () => {
    setBusy(true); setError(''); setNotice('');
    try {
      const res = await apiFetch(`/admin/sellers/${seller.id}`, {
        method: 'PUT', token,
        body: { commission_rate: Number(commission), status },
      });
      onSaved(res.data);
      setNotice('Saved.');
    } catch (err) {
      setError(err.message);
    } finally { setBusy(false); }
  };

  const submitAdjustment = async () => {
    const amount = Number(adjAmount);
    if (!amount || !adjNote.trim()) {
      setError('An adjustment needs a non-zero amount and a note explaining it.');
      return;
    }

    setBusy(true); setError(''); setNotice('');
    try {
      await apiFetch(`/admin/sellers/${seller.id}/payout-adjustment`, {
        method: 'POST', token,
        body: { amount, note: adjNote.trim() },
      });
      setAdjAmount(''); setAdjNote('');
      setNotice(`Payout ${amount > 0 ? 'credited' : 'debited'} ₹${Math.abs(amount).toLocaleString('en-IN')}.`);
      // The balance shown in the list is now stale — reload it via onSaved
      // with the delta applied locally rather than forcing a full refetch.
      onSaved({ id: seller.id, payout_balance: (Number(seller.payout_balance) || 0) + amount });
    } catch (err) {
      setError(err.message);
    } finally { setBusy(false); }
  };

  return (
    <div className="fixed inset-0 z-50 bg-inverse/60 backdrop-blur-sm flex justify-end">
      <div className="w-screen max-w-md bg-surface border-l border-line overflow-y-auto p-5 space-y-5">
        <header className="flex items-start justify-between gap-3">
          <div>
            <h3 className="text-base font-black text-ink">{seller.display_name}</h3>
            <p className="text-[11px] text-ink-subtle font-semibold">{seller.user?.email}</p>
          </div>
          <button onClick={onClose} className="text-ink-subtle hover:text-ink" aria-label="Close">
            <X className="w-4 h-4" />
          </button>
        </header>

        {notice && <p className="text-xs font-bold text-success">{notice}</p>}
        {error && (
          <p className="text-xs font-bold text-danger flex items-center gap-1">
            <AlertCircle className="w-3.5 h-3.5" /> {error}
          </p>
        )}

        <PerformanceSection seller={seller} token={token} />

        <ShopProfileSection seller={seller} token={token} onSaved={onSaved} />

        {/* Where this seller's goods are collected from. Delivery times, fees and
            which speeds are possible are all worked out from here. */}
        <section className="space-y-3">
          <h4 className="text-xs font-black text-ink uppercase tracking-wide">Pickup address</h4>
          <p className="text-[11px] text-ink-subtle font-medium">
            Where couriers collect this seller&apos;s orders. Left empty, the marketplace warehouse is used.
          </p>
          {[
            ['pickup_line1', 'Street address'],
            ['pickup_city', 'City'],
            ['pickup_state', 'State'],
            ['pickup_pincode', 'PIN code'],
            ['pickup_phone', 'Phone at pickup'],
            ['pickup_code', 'Courier pickup name (Shiprocket / Delhivery)'],
          ].map(([key, label]) => (
            <label key={key} className="block">
              <span className="block text-[10px] font-bold text-ink-subtle uppercase mb-1">{label}</span>
              <input
                value={pickup[key]}
                onChange={e => setPickup(p => ({ ...p, [key]: e.target.value }))}
                inputMode={key === 'pickup_pincode' ? 'numeric' : undefined}
                maxLength={key === 'pickup_pincode' ? 6 : undefined}
                className="w-full bg-surface border border-line rounded-control px-3 py-2 text-sm font-semibold text-ink focus:outline-none focus:border-accent"
              />
            </label>
          ))}
          <button onClick={savePickup} disabled={busy}
            className="btn-primary text-sm py-2.5 px-5 disabled:opacity-50">
            {busy ? 'Saving…' : 'Save pickup address'}
          </button>
        </section>

        {/* Terms and standing: not for the owner's own shop, which pays no commission. */}
        {!seller.is_house && (
        <section className="space-y-3">
          <h4 className="text-xs font-black text-ink uppercase tracking-wide">Terms &amp; standing</h4>

          <label className="block">
            <span className="block text-[10px] font-bold text-ink-subtle uppercase mb-1">Commission rate (%)</span>
            <input
              type="number" min="0" max="100" step="0.5"
              value={commission}
              onChange={e => setCommission(e.target.value)}
              className="w-full bg-surface border border-line rounded-control px-3 py-2 text-sm font-bold text-ink focus:outline-none focus:border-accent"
            />
            <span className="block text-[10px] text-ink-subtle font-medium mt-1">
              Applies to future sales only — past order lines keep the rate they were sold under.
            </span>
          </label>

          <label className="block">
            <span className="block text-[10px] font-bold text-ink-subtle uppercase mb-1">Status</span>
            <select
              value={status}
              onChange={e => setStatus(e.target.value)}
              className="w-full bg-surface border border-line rounded-control px-3 py-2 text-sm font-bold text-ink focus:outline-none focus:border-accent"
            >
              <option value="PENDING">Pending</option>
              <option value="ACTIVE">Active</option>
              <option value="SUSPENDED">Suspended</option>
            </select>
            {status === 'ACTIVE' && seller.status !== 'ACTIVE' && (
              <span className="block text-[10px] text-warning font-bold mt-1 flex items-center gap-1">
                <AlertCircle className="w-3 h-3" /> Refused unless KYC is already approved.
              </span>
            )}
            {status === 'SUSPENDED' && (
              <span className="block text-[10px] text-ink-subtle font-medium mt-1 flex items-center gap-1">
                <Ban className="w-3 h-3" /> Their whole catalog leaves the storefront immediately.
              </span>
            )}
          </label>

          <button onClick={saveTerms} disabled={busy}
            className="btn-primary text-sm py-2.5 px-5 disabled:opacity-50">
            {busy ? 'Saving…' : 'Save'}
          </button>
        </section>
        )}

        {/* Payout adjustment */}
        {!seller.is_house && (
        <section className="space-y-3 pt-4 border-t border-line">
          <h4 className="text-xs font-black text-ink uppercase tracking-wide flex items-center gap-1.5">
            <Landmark className="w-3.5 h-3.5 text-accent" /> Payout adjustment
          </h4>
          <p className="text-[11px] text-ink-subtle font-medium">
            Current balance: <strong className="text-ink">{formatINR(seller.payout_balance)}</strong>.
            Positive credits the seller, negative debits them — for goodwill, a chargeback, or a
            manual correction outside the normal sale/refund flow.
          </p>

          <div className="grid grid-cols-2 gap-2">
            <input
              type="number" step="0.01"
              value={adjAmount}
              onChange={e => setAdjAmount(e.target.value)}
              placeholder="Amount (± ₹)"
              className="bg-surface border border-line rounded-control px-3 py-2 text-sm font-bold text-ink focus:outline-none focus:border-accent"
            />
            <input
              value={adjNote}
              onChange={e => setAdjNote(e.target.value)}
              placeholder="Reason"
              className="bg-surface border border-line rounded-control px-3 py-2 text-sm font-semibold text-ink focus:outline-none focus:border-accent"
            />
          </div>

          <button
            onClick={submitAdjustment}
            disabled={busy || !adjAmount || !adjNote.trim()}
            className="w-full justify-center flex items-center gap-1.5 text-xs font-black py-2.5 rounded-control border border-line text-ink hover:bg-surface-muted disabled:opacity-50"
          >
            <CheckCircle2 className="w-3.5 h-3.5" /> Apply adjustment
          </button>
        </section>
        )}
      </div>
    </div>
  );
}
