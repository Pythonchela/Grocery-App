'use client';

import React, { useCallback, useEffect, useState } from 'react';
import {
  Store, ShieldCheck, Upload, FileText, Trash2, CheckCircle2,
  AlertCircle, Clock, RefreshCw, Landmark, Building2, X,
} from 'lucide-react';
import { useStore } from '../providers/StoreProvider';
import { offersSelling } from '../../lib/shopRules';
import VendorsOff from './VendorsOff';
import { apiFetch } from '../../lib/apiClient';

const API_BASE = process.env.NEXT_PUBLIC_API_URL || 'http://127.0.0.1:8000/api/v1';

/** Field labels for the checklist the server returns, which sends keys. */
const FIELD_LABELS = {
  business_type: 'Business type',
  legal_name: 'Legal name',
  pan: 'PAN',
  registered_line1: 'Registered address',
  registered_city: 'City',
  registered_state: 'State',
  registered_pincode: 'PIN code',
  bank_account_holder: 'Account holder name',
  bank_account_number: 'Bank account number',
  bank_ifsc: 'IFSC code',
};

const DOC_LABELS = {
  PAN_CARD: 'PAN card',
  GST_CERTIFICATE: 'GST certificate',
  CANCELLED_CHEQUE: 'Cancelled cheque',
  ADDRESS_PROOF: 'Address proof',
  INCORPORATION_CERT: 'Certificate of incorporation',
};

const BUSINESS_TYPE_LABELS = {
  INDIVIDUAL: 'Individual',
  PROPRIETORSHIP: 'Sole proprietorship',
  PARTNERSHIP: 'Partnership firm',
  LLP: 'LLP',
  PRIVATE_LIMITED: 'Private limited',
};

/** One banner that explains the current state, since it drives what's editable. */
function StatusBanner({ sellerStatus, kyc }) {
  const map = {
    APPROVED: {
      icon: CheckCircle2, tone: 'text-success border-success/30 bg-success/5',
      title: 'Your shop is live',
      body: 'Your details are verified. You can list products from the seller dashboard.',
    },
    SUBMITTED: {
      icon: Clock, tone: 'text-warning border-warning/30 bg-warning/5',
      title: 'Under review',
      body: 'We are checking your documents. This form is locked until we respond.',
    },
    REJECTED: {
      icon: AlertCircle, tone: 'text-danger border-danger/30 bg-danger/5',
      title: 'We need something corrected',
      body: kyc?.rejection_reason || 'Please review your details and submit again.',
    },
    DRAFT: {
      icon: Store, tone: 'text-accent border-accent/30 bg-accent/5',
      title: 'Finish your application',
      body: 'Fill in your business and bank details, upload your documents, then submit for review.',
    },
  };

  const state = map[kyc?.status] || map.DRAFT;
  const Icon = state.icon;

  return (
    <div className={`flex gap-3 p-4 rounded-card border ${state.tone}`}>
      <Icon className="w-5 h-5 shrink-0 mt-0.5" />
      <div>
        <p className="text-sm font-black">{state.title}</p>
        <p className="text-xs font-medium text-ink-muted mt-0.5">{state.body}</p>
        {sellerStatus === 'SUSPENDED' && (
          <p className="text-xs font-bold text-danger mt-1">
            This account is currently suspended. Contact support.
          </p>
        )}
      </div>
    </div>
  );
}

function Field({ label, hint, children }) {
  return (
    <label className="block">
      <span className="block text-[10px] font-bold text-ink-subtle uppercase tracking-wide mb-1">{label}</span>
      {children}
      {hint && <span className="block text-[10px] text-ink-subtle font-medium mt-1">{hint}</span>}
    </label>
  );
}

const inputClass =
  'w-full bg-surface border border-line rounded-control px-3 py-2 text-sm font-semibold text-ink ' +
  'focus:outline-none focus:border-accent disabled:opacity-60 disabled:cursor-not-allowed';

function OnboardingFlow() {
  const { authToken } = useStore();

  const [loading, setLoading] = useState(true);
  const [state, setState] = useState(null);
  const [form, setForm] = useState({});
  const [errors, setErrors] = useState({});
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState('');
  const [applyName, setApplyName] = useState('');
  const [needsApplication, setNeedsApplication] = useState(false);

  /** Seeds the editable form from the server's masked values. */
  const adopt = useCallback((data) => {
    setState(data);
    setNeedsApplication(false);
    setForm({
      business_type: data.kyc.business_type || 'INDIVIDUAL',
      legal_name: data.kyc.legal_name || '',
      registered_line1: data.kyc.registered_line1 || '',
      registered_line2: data.kyc.registered_line2 || '',
      registered_city: data.kyc.registered_city || '',
      registered_state: data.kyc.registered_state || '',
      registered_pincode: data.kyc.registered_pincode || '',
      bank_account_holder: data.kyc.bank_account_holder || '',
      bank_ifsc: data.kyc.bank_ifsc || '',
      bank_name: data.kyc.bank_name || '',
      // Identity numbers come back masked, so the inputs start empty and only
      // send a value when the seller actually types a new one. Blanking them
      // would otherwise submit "••••1234F" as a PAN.
      pan: '',
      gstin: '',
      bank_account_number: '',
    });
  }, []);

  const load = useCallback(async () => {
    if (!authToken) { setLoading(false); return; }
    setLoading(true);
    try {
      const res = await apiFetch('/seller/onboarding', { token: authToken });
      adopt(res.data);
    } catch (err) {
      // 403 with no seller account is the normal "not applied yet" path.
      if (err.status === 403) setNeedsApplication(true);
      else setNotice(err.message);
    } finally {
      setLoading(false);
    }
  }, [authToken, adopt]);

  useEffect(() => { load(); }, [load]);

  const apply = async (e) => {
    e.preventDefault();
    setBusy(true); setErrors({}); setNotice('');
    try {
      const res = await apiFetch('/sellers/apply', {
        method: 'POST', token: authToken, body: { display_name: applyName.trim() },
      });
      adopt(res.data);
    } catch (err) {
      setNotice(err.message);
    } finally { setBusy(false); }
  };

  const saveKyc = async () => {
    setBusy(true); setErrors({}); setNotice('');
    try {
      // Only send the identity fields the seller actually retyped.
      const body = { ...form };
      for (const key of ['pan', 'gstin', 'bank_account_number']) {
        if (!body[key]) delete body[key];
      }
      const res = await apiFetch('/seller/onboarding/kyc', {
        method: 'PUT', token: authToken, body,
      });
      adopt(res.data);
      setNotice('Saved.');
    } catch (err) {
      setErrors(err.fieldErrors || {});
      setNotice(err.message);
    } finally { setBusy(false); }
  };

  /**
   * Multipart, so this bypasses apiFetch — that helper always sends JSON, and
   * setting Content-Type by hand on a FormData body strips the boundary.
   */
  const uploadDocument = async (kind, file) => {
    setBusy(true); setNotice('');
    const body = new FormData();
    body.append('kind', kind);
    body.append('file', file);

    try {
      const res = await fetch(`${API_BASE}/seller/onboarding/documents`, {
        method: 'POST',
        headers: { Accept: 'application/json', Authorization: `Bearer ${authToken}` },
        body,
      });
      const json = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(json.message || 'Upload failed.');
      adopt(json.data.onboarding);
      setNotice(`${DOC_LABELS[kind] || kind} uploaded.`);
    } catch (err) {
      setNotice(err.message);
    } finally { setBusy(false); }
  };

  const removeDocument = async (id) => {
    setBusy(true);
    try {
      const res = await apiFetch(`/seller/onboarding/documents/${id}`, {
        method: 'DELETE', token: authToken,
      });
      adopt(res.data);
    } catch (err) { setNotice(err.message); } finally { setBusy(false); }
  };

  const submit = async () => {
    setBusy(true); setErrors({}); setNotice('');
    try {
      const res = await apiFetch('/seller/onboarding/submit', { method: 'POST', token: authToken });
      adopt(res.data);
      setNotice(res.message || 'Submitted for review.');
    } catch (err) {
      setErrors(err.fieldErrors || {});
      setNotice(err.message);
    } finally { setBusy(false); }
  };

  // ── Render ───────────────────────────────────────────────────────────

  if (!authToken) {
    return (
      <Shell>
        <div className="p-8 text-center space-y-2">
          <Store className="w-10 h-10 mx-auto text-ink-subtle" />
          <p className="text-sm font-black text-ink">Sign in to start selling</p>
          <p className="text-xs text-ink-muted font-medium">
            You need an account before you can apply.
          </p>
        </div>
      </Shell>
    );
  }

  if (loading) {
    return (
      <Shell>
        <div className="p-12 flex justify-center">
          <RefreshCw className="w-6 h-6 animate-spin text-accent" />
          <span className="sr-only">Loading your application</span>
        </div>
      </Shell>
    );
  }

  if (needsApplication) {
    return (
      <Shell>
        <form onSubmit={apply} className="space-y-4 p-5 border border-line rounded-card bg-surface">
          <div>
            <h2 className="text-base font-black text-ink">Start selling on {`BazaarX`}</h2>
            <p className="text-xs text-ink-muted font-medium mt-1">
              Tell us your shop name to begin. You&apos;ll add your business and bank details next,
              and we&apos;ll verify them before your shop goes live.
            </p>
          </div>

          <Field label="Shop name" hint="This is what shoppers will see on your products.">
            <input
              className={inputClass}
              value={applyName}
              onChange={e => setApplyName(e.target.value)}
              placeholder="e.g. Jaipur Handicrafts"
              maxLength={120}
              required
            />
          </Field>

          {notice && <p className="text-xs font-bold text-danger">{notice}</p>}

          <button
            type="submit"
            disabled={busy || !applyName.trim()}
            className="btn-primary w-full justify-center text-sm py-3 disabled:opacity-50"
          >
            {busy ? 'Starting…' : 'Apply to sell'}
          </button>
        </form>
      </Shell>
    );
  }

  // Loaded, not an un-applied user, and still nothing to show: the request
  // failed some other way (server down, network, an unexpected status). Say so
  // and offer a retry — destructuring null here is how this crashed to a blank
  // "page couldn't load" screen with the real reason only in the console.
  if (!state) {
    return (
      <Shell>
        <div className="p-8 text-center space-y-3 border border-line rounded-card bg-surface">
          <AlertCircle className="w-8 h-8 mx-auto text-danger" />
          <p className="text-sm font-black text-ink">We couldn&apos;t load your application</p>
          {notice && <p className="text-xs text-ink-muted font-medium">{notice}</p>}
          <button onClick={load} className="btn-primary text-sm py-2.5 px-5">Try again</button>
        </div>
      </Shell>
    );
  }

  const { kyc, checklist, documents, seller, business_types: businessTypes, accepted_document_kinds: docKinds } = state;
  const editable = checklist.editable;

  return (
    <Shell>
      <div className="space-y-5">
        <StatusBanner sellerStatus={seller.status} kyc={kyc} />

        {notice && (
          <div className="flex items-start gap-2 text-xs font-bold text-ink bg-surface-muted border border-line rounded-control p-3">
            <span className="flex-1">{notice}</span>
            <button onClick={() => setNotice('')} aria-label="Dismiss">
              <X className="w-3.5 h-3.5" />
            </button>
          </div>
        )}

        {/* Business details */}
        <section className="p-5 border border-line rounded-card bg-surface space-y-4">
          <h3 className="text-sm font-black text-ink flex items-center gap-2">
            <Building2 className="w-4 h-4 text-accent" /> Business details
          </h3>

          <div className="grid grid-cols-2 gap-3">
            <Field label="Business type">
              <select
                className={inputClass} disabled={!editable}
                value={form.business_type}
                onChange={e => setForm(f => ({ ...f, business_type: e.target.value }))}
              >
                {(businessTypes || []).map(t => (
                  <option key={t} value={t}>{BUSINESS_TYPE_LABELS[t] || t}</option>
                ))}
              </select>
            </Field>

            <Field label="Legal name">
              <input
                className={inputClass} disabled={!editable}
                value={form.legal_name}
                onChange={e => setForm(f => ({ ...f, legal_name: e.target.value }))}
              />
            </Field>

            <Field label="PAN" hint={kyc.pan ? `On file: ${kyc.pan}` : 'Format ABCDE1234F'}>
              <input
                className={inputClass} disabled={!editable}
                value={form.pan}
                onChange={e => setForm(f => ({ ...f, pan: e.target.value }))}
                placeholder={kyc.pan ? 'Enter to replace' : 'ABCDE1234F'}
                maxLength={10}
              />
              {errors.pan && <span className="block text-[10px] font-bold text-danger mt-1">{errors.pan[0]}</span>}
            </Field>

            <Field label="GSTIN (optional)" hint={kyc.gstin ? `On file: ${kyc.gstin}` : 'Only if registered'}>
              <input
                className={inputClass} disabled={!editable}
                value={form.gstin}
                onChange={e => setForm(f => ({ ...f, gstin: e.target.value }))}
                placeholder={kyc.gstin ? 'Enter to replace' : '08ABCDE1234F1Z5'}
                maxLength={15}
              />
              {errors.gstin && <span className="block text-[10px] font-bold text-danger mt-1">{errors.gstin[0]}</span>}
            </Field>
          </div>

          <Field label="Registered address">
            <input
              className={inputClass} disabled={!editable}
              value={form.registered_line1}
              onChange={e => setForm(f => ({ ...f, registered_line1: e.target.value }))}
              placeholder="Building, street"
            />
          </Field>

          <div className="grid grid-cols-3 gap-3">
            <Field label="City">
              <input className={inputClass} disabled={!editable} value={form.registered_city}
                onChange={e => setForm(f => ({ ...f, registered_city: e.target.value }))} />
            </Field>
            <Field label="State">
              <input className={inputClass} disabled={!editable} value={form.registered_state}
                onChange={e => setForm(f => ({ ...f, registered_state: e.target.value }))} />
            </Field>
            <Field label="PIN code">
              <input className={inputClass} disabled={!editable} value={form.registered_pincode}
                onChange={e => setForm(f => ({ ...f, registered_pincode: e.target.value }))} maxLength={6} />
              {errors.registered_pincode && (
                <span className="block text-[10px] font-bold text-danger mt-1">{errors.registered_pincode[0]}</span>
              )}
            </Field>
          </div>
        </section>

        {/* Settlement */}
        <section className="p-5 border border-line rounded-card bg-surface space-y-4">
          <h3 className="text-sm font-black text-ink flex items-center gap-2">
            <Landmark className="w-4 h-4 text-accent" /> Where we send your payouts
          </h3>

          <div className="grid grid-cols-2 gap-3">
            <Field label="Account holder name">
              <input className={inputClass} disabled={!editable} value={form.bank_account_holder}
                onChange={e => setForm(f => ({ ...f, bank_account_holder: e.target.value }))} />
            </Field>
            <Field label="Bank name (optional)">
              <input className={inputClass} disabled={!editable} value={form.bank_name}
                onChange={e => setForm(f => ({ ...f, bank_name: e.target.value }))} />
            </Field>
            <Field
              label="Account number"
              hint={kyc.bank_account_number ? `On file: ${kyc.bank_account_number}` : '9 to 18 digits'}
            >
              <input
                className={inputClass} disabled={!editable}
                value={form.bank_account_number}
                onChange={e => setForm(f => ({ ...f, bank_account_number: e.target.value }))}
                placeholder={kyc.bank_account_number ? 'Enter to replace' : ''}
                inputMode="numeric" maxLength={18}
              />
              {errors.bank_account_number && (
                <span className="block text-[10px] font-bold text-danger mt-1">{errors.bank_account_number[0]}</span>
              )}
            </Field>
            <Field label="IFSC">
              <input className={inputClass} disabled={!editable} value={form.bank_ifsc}
                onChange={e => setForm(f => ({ ...f, bank_ifsc: e.target.value }))}
                placeholder="HDFC0001234" maxLength={11} />
              {errors.bank_ifsc && (
                <span className="block text-[10px] font-bold text-danger mt-1">{errors.bank_ifsc[0]}</span>
              )}
            </Field>
          </div>

          {editable && (
            <button onClick={saveKyc} disabled={busy}
              className="btn-primary text-sm py-2.5 px-5 disabled:opacity-50">
              {busy ? 'Saving…' : 'Save details'}
            </button>
          )}
        </section>

        {/* Documents */}
        <section className="p-5 border border-line rounded-card bg-surface space-y-4">
          <h3 className="text-sm font-black text-ink flex items-center gap-2">
            <ShieldCheck className="w-4 h-4 text-accent" /> Documents
          </h3>
          <p className="text-xs text-ink-muted font-medium">
            JPG, PNG or PDF, up to 5 MB. Stored privately and only visible to our verification team.
          </p>

          <div className="space-y-2">
            {(docKinds || []).map(kind => {
              const held = documents.find(d => d.kind === kind);
              const required = checklist.missing_documents.includes(kind);

              return (
                <div key={kind}
                  className="flex items-center gap-3 p-3 border border-line rounded-control bg-surface-muted">
                  <FileText className={`w-4 h-4 shrink-0 ${held ? 'text-success' : 'text-ink-subtle'}`} />
                  <div className="flex-1 min-w-0">
                    <p className="text-xs font-extrabold text-ink">
                      {DOC_LABELS[kind] || kind}
                      {required && <span className="text-danger ml-1">*</span>}
                    </p>
                    {held ? (
                      <p className="text-[10px] text-ink-subtle font-medium truncate">{held.original_name}</p>
                    ) : (
                      <p className="text-[10px] text-ink-subtle font-medium">Not uploaded</p>
                    )}
                  </div>

                  {held && (
                    <a
                      href={`${API_BASE}/seller/documents/${held.id}/download`}
                      className="text-[10px] font-bold text-accent hover:underline"
                      target="_blank" rel="noreferrer"
                    >
                      View
                    </a>
                  )}

                  {editable && (
                    <>
                      <label className="text-[10px] font-bold text-accent cursor-pointer hover:underline">
                        <Upload className="w-3.5 h-3.5 inline mr-1" />
                        {held ? 'Replace' : 'Upload'}
                        <input
                          type="file" className="hidden"
                          accept=".jpg,.jpeg,.png,.webp,.pdf"
                          disabled={busy}
                          onChange={e => {
                            const file = e.target.files?.[0];
                            if (file) uploadDocument(kind, file);
                            e.target.value = '';
                          }}
                        />
                      </label>
                      {held && (
                        <button onClick={() => removeDocument(held.id)} disabled={busy}
                          className="text-ink-subtle hover:text-danger" aria-label={`Remove ${DOC_LABELS[kind]}`}>
                          <Trash2 className="w-3.5 h-3.5" />
                        </button>
                      )}
                    </>
                  )}
                </div>
              );
            })}
          </div>
        </section>

        {/* Submit */}
        {editable && (
          <section className="p-5 border border-line rounded-card bg-surface-muted space-y-3">
            {(checklist.missing_fields.length > 0 || checklist.missing_documents.length > 0) && (
              <div className="space-y-1">
                <p className="text-xs font-black text-ink">Still needed before you can submit</p>
                <ul className="text-[11px] text-ink-muted font-semibold space-y-0.5">
                  {checklist.missing_fields.map(f => (
                    <li key={f}>• {FIELD_LABELS[f] || f}</li>
                  ))}
                  {checklist.missing_documents.map(d => (
                    <li key={d}>• {DOC_LABELS[d] || d}</li>
                  ))}
                </ul>
              </div>
            )}

            <button
              onClick={submit}
              disabled={busy || !checklist.can_submit}
              className="btn-primary w-full justify-center text-sm py-3 disabled:opacity-50"
            >
              {busy ? 'Submitting…' : 'Submit for review'}
            </button>
          </section>
        )}
      </div>
    </Shell>
  );
}

function Shell({ children }) {
  return (
    <main className="max-w-2xl mx-auto px-4 py-8">
      <header className="mb-6">
        <h1 className="text-xl font-black text-ink flex items-center gap-2">
          <Store className="w-5 h-5 text-accent" /> Seller onboarding
        </h1>
        <p className="text-xs text-ink-muted font-medium mt-1">
          Verified sellers only. We check every application before a shop goes live.
        </p>
      </header>
      {children}
    </main>
  );
}

export default function SellerOnboardingClient() {
  const { storeConfig } = useStore();
  // A store that sells only its own goods has no seller area: the links are hidden,
  // and this covers someone who types the address.
  if (!offersSelling(storeConfig)) return <VendorsOff />;
  return <OnboardingFlow />;
}
