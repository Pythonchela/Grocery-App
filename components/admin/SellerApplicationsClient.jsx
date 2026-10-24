'use client';

import React, { useCallback, useEffect, useState } from 'react';
import {
  ShieldCheck, FileText, RefreshCw, CheckCircle2, XCircle,
  Eye, EyeOff, Store, AlertCircle,
} from 'lucide-react';
import { useAdminAuth } from './AdminAuthContext';
import { apiFetch, formatDate } from '../../lib/apiClient';

const API_BASE = process.env.NEXT_PUBLIC_API_URL || 'http://127.0.0.1:8000/api/v1';

const DOC_LABELS = {
  PAN_CARD: 'PAN card',
  GST_CERTIFICATE: 'GST certificate',
  CANCELLED_CHEQUE: 'Cancelled cheque',
  ADDRESS_PROOF: 'Address proof',
  INCORPORATION_CERT: 'Certificate of incorporation',
};

const TABS = [
  { key: 'SUBMITTED', label: 'Awaiting review' },
  { key: 'APPROVED', label: 'Approved' },
  { key: 'REJECTED', label: 'Rejected' },
];

/**
 * The review desk.
 *
 * The queue deliberately shows masked identity numbers — a reviewer works one
 * application at a time, and a list view full of other people's PANs is a
 * needless exposure. Opening one calls the detail endpoint, which is where the
 * unmasking (and its audit log entry) happens.
 */
export default function SellerApplicationsClient() {
  const { token } = useAdminAuth();

  const [tab, setTab] = useState('SUBMITTED');
  const [rows, setRows] = useState([]);
  const [loading, setLoading] = useState(true);
  const [selected, setSelected] = useState(null);
  const [detail, setDetail] = useState(null);
  const [revealed, setRevealed] = useState(false);
  const [busy, setBusy] = useState(false);
  const [rejectReason, setRejectReason] = useState('');
  const [error, setError] = useState('');

  const load = useCallback(async () => {
    setLoading(true); setError('');
    try {
      const res = await apiFetch(`/admin/sellers/applications?status=${tab}`, { token });
      setRows(res.data || []);
    } catch (err) {
      setError(err.message);
    } finally { setLoading(false); }
  }, [token, tab]);

  useEffect(() => { load(); }, [load]);

  const open = async (sellerId) => {
    setSelected(sellerId); setDetail(null); setRevealed(false); setRejectReason(''); setError('');
    try {
      const res = await apiFetch(`/admin/sellers/${sellerId}/review`, { token });
      setDetail(res.data);
    } catch (err) { setError(err.message); }
  };

  const decide = async (action) => {
    if (action === 'reject' && !rejectReason.trim()) {
      setError('A rejection needs a reason the seller can act on.');
      return;
    }

    setBusy(true); setError('');
    try {
      await apiFetch(`/admin/sellers/${selected}/kyc/${action}`, {
        method: 'POST', token,
        body: action === 'reject' ? { reason: rejectReason.trim() } : undefined,
      });
      setSelected(null); setDetail(null);
      await load();
    } catch (err) { setError(err.message); } finally { setBusy(false); }
  };

  return (
    <div className="space-y-4">
      <header className="flex items-center justify-between gap-3">
        <div>
          <h2 className="text-lg font-black text-ink flex items-center gap-2">
            <ShieldCheck className="w-5 h-5 text-accent" /> Seller applications
          </h2>
          <p className="text-xs text-ink-muted font-medium mt-0.5">
            A shop only goes live once you approve it here.
          </p>
        </div>
        <button onClick={load} className="text-ink-subtle hover:text-ink" aria-label="Refresh">
          <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} />
        </button>
      </header>

      <div className="flex gap-1 border-b border-line">
        {TABS.map(t => (
          <button
            key={t.key}
            onClick={() => setTab(t.key)}
            className={`px-4 py-2 text-xs font-black border-b-2 transition ${
              tab === t.key
                ? 'border-accent text-accent'
                : 'border-transparent text-ink-subtle hover:text-ink'
            }`}
          >
            {t.label}
          </button>
        ))}
      </div>

      {error && !selected && (
        <p className="text-xs font-bold text-danger flex items-center gap-1">
          <AlertCircle className="w-3.5 h-3.5" /> {error}
        </p>
      )}

      {loading ? (
        <div className="py-12 flex justify-center">
          <RefreshCw className="w-5 h-5 animate-spin text-accent" />
        </div>
      ) : rows.length === 0 ? (
        <div className="py-12 text-center text-ink-subtle">
          <Store className="w-8 h-8 mx-auto mb-2" />
          <p className="text-sm font-bold">Nothing here</p>
        </div>
      ) : (
        <div className="space-y-2">
          {rows.map(row => (
            <button
              key={row.id}
              onClick={() => open(row.seller.id)}
              className="w-full text-left flex items-center gap-4 p-4 border border-line rounded-card bg-surface hover:border-accent transition"
            >
              <div className="flex-1 min-w-0">
                <p className="text-sm font-black text-ink truncate">{row.seller.display_name}</p>
                <p className="text-[11px] text-ink-subtle font-semibold">
                  {row.legal_name} · {row.business_type} · PAN {row.pan || '—'}
                </p>
              </div>
              <div className="text-right shrink-0">
                <p className="text-[10px] font-bold text-ink-muted">
                  {row.document_count} document{row.document_count === 1 ? '' : 's'}
                </p>
                {row.submitted_at && (
                  <p className="text-[10px] text-ink-subtle font-medium">{formatDate(row.submitted_at)}</p>
                )}
              </div>
            </button>
          ))}
        </div>
      )}

      {/* Review drawer */}
      {selected && (
        <div className="fixed inset-0 z-50 bg-inverse/60 backdrop-blur-sm flex justify-end">
          <div className="w-screen max-w-lg bg-surface border-l border-line overflow-y-auto">
            {!detail ? (
              <div className="p-12 flex justify-center">
                <RefreshCw className="w-5 h-5 animate-spin text-accent" />
              </div>
            ) : (
              <div className="p-5 space-y-5">
                <header className="flex items-start justify-between gap-3">
                  <div>
                    <h3 className="text-base font-black text-ink">{detail.seller.display_name}</h3>
                    <p className="text-[11px] text-ink-subtle font-semibold">
                      {detail.operator?.name} · {detail.operator?.email}
                    </p>
                  </div>
                  <button onClick={() => { setSelected(null); setDetail(null); }}
                    className="text-ink-subtle hover:text-ink text-xs font-bold">Close</button>
                </header>

                <section className="space-y-2">
                  <div className="flex items-center justify-between">
                    <h4 className="text-xs font-black text-ink uppercase tracking-wide">Identity</h4>
                    <button
                      onClick={() => setRevealed(r => !r)}
                      className="text-[10px] font-bold text-accent flex items-center gap-1 hover:underline"
                    >
                      {revealed ? <EyeOff className="w-3 h-3" /> : <Eye className="w-3 h-3" />}
                      {revealed ? 'Hide' : 'Reveal'}
                    </button>
                  </div>

                  <dl className="text-xs space-y-1.5">
                    <Row label="Business type" value={detail.kyc.business_type} />
                    <Row label="Legal name" value={detail.kyc.legal_name} />
                    <Row label="PAN" value={revealed ? detail.kyc.pan : maskAll(detail.kyc.pan)} mono />
                    <Row label="GSTIN" value={revealed ? (detail.kyc.gstin || '—') : maskAll(detail.kyc.gstin)} mono />
                    <Row
                      label="Address"
                      value={[detail.kyc.registered_line1, detail.kyc.registered_line2,
                        detail.kyc.registered_city, detail.kyc.registered_state,
                        detail.kyc.registered_pincode].filter(Boolean).join(', ')}
                    />
                  </dl>
                </section>

                <section className="space-y-2">
                  <h4 className="text-xs font-black text-ink uppercase tracking-wide">Settlement</h4>
                  <dl className="text-xs space-y-1.5">
                    <Row label="Account holder" value={detail.kyc.bank_account_holder} />
                    <Row label="Bank" value={detail.kyc.bank_name || '—'} />
                    <Row
                      label="Account no."
                      value={revealed ? detail.kyc.bank_account_number : maskAll(detail.kyc.bank_account_number)}
                      mono
                    />
                    <Row label="IFSC" value={detail.kyc.bank_ifsc} mono />
                  </dl>
                </section>

                <section className="space-y-2">
                  <h4 className="text-xs font-black text-ink uppercase tracking-wide">Documents</h4>
                  {detail.documents.length === 0 ? (
                    <p className="text-xs text-ink-subtle font-medium">None uploaded.</p>
                  ) : detail.documents.map(doc => (
                    <a
                      key={doc.id}
                      href={`${API_BASE}/seller/documents/${doc.id}/download`}
                      target="_blank" rel="noreferrer"
                      className="flex items-center gap-2 p-2.5 border border-line rounded-control hover:border-accent transition"
                    >
                      <FileText className="w-4 h-4 text-accent shrink-0" />
                      <div className="flex-1 min-w-0">
                        <p className="text-xs font-extrabold text-ink">{DOC_LABELS[doc.kind] || doc.kind}</p>
                        <p className="text-[10px] text-ink-subtle font-medium truncate">{doc.original_name}</p>
                      </div>
                    </a>
                  ))}
                </section>

                {error && (
                  <p className="text-xs font-bold text-danger flex items-center gap-1">
                    <AlertCircle className="w-3.5 h-3.5" /> {error}
                  </p>
                )}

                {detail.kyc.status === 'SUBMITTED' ? (
                  <section className="space-y-3 pt-2 border-t border-line">
                    <textarea
                      className="w-full bg-surface border border-line rounded-control px-3 py-2 text-xs font-semibold text-ink focus:outline-none focus:border-accent"
                      rows={2}
                      placeholder="Reason — required to reject, e.g. 'the cancelled cheque is unreadable'"
                      value={rejectReason}
                      onChange={e => setRejectReason(e.target.value)}
                    />
                    <div className="flex gap-2">
                      <button
                        onClick={() => decide('approve')} disabled={busy}
                        className="flex-1 btn-primary justify-center text-xs py-2.5 disabled:opacity-50"
                      >
                        <CheckCircle2 className="w-4 h-4" /> Approve &amp; activate
                      </button>
                      <button
                        onClick={() => decide('reject')} disabled={busy}
                        className="flex-1 justify-center flex items-center gap-1.5 text-xs font-black py-2.5 rounded-control border border-danger/40 text-danger hover:bg-danger/5 disabled:opacity-50"
                      >
                        <XCircle className="w-4 h-4" /> Reject
                      </button>
                    </div>
                  </section>
                ) : (
                  <p className="text-xs font-bold text-ink-muted pt-2 border-t border-line">
                    Already {detail.kyc.status.toLowerCase()}
                    {detail.kyc.rejection_reason ? ` — ${detail.kyc.rejection_reason}` : ''}.
                  </p>
                )}
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
}

function Row({ label, value, mono }) {
  return (
    <div className="flex justify-between gap-3">
      <dt className="text-ink-subtle font-semibold shrink-0">{label}</dt>
      <dd className={`text-ink font-bold text-right break-all ${mono ? 'font-mono' : ''}`}>{value || '—'}</dd>
    </div>
  );
}

/** Local masking for the reveal toggle, so hiding doesn't need a refetch. */
function maskAll(value) {
  if (!value) return '—';
  return '•'.repeat(Math.max(4, value.length - 4)) + value.slice(-4);
}
