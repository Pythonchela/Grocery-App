'use client';

import React, { useCallback, useEffect, useRef, useState } from 'react';
import {
  ChevronRight, X, CheckCircle2, Clock, Truck, RefreshCw, Search, AlertCircle, Ban, PackageCheck, MapPin,
} from 'lucide-react';
import { apiFetch, mapOrder, ORDER_STAGES, STAGE_LABELS, formatINR } from '../../lib/apiClient';
import { OptionPicks } from '../storefront/OptionPicker';
import { useStoreConfig } from './useStoreConfig';

const PER_PAGE = 20;

/** Why staff cancel an order, as codes the store can later count by cause. */
export const CANCEL_CODES = [
  ['CUSTOMER_REQUEST', 'Customer asked to cancel'],
  ['SELLER_UNRESPONSIVE', 'Shop is not responding'],
  ['OUT_OF_STOCK', 'Item is out of stock'],
  ['ADDRESS_UNSERVICEABLE', 'Cannot deliver to the address'],
  ['PAYMENT_ISSUE', 'Payment problem'],
  ['FRAUD_SUSPECTED', 'Suspected fraud'],
  ['DUPLICATE_ORDER', 'Duplicate order'],
  ['OTHER', 'Another reason'],
];

export const STATUS_COLORS = {
  PENDING: 'bg-warning-soft text-warning border-warning',
  CONFIRMED: 'bg-accent-soft text-accent border-accent',
  PACKED: 'bg-accent-soft text-accent border-accent',
  SHIPPED: 'bg-accent-soft text-accent border-accent',
  OUT_FOR_DELIVERY: 'bg-warning-soft text-warning border-warning',
  DELIVERED: 'bg-success-soft text-success border-success',
  CANCELLED: 'bg-danger-soft text-danger border-danger',
};

const inputCls = 'bg-surface border border-line rounded-control px-3 py-2 text-xs font-semibold text-ink focus:outline-none focus:border-accent';

/** Orders that can still be cancelled (the server has the final say). */
const CANCELLABLE = ['PENDING', 'CONFIRMED', 'PACKED'];
/** Orders a courier can still be booked for. */
const BOOKABLE = ['CONFIRMED', 'PACKED'];

/**
 * Every order, with what an operator needs to run the day: find an order,
 * see who sold what and where the parcel is, book the courier, move it along
 * or cancel it (which refunds a paid order).
 */
export default function OrdersClient({ token }) {
  const store = useStoreConfig();
  const showSellers = store ? store.vendors_enabled : false;

  const [filters, setFilters] = useState({ status: '', search: '', payment_method: '', payment_status: '', seller: '', from: '', to: '' });
  const [searchText, setSearchText] = useState('');
  const [page, setPage] = useState(1);
  const [orders, setOrders] = useState([]);
  const [counts, setCounts] = useState({});
  const [meta, setMeta] = useState({ total: 0, last_page: 1 });
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [sellers, setSellers] = useState([]);
  const [selectedId, setSelectedId] = useState(null);
  const requestRef = useRef(0);

  // The search box waits for a pause in typing before asking the server.
  useEffect(() => {
    const t = setTimeout(() => {
      setFilters((f) => (f.search === searchText.trim() ? f : { ...f, search: searchText.trim() }));
      setPage(1);
    }, 350);
    return () => clearTimeout(t);
  }, [searchText]);

  useEffect(() => {
    if (!showSellers) return;
    apiFetch('/admin/sellers?per_page=200', { token })
      .then((res) => setSellers(res.data || []))
      .catch(() => {});
  }, [showSellers, token]);

  const load = useCallback(async () => {
    const ticket = ++requestRef.current;
    setLoading(true); setError('');
    try {
      const params = new URLSearchParams({ per_page: String(PER_PAGE), page: String(page) });
      Object.entries(filters).forEach(([k, v]) => { if (v) params.set(k, v); });
      const res = await apiFetch(`/admin/orders?${params}`, { token });
      if (ticket !== requestRef.current) return; // a newer search has superseded this one
      setOrders((res.data || []).map(mapOrder));
      setCounts(res.facets?.status || {});
      setMeta({ total: res.meta?.total ?? res.count ?? 0, last_page: res.meta?.last_page ?? 1 });
    } catch (err) {
      if (ticket === requestRef.current) setError(err.message);
    } finally {
      if (ticket === requestRef.current) setLoading(false);
    }
  }, [token, filters, page]);

  useEffect(() => { load(); }, [load]);

  const setFilter = (key, value) => { setFilters((f) => ({ ...f, [key]: value })); setPage(1); };
  const clearFilters = () => {
    setSearchText('');
    setFilters({ status: '', search: '', payment_method: '', payment_status: '', seller: '', from: '', to: '' });
    setPage(1);
  };
  const hasFilters = Object.values(filters).some(Boolean);

  const totalAll = Object.values(counts).reduce((a, b) => a + Number(b), 0);
  const selected = orders.find((o) => o._id === selectedId) || null;

  const replaceOrder = (updated) => setOrders((prev) => prev.map((o) => (o._id === updated._id ? { ...o, ...updated } : o)));

  return (
    <div className="space-y-4">
      {/* Status tabs, with how many orders each holds */}
      <div className="flex items-center gap-2 flex-wrap">
        {[['', 'All', totalAll], ...ORDER_STAGES.map((s) => [s, STAGE_LABELS[s], counts[s] || 0]), ['CANCELLED', 'Cancelled', counts.CANCELLED || 0]].map(([key, label, n]) => (
          <button
            key={key || 'all'}
            onClick={() => setFilter('status', key)}
            className={`px-4 py-2 rounded-pill text-xs font-bold border transition ${filters.status === key ? 'bg-inverse text-ink-inverse border-line-strong' : 'bg-surface text-ink-muted border-line hover:border-line-strong hover:text-ink'}`}
          >
            {label}
            <span className="ml-1.5 bg-surface-sunken text-ink-muted px-1.5 py-0.5 rounded-pill">{n}</span>
          </button>
        ))}
      </div>

      {/* Find an order */}
      <div className="flex items-center gap-2 flex-wrap">
        <div className="relative">
          <Search className="w-3.5 h-3.5 absolute left-2.5 top-1/2 -translate-y-1/2 text-ink-subtle" />
          <input
            value={searchText}
            onChange={(e) => setSearchText(e.target.value)}
            placeholder="Order no., customer, phone, city, PIN, tracking"
            aria-label="Search orders"
            className={`${inputCls} pl-8 w-72`}
          />
        </div>
        <select value={filters.payment_method} onChange={(e) => setFilter('payment_method', e.target.value)} aria-label="Payment method" className={inputCls}>
          <option value="">Any payment</option>
          <option value="COD">Cash on delivery</option>
          <option value="UPI">UPI</option>
          <option value="CARD">Card</option>
          <option value="NETBANKING">Net banking</option>
        </select>
        <select value={filters.payment_status} onChange={(e) => setFilter('payment_status', e.target.value)} aria-label="Payment status" className={inputCls}>
          <option value="">Any payment status</option>
          <option value="PENDING">Payment pending</option>
          <option value="PAID">Paid</option>
          <option value="REFUNDED">Refunded</option>
          <option value="FAILED">Failed</option>
        </select>
        {showSellers && (
          <select value={filters.seller} onChange={(e) => setFilter('seller', e.target.value)} aria-label="Shop" className={inputCls}>
            <option value="">All shops</option>
            {sellers.map((s) => <option key={s.id} value={s.id}>{s.display_name}</option>)}
          </select>
        )}
        <input type="date" value={filters.from} onChange={(e) => setFilter('from', e.target.value)} aria-label="From date" className={inputCls} />
        <span className="text-ink-subtle text-xs">to</span>
        <input type="date" value={filters.to} onChange={(e) => setFilter('to', e.target.value)} aria-label="To date" className={inputCls} />
        {hasFilters && (
          <button onClick={clearFilters} className="text-[11px] font-bold text-accent hover:underline">Clear filters</button>
        )}
        <button onClick={load} className="ml-auto text-ink-subtle hover:text-ink" aria-label="Refresh orders">
          <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} />
        </button>
      </div>

      {error && <p className="text-xs font-bold text-danger flex items-center gap-1"><AlertCircle className="w-3.5 h-3.5" /> {error}</p>}

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
        <div className={`${selected ? 'lg:col-span-1' : 'lg:col-span-3'} space-y-3`}>
          {loading && orders.length === 0 && <div className="text-center py-10 text-ink-subtle font-bold">Loading orders...</div>}
          {!loading && orders.length === 0 && (
            <div className="text-center py-10 text-ink-subtle font-bold bg-surface border border-line rounded-card">
              {hasFilters ? 'No orders match these filters.' : 'No orders yet.'}
            </div>
          )}
          {orders.map((order) => (
            <button
              key={order._id}
              onClick={() => setSelectedId(selectedId === order._id ? null : order._id)}
              className={`w-full text-left bg-surface border rounded-card p-4 transition hover:shadow-card ${selectedId === order._id ? 'border-line-strong ring-2 ring-line-strong/20' : 'border-line'}`}
            >
              <div className="flex items-start justify-between gap-3">
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 mb-1 flex-wrap">
                    <span className="font-black text-ink text-sm">{order.id}</span>
                    <span className={`text-[10px] font-black px-2 py-0.5 rounded-pill border ${STATUS_COLORS[order.status] || 'bg-surface-muted text-ink-muted border-line'}`}>
                      {STAGE_LABELS[order.status] || order.status}
                    </span>
                  </div>
                  <p className="text-xs text-ink-muted font-bold">{order.customerName}</p>
                  <p className="text-[11px] text-ink-subtle font-medium">{order.city}, {order.pincode}</p>
                  {showSellers && order.shopNames.length > 0 && (
                    <p className="text-[11px] text-ink-subtle font-medium truncate">{order.shopNames.join(', ')}</p>
                  )}
                  <div className="flex items-center gap-2 mt-1.5">
                    <span className="text-xs font-black text-ink">{formatINR(order.totalAmount)}</span>
                    <span className="text-[10px] text-ink-subtle">{order.paymentMethod} · {order.paymentStatus}</span>
                  </div>
                </div>
                <div className="text-right shrink-0">
                  <p className="text-[10px] text-ink-subtle font-medium">{order.createdAt}</p>
                  <ChevronRight className={`w-4 h-4 text-ink-subtle mt-2 mx-auto transition ${selectedId === order._id ? 'rotate-90 text-ink' : ''}`} />
                </div>
              </div>
            </button>
          ))}

          {meta.last_page > 1 && (
            <div className="flex items-center justify-between pt-1">
              <button disabled={page <= 1} onClick={() => setPage((p) => p - 1)} className="text-xs font-bold text-accent disabled:text-ink-subtle">Previous</button>
              <span className="text-[11px] text-ink-subtle font-semibold">Page {page} of {meta.last_page} · {meta.total} orders</span>
              <button disabled={page >= meta.last_page} onClick={() => setPage((p) => p + 1)} className="text-xs font-bold text-accent disabled:text-ink-subtle">Next</button>
            </div>
          )}
        </div>

        {selected && (
          <OrderDetail
            key={selected._id}
            order={selected}
            token={token}
            showSellers={showSellers}
            onClose={() => setSelectedId(null)}
            onChanged={(patch) => { replaceOrder({ _id: selected._id, ...patch }); load(); }}
          />
        )}
      </div>
    </div>
  );
}

function OrderDetail({ order, token, showSellers, onClose, onChanged }) {
  const [busy, setBusy] = useState('');
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const [tracking, setTracking] = useState(null);
  const [cancelling, setCancelling] = useState(false);
  const [reason, setReason] = useState('');
  const [reasonCode, setReasonCode] = useState('CUSTOMER_REQUEST');

  const loadTracking = useCallback(async () => {
    try {
      const res = await apiFetch(`/admin/orders/${order._id}/tracking`, { token });
      setTracking(res.data);
    } catch {
      setTracking(null);
    }
  }, [order._id, token]);

  useEffect(() => { loadTracking(); }, [loadTracking, order.trackingNo]);

  const run = async (name, fn, success) => {
    setBusy(name); setError(''); setNotice('');
    try {
      await fn();
      if (success) setNotice(success);
    } catch (err) {
      setError(err.message);
    } finally { setBusy(''); }
  };

  const nextStatus = ORDER_STAGES[ORDER_STAGES.indexOf(order.status) + 1];

  const advance = () => run('advance', async () => {
    await apiFetch(`/admin/orders/${order._id}`, { method: 'PUT', token, body: { status: nextStatus } });
    onChanged({ status: nextStatus });
  }, `Moved to ${STAGE_LABELS[nextStatus]}.`);

  const bookCourier = () => run('book', async () => {
    const res = await apiFetch(`/admin/orders/${order._id}/shipment`, { method: 'POST', token });
    const o = res.data || {};
    onChanged({ courier: o.courier, trackingNo: o.tracking_no, label_generated: true, labelGenerated: true });
    await loadTracking();
  }, 'Courier booked.');

  const cancel = () => run('cancel', async () => {
    await apiFetch(`/orders/${order._id}/cancel`, { method: 'POST', token, body: { reason: reason.trim() || undefined, reason_code: reasonCode } });
    setCancelling(false);
    onChanged({ status: 'CANCELLED', paymentStatus: order.paymentStatus === 'PAID' ? 'REFUNDED' : order.paymentStatus });
  }, order.paymentStatus === 'PAID' ? 'Order cancelled and the payment refunded.' : 'Order cancelled.');

  const events = tracking?.tracking?.events || [];

  return (
    <div className="lg:col-span-2 bg-surface border border-line rounded-panel overflow-hidden">
      <div className="bg-inverse text-ink-inverse p-5 flex items-center justify-between">
        <div>
          <h3 className="font-black text-base">Order {order.id}</h3>
          <p className="text-ink-subtle text-xs font-medium">{order.customerName} • {order.createdAt}</p>
        </div>
        <button onClick={onClose} aria-label="Close order" className="text-ink-subtle hover:text-ink-inverse p-1.5 rounded-pill">
          <X className="w-5 h-5" />
        </button>
      </div>

      <div className="p-5 space-y-5">
        {notice && <p className="text-xs font-bold text-success flex items-center gap-1"><CheckCircle2 className="w-3.5 h-3.5" /> {notice}</p>}
        {error && <p className="text-xs font-bold text-danger flex items-center gap-1"><AlertCircle className="w-3.5 h-3.5" /> {error}</p>}

        {/* Actions */}
        {order.status !== 'CANCELLED' && (
          <div className="flex flex-wrap gap-2">
            {order.status !== 'DELIVERED' && nextStatus && (
              <button onClick={advance} disabled={!!busy} className="flex items-center gap-2 bg-inverse text-ink-inverse px-4 py-2.5 rounded-card text-xs font-black disabled:opacity-50">
                {busy === 'advance' ? <RefreshCw className="w-4 h-4 animate-spin" /> : <Truck className="w-4 h-4" />}
                Advance to {STAGE_LABELS[nextStatus]}
              </button>
            )}
            {BOOKABLE.includes(order.status) && !order.labelGenerated && !order.trackingNo && (
              <button onClick={bookCourier} disabled={!!busy} className="flex items-center gap-2 border border-line px-4 py-2.5 rounded-card text-xs font-black text-ink hover:bg-surface-muted disabled:opacity-50">
                {busy === 'book' ? <RefreshCw className="w-4 h-4 animate-spin" /> : <PackageCheck className="w-4 h-4" />}
                Book courier
              </button>
            )}
            {CANCELLABLE.includes(order.status) && (
              <button onClick={() => setCancelling(true)} disabled={!!busy} className="flex items-center gap-2 border border-danger text-danger px-4 py-2.5 rounded-card text-xs font-black hover:bg-danger-soft disabled:opacity-50">
                <Ban className="w-4 h-4" /> Cancel order
              </button>
            )}
          </div>
        )}

        {cancelling && (
          <div className="border border-danger rounded-card p-3 space-y-2 bg-danger-soft">
            <p className="text-xs font-bold text-ink">
              Cancel {order.id}? Stock goes back on sale{order.paymentStatus === 'PAID' ? ', and the payment is refunded to the customer' : ''}.
            </p>
            <select value={reasonCode} onChange={(e) => setReasonCode(e.target.value)} aria-label="Why is it being cancelled" className={`${inputCls} w-full`}>
              {CANCEL_CODES.map(([value, label]) => <option key={value} value={value}>{label}</option>)}
            </select>
            <input value={reason} onChange={(e) => setReason(e.target.value)} placeholder="Note (optional)" aria-label="Cancellation note" className={`${inputCls} w-full`} />
            <div className="flex gap-2">
              <button onClick={cancel} disabled={!!busy} className="bg-danger text-on-primary px-4 py-2 rounded-card text-xs font-black disabled:opacity-50">
                {busy === 'cancel' ? 'Cancelling…' : 'Yes, cancel it'}
              </button>
              <button onClick={() => setCancelling(false)} className="text-xs font-bold text-ink-muted px-3">Keep order</button>
            </div>
          </div>
        )}

        {/* Status timeline */}
        <div>
          <h4 className="font-black text-xs text-ink-muted mb-3">ORDER STATUS</h4>
          {order.status === 'CANCELLED' ? (
            <p className="text-xs font-bold text-danger">Cancelled</p>
          ) : (
            <div className="space-y-2">
              {ORDER_STAGES.map((stage, idx) => {
                const currentIdx = ORDER_STAGES.indexOf(order.status);
                const done = idx <= currentIdx;
                const current = idx === currentIdx;
                return (
                  <div key={stage} className="flex items-center gap-3">
                    <div className={`w-6 h-6 rounded-pill flex items-center justify-center shrink-0 ${done ? (current ? 'bg-warning' : 'bg-success') : 'bg-surface-sunken'}`}>
                      {done && !current && <CheckCircle2 className="w-4 h-4 text-ink-inverse" />}
                      {current && <Clock className="w-3.5 h-3.5 text-ink" />}
                    </div>
                    <div className={`flex-1 py-1.5 px-3 rounded-control text-xs font-bold ${current ? 'bg-warning-soft border border-warning text-warning' : done ? 'bg-success-soft text-success' : 'text-ink-subtle'}`}>
                      {STAGE_LABELS[stage]}
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </div>

        {/* Courier and where the parcel is */}
        <div className="bg-surface-muted border border-line rounded-card p-3 space-y-2 text-xs">
          <h4 className="font-black text-ink-subtle">COURIER</h4>
          <p className="font-bold text-ink">{order.courier || 'Not booked yet'}</p>
          <p className="text-ink-subtle font-mono text-[11px]">{order.trackingNo || 'No tracking number yet'}</p>
          {events.length > 0 && (
            <ol className="space-y-1.5 pt-1" aria-label="Tracking events">
              {events.map((e, i) => (
                <li key={`${e.status}-${i}`} className="flex gap-2">
                  <MapPin className="w-3.5 h-3.5 text-accent shrink-0 mt-0.5" />
                  <span className="text-ink font-semibold">
                    {e.label || e.status}
                    {e.location ? ` · ${e.location}` : ''}
                    {e.at ? <span className="text-ink-subtle font-medium"> · {new Date(e.at).toLocaleString('en-IN')}</span> : null}
                  </span>
                </li>
              ))}
            </ol>
          )}
          {tracking?.tracking?.track_url && (
            <a href={tracking.tracking.track_url} target="_blank" rel="noopener noreferrer" className="inline-block text-[11px] font-bold text-accent hover:underline">
              Track on the courier&apos;s site
            </a>
          )}
        </div>

        {/* Customer and address */}
        <div className="grid grid-cols-2 gap-4 text-xs">
          <div className="space-y-1">
            <h4 className="font-black text-ink-muted">CUSTOMER</h4>
            <p className="font-bold text-ink">{order.customerName}</p>
            <p className="text-ink-subtle">{order.phone}</p>
            {order.user?.email && <p className="text-ink-subtle">{order.user.email}</p>}
          </div>
          <div className="space-y-1">
            <h4 className="font-black text-ink-muted">DELIVERY ADDRESS</h4>
            <p className="text-ink-muted font-medium">{order.address}, {order.city} – {order.pincode}</p>
          </div>
        </div>

        {/* Items, and who sold them */}
        <div>
          <h4 className="font-black text-xs text-ink-muted mb-2">ORDERED ITEMS</h4>
          {(order.items || []).map((item, i) => (
            <div key={i} className="flex items-center justify-between py-2 border-b border-line last:border-0">
              <div>
                <p className="font-bold text-ink text-xs">{item.title}</p>
                <p className="text-[11px] text-ink-subtle">Qty: {item.qty}{showSellers && item.seller ? ` · Sold by ${item.seller}` : ''}</p>
                <OptionPicks picks={item.picks} className="mt-0.5" />
              </div>
              <span className="font-black text-ink text-sm">{formatINR(item.price * item.qty)}</span>
            </div>
          ))}
          <div className="flex items-center justify-between pt-2 font-black">
            <span className="text-ink text-xs">Total Amount</span>
            <span className="text-ink text-base">{formatINR(order.totalAmount)}</span>
          </div>
        </div>

        <div className="bg-surface-muted border border-line rounded-card p-3 text-xs">
          <h4 className="font-black text-ink-subtle mb-1">PAYMENT</h4>
          <p className="font-bold text-ink">{order.paymentMethod}</p>
          <span className={`text-[10px] font-black px-2 py-0.5 rounded-pill ${order.paymentStatus === 'PAID' ? 'bg-success-soft text-success' : 'bg-warning-soft text-warning'}`}>
            {order.paymentStatus}
          </span>
        </div>
      </div>
    </div>
  );
}
