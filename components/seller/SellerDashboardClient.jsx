'use client';

import React, { useCallback, useEffect, useRef, useState } from 'react';
import Link from 'next/link';
import { useStore } from '../providers/StoreProvider';
import { offersSelling } from '../../lib/shopRules';
import VendorsOff from './VendorsOff';
import { apiFetch, formatINR, mapCategory, mapProduct } from '../../lib/apiClient';
import ProductFormModal from '../admin/ProductFormModal';
import InventoryModal from '../admin/InventoryModal';
import ShopProfileSection from '../admin/ShopProfileSection';
import BulkImportClient from '../admin/BulkImportClient';
import CategoryRequestPanel from './CategoryRequestPanel';
import CouponsSection from '../admin/CouponsSection';
import MoneyPanel from './MoneyPanel';
import SupportClient from '../support/SupportClient';
import useOrderAlerts from './useOrderAlerts';
import SellerShell from './SellerShell';
import { AvailabilityToggle, DeclineForm, IncomingOrders, OrderDeskSettings } from './OrderDesk';

const stages = [['to_pack', 'To pack'], ['packed', 'Ready to ship'], ['shipped', 'Shipped'], ['delivered', 'Delivered'], ['cancelled', 'Cancelled']];
const input = 'w-full rounded-control border border-line bg-surface px-3 py-2 text-sm text-ink';
const button = 'rounded-control bg-accent px-3 py-2 text-xs font-bold text-on-accent disabled:opacity-50';

function DashboardFlow() {
  const { authToken, sellerState } = useStore();
  const [tab, setTab] = useState('overview');
  const [profile, setProfile] = useState(null);
  const [overview, setOverview] = useState(null);
  const [rows, setRows] = useState([]);
  const [categories, setCategories] = useState([]);
  const [stage, setStage] = useState('to_pack');
  const [status, setStatus] = useState('');
  const [searchText, setSearchText] = useState('');
  const [search, setSearch] = useState('');
  const [page, setPage] = useState(1);
  const [lastPage, setLastPage] = useState(1);
  const [loading, setLoading] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const [editor, setEditor] = useState(undefined);
  const [stockProduct, setStockProduct] = useState(null);
  const [shipping, setShipping] = useState(null);
  const [courier, setCourier] = useState('');
  const [tracking, setTracking] = useState('');
  const [reply, setReply] = useState({});
  const [pickup, setPickup] = useState({});
  const [returnDraft, setReturnDraft] = useState({});
  const [cancelling, setCancelling] = useState(null);
  const loadId = useRef(0);

  const active = sellerState?.stage === 'ACTIVE';
  const alerts = useOrderAlerts(authToken, active);
  const load = useCallback(async () => {
    if (!authToken || !active) return;
    const current = ++loadId.current;
    setLoading(true); setError('');
    try {
      const path = {
        overview: '/seller/overview', orders: `/seller/order-items?stage=${stage}&page=${page}&per_page=20`,
        products: `/seller/products?status=${status}&search=${encodeURIComponent(search)}&page=${page}&per_page=20`, import: null, coupons: null, incoming: null, help: null,
        feedback: '/seller/reviews?per_page=100', returns: '/seller/returns?per_page=100',
        earnings: `/seller/ledger?page=${page}&per_page=20`, shop: '/seller/me',
      }[tab];
      if (!path) { setLoading(false); return; }
      const res = await apiFetch(path, { token: authToken });
      if (current !== loadId.current) return;
      if (tab === 'overview') setOverview(res.data);
      else if (tab === 'shop') setProfile(res.data);
      else setRows(res.data || []);
      setLastPage(res.meta?.last_page || 1);
      if (tab === 'feedback') {
        const questions = await apiFetch('/seller/questions?per_page=100', { token: authToken });
        if (current !== loadId.current) return;
        setRows({ reviews: res.data || [], questions: questions.data || [] });
      }
      if (tab === 'earnings') setOverview(v => ({ ...v, balance: res.balance, pending: res.pending, withdrawable: res.withdrawable }));
    } catch (e) { if (current === loadId.current) setError(e.message); }
    finally { if (current === loadId.current) setLoading(false); }
  }, [authToken, active, tab, stage, status, search, page]);

  useEffect(() => { load(); }, [load]);
  useEffect(() => {
    if (!authToken || !active) return;
    apiFetch('/seller/me', { token: authToken }).then(r => setProfile(r.data)).catch(e => setError(e.message));
    apiFetch('/categories').then(r => setCategories((r.data || []).map(mapCategory))).catch(e => setError(e.message));
  }, [authToken, active]);
  useEffect(() => { setPage(1); }, [tab, stage, status, search]);

  const act = async (path, method = 'POST', body) => {
    setBusy(true); setError(''); setNotice('');
    try {
      await apiFetch(path, { method, body, token: authToken });
      setNotice('Saved.'); setShipping(null); setCourier(''); setTracking('');
      await load();
    } catch (e) { setError(e.message); }
    finally { setBusy(false); }
  };

  if (!authToken) return <Gate title="Sign in to manage your shop" href="/account" action="Sign in" />;
  if (!sellerState) return <p className="p-12 text-center text-ink-muted">Loading your shop…</p>;
  if (!active) return <Gate title={sellerState.stage === 'IN_REVIEW' ? 'Your application is under review' : 'Finish setting up your shop'} href="/sell" action="Open application" />;

  return <SellerShell tab={tab} onSelect={setTab} badges={{ newOrders: alerts.newOrders }} profile={profile} onRefresh={load}>
    <div className="flex flex-wrap items-center justify-between gap-2 text-xs text-ink-muted">
      <span>{alerts.late > 0 ? `${alerts.late} order${alerts.late === 1 ? ' is' : 's are'} past the time you promised.` : 'Keep this page open to hear about new orders.'}</span>
      <label className="flex items-center gap-2 font-bold text-ink"><input type="checkbox" checked={alerts.soundOn} onChange={e => alerts.setSoundOn(e.target.checked)} /> Sound alerts for new orders</label>
    </div>
    {alerts.newOrders > 0 && tab !== 'incoming' && <button type="button" onClick={() => setTab('incoming')} className="w-full rounded-card border-2 border-accent bg-accent-soft p-3 text-left text-sm font-bold text-ink">{alerts.newOrders} new order{alerts.newOrders === 1 ? '' : 's'} waiting for your answer — open them</button>}
    {error && <p role="alert" className="rounded-card bg-danger-soft p-3 text-sm text-danger">{error}</p>}
    {notice && <p role="status" className="rounded-card bg-success-soft p-3 text-sm text-success">{notice}</p>}
    {loading && <p className="text-sm text-ink-muted">Loading…</p>}
    {!loading && tab === 'overview' && <div className="space-y-4">
      <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
        {[[overview?.new_orders, 'New orders to answer', 'incoming'], [overview?.late_to_pack, 'Past promised time', 'orders'], [overview?.acceptance_rate_30d == null ? '—' : `${overview.acceptance_rate_30d}%`, 'Orders accepted (30 days)', 'incoming'], [overview?.to_pack, 'To pack', 'orders'], [overview?.packed, 'Ready to ship', 'orders'], [overview?.orders_30d, 'Orders in 30 days', 'orders'], [formatINR(overview?.sold_30d || 0), 'Earned in 30 days', 'earnings'], [overview?.low_stock, 'Low stock products', 'products'], [overview?.questions_open, 'Questions to answer', 'feedback'], [overview?.returns_open, 'Open returns', 'returns']].map(([value, label, destination]) =>
          <button key={label} onClick={() => setTab(destination)} className="rounded-card border border-line bg-surface p-4 text-left hover:border-accent"><strong className="block text-xl text-ink">{value ?? '—'}</strong><span className="text-xs text-ink-muted">{label}</span></button>)}
      </div><p className="text-sm text-ink-muted">Start with orders that need packing. Keep stock and opening hours current so shoppers see what you can deliver.</p>
    </div>}
    {tab === 'incoming' && <IncomingOrders token={authToken} defaultPrep={profile?.prep_minutes} onChanged={alerts.refresh} />}
    {tab === 'help' && <SupportClient token={authToken} sellerView />}
    {!loading && tab === 'products' && <section className="space-y-3">
      <CategoryRequestPanel token={authToken} />
      <div className="flex flex-wrap items-center justify-between gap-2"><label className="text-sm font-bold text-ink">Show <select className={input} value={status} onChange={e => setStatus(e.target.value)}>
        {[['', 'All products'], ['ACTIVE', 'Live'], ['DRAFT', 'Drafts'], ['OUT_OF_STOCK', 'Out of stock'], ['DISCONTINUED', 'Discontinued']].map(([v, label]) => <option key={v} value={v}>{label}</option>)}
      </select></label><button className={button} onClick={() => setEditor(null)}>Add product</button></div>
      <form className="flex gap-2" onSubmit={e => { e.preventDefault(); setSearch(searchText.trim()); }}>
        <input aria-label="Search my products" className={input} value={searchText} onChange={e => setSearchText(e.target.value)} placeholder="Search name or SKU" />
        <button className={button} type="submit">Search</button>
        {search && <button type="button" className="text-xs text-ink-muted" onClick={() => { setSearch(''); setSearchText(''); }}>Clear</button>}
      </form>
      {rows.length === 0 && <Empty text="No products in this view. Add one to start selling." />}
      {rows.map(raw => { const p = mapProduct(raw); return <article key={p.id} className="flex flex-wrap items-center gap-3 rounded-card border border-line bg-surface p-3">
        <img src={p.image} alt="" className="h-14 w-14 rounded-control object-cover" />
        <div className="min-w-40 flex-1"><strong className="block text-sm text-ink">{p.title}</strong><span className="text-xs text-ink-muted">{formatINR(p.price)} · {p.stockCount} in stock · {p.status}</span></div>
        <AvailabilityToggle product={p} token={authToken} onChanged={load} />
        <button className={button} onClick={() => setStockProduct(p)}>Stock</button>
        <button className="rounded-control border border-line px-3 py-2 text-xs font-bold text-ink" onClick={() => setEditor(p)}>Edit</button>
        <select aria-label={`Status for ${p.title}`} className={input + ' max-w-36'} value={p.status} disabled={busy} onChange={e => act(`/products/${p.id}`, 'PUT', { status: e.target.value })}>
          {['ACTIVE', 'DRAFT', 'OUT_OF_STOCK', 'DISCONTINUED'].map(s => <option key={s} value={s}>{s.replaceAll('_', ' ')}</option>)}
        </select>
      </article>; })}
    </section>}
    {!loading && tab === 'import' && <BulkImportClient token={authToken} basePath="/seller/products/import" />}
    {!loading && tab === 'coupons' && <CouponsSection token={authToken} basePath="/seller/coupons" sellerMode />}
    {!loading && tab === 'orders' && <section className="space-y-3">
      <div className="flex gap-2 overflow-x-auto">{stages.map(([key, label]) => <button key={key} onClick={() => setStage(key)} className={`whitespace-nowrap rounded-control px-3 py-2 text-xs font-bold ${stage === key ? 'bg-accent text-on-accent' : 'bg-surface-muted text-ink'}`}>{label}</button>)}</div>
      {rows.length === 0 && <Empty text="No order lines here." />}
      {rows.map(item => <article key={item.id} className="space-y-2 rounded-card border border-line bg-surface p-4 text-sm text-ink">
        <div className="flex justify-between gap-2"><strong>{item.product?.title || 'Product'} × {item.quantity}</strong><span>{item.order?.order_number}</span></div>
        <p className="text-xs text-ink-muted">{item.variant && [item.variant.color, item.variant.size].filter(Boolean).join(' / ')} · {item.order?.shipping_address?.city} {item.order?.shipping_address?.pincode} · You earn {formatINR(item.seller_earning)}</p>
        <p className="text-xs text-ink-muted">{item.fulfilment_status}{item.tracking_no ? ` · ${item.courier} ${item.tracking_no}` : ''}{item.rejection_reason ? ` · ${item.rejection_reason.replaceAll('_', ' ').toLowerCase()}${item.rejected_by === 'SYSTEM' ? ' (no answer in time)' : ''}` : ''}</p>
        {['to_pack', 'packed'].includes(stage) && item.ready_by && <p className={`text-xs font-bold ${new Date(item.ready_by) < new Date() ? 'text-danger' : 'text-ink-muted'}`}>Promised ready by {new Date(item.ready_by).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })}{new Date(item.ready_by) < new Date() ? ' — running late' : ''}</p>}
        {['to_pack', 'packed'].includes(stage) && (cancelling === item.id
          ? <DeclineForm item={item} token={authToken} title="Cancel this order" onCancel={() => setCancelling(null)} onDone={() => { setCancelling(null); setNotice('Order cancelled and the customer refunded.'); load(); alerts.refresh(); }} />
          : <button type="button" className="text-xs font-bold text-danger" onClick={() => setCancelling(item.id)}>Cancel this order</button>)}
        {stage === 'to_pack' && <button disabled={busy} className={button} onClick={() => act(`/seller/order-items/${item.id}/pack`)}>Mark packed</button>}
        {stage === 'packed' && <button disabled={busy} className={button} onClick={() => setShipping(item.id)}>{profile?.auto_book ? 'Book courier & ship' : 'Enter shipping details'}</button>}
        {shipping === item.id && <div className="space-y-2 rounded-card bg-surface-muted p-3">
          {profile?.auto_book && <p className="text-xs text-ink-muted">Leave both fields empty for automatic booking, or enter your own courier and tracking number.</p>}
          <div className="grid gap-2 sm:grid-cols-2"><input className={input} value={courier} onChange={e => setCourier(e.target.value)} placeholder="Courier" aria-label="Courier" /><input className={input} value={tracking} onChange={e => setTracking(e.target.value)} placeholder="Tracking number" aria-label="Tracking number" /></div>
          <button className={button} disabled={busy || (!!courier !== !!tracking)} onClick={() => act(`/seller/order-items/${item.id}/ship`, 'POST', { courier: courier || null, tracking_no: tracking || null })}>Confirm shipment</button>
          <button className="ml-2 text-xs text-ink-muted" onClick={() => setShipping(null)}>Cancel</button>
        </div>}
      </article>)}
    </section>}
    {!loading && tab === 'feedback' && <div className="grid gap-5 lg:grid-cols-2">
      <section className="space-y-3"><h2 className="font-bold text-ink">Reviews</h2>{!rows.reviews?.length && <Empty text="No reviews yet." />}
        {rows.reviews?.map(r => <article key={r.id} className="space-y-2 rounded-card border border-line bg-surface p-3 text-sm text-ink">
          <strong>{r.product?.title} · {r.rating}/5</strong><p>{r.body || r.title}</p><p className="text-xs text-ink-muted">{r.status}</p>
          {r.status === 'APPROVED' && <><textarea className={input} rows={2} aria-label={`Reply to review for ${r.product?.title}`} value={reply[r.id] ?? r.admin_reply ?? ''} onChange={e => setReply(v => ({ ...v, [r.id]: e.target.value }))} /><button className={button} disabled={busy || !(reply[r.id] ?? r.admin_reply ?? '').trim()} onClick={() => act(`/seller/reviews/${r.id}/reply`, 'PUT', { reply: reply[r.id] ?? r.admin_reply })}>Post reply</button></>}
        </article>)}</section>
      <section className="space-y-3"><h2 className="font-bold text-ink">Product questions</h2>{!rows.questions?.length && <Empty text="No approved questions yet." />}
        {rows.questions?.map(q => <article key={q.id} className="space-y-2 rounded-card border border-line bg-surface p-3 text-sm text-ink"><strong>{q.product?.title}</strong><p>{q.body}</p>
          {q.answers?.filter(a => a.is_official).map(a => <p key={a.id} className="text-xs text-ink-muted">Shop answer: {a.body}</p>)}
          <textarea className={input} rows={2} aria-label={`Answer question for ${q.product?.title}`} value={reply[q.id] || ''} onChange={e => setReply(v => ({ ...v, [q.id]: e.target.value }))} />
          <button className={button} disabled={busy || !reply[q.id]?.trim()} onClick={() => act(`/questions/${q.id}/answer`, 'POST', { body: reply[q.id] })}>Post answer</button>
        </article>)}</section>
    </div>}
    {!loading && tab === 'returns' && <section className="space-y-3"><p className="text-sm text-ink-muted">Review requests and send your recommendation. The marketplace team decides pickups and refunds.</p>
      {rows.length === 0 && <Empty text="No returns for your products." />}
      {rows.map(r => <article key={r.id} className="space-y-2 rounded-card border border-line bg-surface p-3 text-sm text-ink"><strong>{r.order_item?.product?.title}</strong> · {r.rma_number}<p>{r.kind} · {r.status} · {r.reason}</p><p className="text-xs text-ink-muted">Refund {formatINR(r.refund_amount)}</p>
        {r.seller_recommendation && <p className="text-xs text-ink-muted">Your recommendation: {r.seller_recommendation} · {r.seller_note}</p>}
        {['REQUESTED', 'PICKUP_SCHEDULED', 'PICKED_UP'].includes(r.status) && <div className="grid gap-2 sm:grid-cols-[180px_1fr_auto]">
          <select aria-label={`Recommendation for ${r.rma_number}`} className={input} value={returnDraft[r.id]?.seller_recommendation ?? r.seller_recommendation ?? 'NEEDS_REVIEW'} onChange={e => setReturnDraft(v => ({ ...v, [r.id]: { ...v[r.id], seller_recommendation: e.target.value } }))}>
            <option value="NEEDS_REVIEW">Needs review</option><option value="ACCEPT">Recommend accept</option><option value="REJECT">Recommend reject</option>
          </select>
          <input aria-label={`Review note for ${r.rma_number}`} className={input} placeholder="What did you check?" value={returnDraft[r.id]?.seller_note ?? r.seller_note ?? ''} onChange={e => setReturnDraft(v => ({ ...v, [r.id]: { ...v[r.id], seller_note: e.target.value } }))} />
          <button className={button} disabled={busy || !(returnDraft[r.id]?.seller_note ?? r.seller_note ?? '').trim()} onClick={() => act(`/seller/returns/${r.id}/review`, 'PUT', { seller_recommendation: returnDraft[r.id]?.seller_recommendation ?? r.seller_recommendation ?? 'NEEDS_REVIEW', seller_note: returnDraft[r.id]?.seller_note ?? r.seller_note })}>Send review</button>
        </div>}
      </article>)}
    </section>}
    {tab === 'earnings' && <section className="space-y-6">
      <MoneyPanel token={authToken} />
      {!loading && rows.length > 0 && <h2 className="font-bold text-ink">Every movement</h2>}
      {!loading && rows.map(e => <div key={e.id} className="flex justify-between gap-2 rounded-card border border-line bg-surface p-3 text-sm text-ink"><span>{e.type} · {e.note}</span><strong>{formatINR(e.net)}</strong></div>)}
    </section>}
    {!loading && tab === 'shop' && profile && <section className="mx-auto max-w-2xl space-y-5 rounded-card border border-line bg-surface p-4">
      <OrderDeskSettings profile={profile} token={authToken} onSaved={updated => setProfile(p => ({ ...p, ...updated }))} />
      <ShopProfileSection seller={profile} token={authToken} endpoint="/seller/me" onSaved={updated => setProfile(p => ({ ...p, ...updated }))} />
      <div className="space-y-2 border-t border-line pt-4"><h2 className="font-bold text-ink">Courier pickup address</h2>
        {['pickup_name', 'pickup_phone', 'pickup_line1', 'pickup_city', 'pickup_state', 'pickup_pincode'].map(key => <label key={key} className="block text-xs font-bold text-ink">{key.replaceAll('_', ' ')}<input className={input} value={pickup[key] ?? profile[key] ?? ''} onChange={e => setPickup(v => ({ ...v, [key]: e.target.value }))} /></label>)}
        <button className={button} disabled={busy} onClick={() => act('/seller/me', 'PUT', Object.fromEntries(['pickup_name', 'pickup_phone', 'pickup_line1', 'pickup_city', 'pickup_state', 'pickup_pincode'].map(k => [k, (pickup[k] ?? profile[k] ?? '').trim() || null])))}>Save pickup address</button>
      </div>
    </section>}
    {['orders', 'products', 'earnings'].includes(tab) && !loading && lastPage > 1 && <div className="flex justify-center gap-3 text-sm"><button disabled={page === 1} onClick={() => setPage(page - 1)}>Previous</button><span>{page} of {lastPage}</span><button disabled={page === lastPage} onClick={() => setPage(page + 1)}>Next</button></div>}
    {editor !== undefined && <ProductFormModal isOpen product={editor} categories={categories} token={authToken} defaultStatus="DRAFT" onClose={() => setEditor(undefined)} onSaved={() => { setEditor(undefined); load(); }} />}
    {stockProduct && <InventoryModal product={stockProduct} token={authToken} onClose={() => setStockProduct(null)} onSaved={() => { setStockProduct(null); load(); }} />}
  </SellerShell>;
}

function Empty({ text }) { return <p className="rounded-card border border-dashed border-line p-8 text-center text-sm text-ink-muted">{text}</p>; }
function Gate({ title, href, action }) { return <main className="mx-auto max-w-md space-y-4 px-4 py-16 text-center"><h1 className="text-xl font-bold text-ink">{title}</h1><Link href={href} className={button}>{action}</Link><p><Link href="/" className="text-sm font-bold text-ink-muted">Back to the shop</Link></p></main>; }

export default function SellerDashboardClient() {
  const { storeConfig } = useStore();
  // A store that sells only its own goods has no seller area: the links are hidden,
  // and this covers someone who types the address.
  if (!offersSelling(storeConfig)) return <VendorsOff />;
  return <DashboardFlow />;
}
