'use client';

import React, { useCallback, useEffect, useState } from 'react';
import Link from 'next/link';
import { ShieldAlert, ShieldCheck, Copy, Lock } from 'lucide-react';
import { apiFetch } from '../../lib/apiClient';
import { GUIDES } from '../../lib/integrationGuides';
import { useAdminAuth } from './AdminAuthContext';
import Guide from './integrations/Guide';
import GroupPanel from './integrations/GroupPanel';
import { AuditTable, Badge, PasswordModal, STATUS, StatusBadge } from './integrations/shared';

/**
 * One tab per kind of key, plus an Overview for everything general.
 *
 * `need` says how much a store depends on it: Required to take orders, Recommended
 * for a real launch, Optional extras.
 */
const TABS = [
  { id: 'overview', label: 'Overview' },
  { id: 'google', label: 'Google sign-in', group: 'google', need: 'Optional', purpose: 'Let shoppers sign in with their Google account.' },
  { id: 'email', label: 'Email', group: 'email', need: 'Recommended', purpose: 'Order confirmations and account emails.' },
  { id: 'sms', label: 'SMS & OTP', group: 'sms', need: 'Recommended', purpose: 'The code for phone sign-in, and optional order texts.' },
  { id: 'couriers', label: 'Delivery partners', group: 'couriers', need: 'Recommended', purpose: 'Courier accounts for quotes, booking and tracking.' },
  { id: 'push', label: 'Push', group: 'push', need: 'Optional', purpose: 'Order updates on shoppers\' phones.' },
  { id: 'storage', label: 'File storage', group: 'storage', need: 'Recommended', purpose: 'Keep product images safe off the server disk.' },
  { id: 'gemini', label: 'AI (Gemini)', group: 'gemini', need: 'Optional', purpose: 'AI search, review summaries and product import.' },
  { id: 'payments', label: 'Payments', need: 'Required', purpose: 'Razorpay. Set on the server, shown here read-only.' },
];

const NEED_TONE = {
  Required: 'bg-danger-soft text-danger',
  Recommended: 'bg-warning-soft text-warning',
  Optional: 'bg-surface-sunken text-ink-muted',
};

const tabFromHash = () => {
  if (typeof window === 'undefined') return 'overview';
  const id = window.location.hash.replace('#', '');
  return TABS.some((t) => t.id === id) ? id : 'overview';
};

/**
 * Everything the admin can configure.
 *
 * A secret is write-only here: the API never returns one, so the page can only
 * show that it is set. Saving or removing anything asks for the admin's password
 * again, in a dialog, and the password is sent with that one request only.
 */
export default function IntegrationsClient() {
  const { token } = useAdminAuth();

  const [data, setData] = useState(null);
  const [audit, setAudit] = useState([]);
  const [loading, setLoading] = useState(true);
  const [forbidden, setForbidden] = useState(false);
  const [error, setError] = useState(null);
  const [notice, setNotice] = useState(null);
  const [confirm, setConfirm] = useState(null); // { title, run(password) }
  const [tab, setTab] = useState('overview');
  const [dirty, setDirty] = useState({});

  const load = useCallback(async () => {
    try {
      const [res, log] = await Promise.all([
        apiFetch('/admin/integrations', { token }),
        apiFetch('/admin/integrations/audit', { token }),
      ]);
      setData(res.data);
      setAudit(log.data ?? []);
      setError(null);
    } catch (e) {
      if (e.status === 403) setForbidden(true);
      else setError(e.message);
    } finally {
      setLoading(false);
    }
  }, [token]);

  useEffect(() => {
    if (token) load();
  }, [token, load]);

  // The tab lives in the address (#google), so it survives a reload and the back button.
  useEffect(() => {
    const sync = () => setTab(tabFromHash());
    sync();
    window.addEventListener('hashchange', sync);
    return () => window.removeEventListener('hashchange', sync);
  }, []);

  const closeConfirm = useCallback(() => setConfirm(null), []);
  const markDirty = useCallback((id, isDirty) => setDirty((d) => (d[id] === isDirty ? d : { ...d, [id]: isDirty })), []);

  if (forbidden) {
    return (
      <div className="max-w-md mx-auto text-center py-16">
        <ShieldAlert className="w-12 h-12 text-warning mx-auto mb-4" />
        <h2 className="text-xl font-black text-ink mb-2">Restricted to full admins</h2>
        <p className="text-base text-ink-muted mb-6">
          API keys and settings can only be changed by a full admin.
        </p>
        <Link href="/admin" className="inline-block px-5 py-2.5 rounded-pill bg-primary text-on-primary text-sm font-bold">
          Back to the dashboard
        </Link>
      </div>
    );
  }

  if (loading) return <p className="text-ink-muted text-base">Loading…</p>;
  if (!data) {
    return (
      <div className="rounded-control bg-danger-soft border border-danger/20 px-4 py-3 text-base text-danger">
        {error || 'Could not load the settings.'}
      </div>
    );
  }

  const done = async (message) => {
    setNotice(message);
    setError(null);
    setConfirm(null);
    await load();
  };

  const groups = Object.fromEntries(data.groups.map((g) => [g.id, g]));
  const statusOf = (t) => (t.id === 'payments' ? (data.payments.configured ? 'configured' : 'missing') : groups[t.group]?.status ?? 'missing');

  const open = (id) => {
    setNotice(null);
    window.location.hash = id;
  };

  const panelProps = { token, canSave: data.can_confirm, askPassword: setConfirm, onDone: done, onError: setError, onDirty: markDirty };

  return (
    <div className="space-y-5">
      {!data.can_confirm && (
        <div role="alert" className="rounded-control bg-warning-soft border border-warning/20 px-4 py-3 text-base text-ink">
          <p className="font-bold flex items-center gap-2"><Lock className="w-4 h-4" /> Your account has no password</p>
          <p className="text-sm text-ink-muted mt-1">
            Changes are confirmed with your password, so you cannot save yet. Whoever runs the
            server can set one with <code className="font-mono">php artisan bazaarx:set-password your@email</code>.
          </p>
        </div>
      )}

      <div role="tablist" aria-label="Settings" className="flex gap-1 overflow-x-auto border-b border-line -mx-1 px-1">
        {TABS.map((t) => {
          const active = tab === t.id;
          const status = t.id === 'overview' ? null : STATUS[statusOf(t)];

          return (
            <button
              key={t.id}
              type="button"
              role="tab"
              id={`tab-${t.id}`}
              aria-selected={active}
              aria-controls={`panel-${t.id}`}
              onClick={() => open(t.id)}
              className={`flex items-center gap-2 px-3.5 py-2.5 text-sm font-bold whitespace-nowrap border-b-2 -mb-px transition ${
                active ? 'border-accent text-ink' : 'border-transparent text-ink-muted hover:text-ink'
              }`}
            >
              {status && <span aria-hidden="true" className={`w-2 h-2 rounded-full ${status.dot}`} />}
              {t.label}
              {status && <span className="sr-only"> ({status.label})</span>}
              {dirty[t.group] && <span className="text-warning" title="Unsaved changes">●<span className="sr-only"> Unsaved changes</span></span>}
            </button>
          );
        })}
      </div>

      {error && (
        <div role="alert" className="rounded-control bg-danger-soft border border-danger/20 px-4 py-3 text-base text-danger">
          {error}
        </div>
      )}
      {notice && (
        <div role="status" className="rounded-control bg-success-soft border border-success/20 px-4 py-3 text-base text-success">
          {notice}
        </div>
      )}

      {/* Every panel stays mounted so what you typed survives a switch of tab. */}
      <div role="tabpanel" id="panel-overview" aria-labelledby="tab-overview" hidden={tab !== 'overview'} className="space-y-6">
        <Overview data={data} groups={groups} tabs={TABS} statusOf={statusOf} open={open} audit={audit} panelProps={panelProps} />
      </div>

      {TABS.filter((t) => t.group).map((t) => (
        <div key={t.id} role="tabpanel" id={`panel-${t.id}`} aria-labelledby={`tab-${t.id}`} hidden={tab !== t.id}>
          {groups[t.group] && <GroupPanel group={groups[t.group]} {...panelProps} />}
        </div>
      ))}

      <div role="tabpanel" id="panel-payments" aria-labelledby="tab-payments" hidden={tab !== 'payments'}>
        <PaymentsPanel payments={data.payments} />
      </div>

      {confirm && (
        <PasswordModal
          title={confirm.title}
          onClose={closeConfirm}
          onConfirm={confirm.run}
        />
      )}
    </div>
  );
}

// ── The landing tab ─────────────────────────────────────────────────────

function Overview({ data, groups, tabs, statusOf, open, audit, panelProps }) {
  const items = tabs.filter((t) => t.id !== 'overview');
  const todo = items.filter((t) => t.need === 'Required' && statusOf(t) !== 'configured');

  return (
    <>
      <section aria-labelledby="int-checklist" className="rounded-card border border-line bg-surface">
        <div className="p-5 border-b border-line">
          <h2 id="int-checklist" className="text-xl font-black text-ink">Setup checklist</h2>
          <p className="text-sm text-ink-muted mt-0.5">
            {todo.length > 0
              ? `${todo.map((t) => t.label).join(', ')} still needs setting up before you take real orders.`
              : 'Everything required is set up. Work through the recommended items before you launch.'}
          </p>
        </div>
        <div className="overflow-x-auto">
          <table className="w-full text-left text-sm">
            <thead className="bg-surface-muted border-b border-line">
              <tr className="text-2xs uppercase tracking-wider text-ink-subtle">
                <th scope="col" className="px-5 py-3 font-black">What</th>
                <th scope="col" className="px-3 py-3 font-black">Needed</th>
                <th scope="col" className="px-3 py-3 font-black">Status</th>
                <th scope="col" className="px-5 py-3 font-black"><span className="sr-only">Open</span></th>
              </tr>
            </thead>
            <tbody>
              {items.map((t) => (
                <tr key={t.id} className="border-b border-line last:border-0">
                  <td className="px-5 py-3">
                    <p className="font-bold text-ink">{t.label}</p>
                    <p className="text-xs text-ink-muted">{t.purpose}</p>
                  </td>
                  <td className="px-3 py-3"><Badge tone={NEED_TONE[t.need]}>{t.need}</Badge></td>
                  <td className="px-3 py-3"><StatusBadge status={statusOf(t)} /></td>
                  <td className="px-5 py-3 text-right">
                    <button
                      type="button"
                      onClick={() => open(t.id)}
                      className="px-3.5 py-1.5 rounded-pill border border-line text-xs font-bold text-ink-muted hover:text-ink whitespace-nowrap"
                    >
                      {statusOf(t) === 'configured' ? 'Review' : 'Set up'}
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>

      <Guide guide={GUIDES.overview} defaultOpen={todo.length > 0} />

      {groups.shipping && (
        <div className="space-y-3">
          <div>
            <h2 className="text-xl font-black text-ink">General settings</h2>
            <p className="text-sm text-ink-muted mt-0.5">{groups.shipping.description}</p>
          </div>
          <GroupPanel group={groups.shipping} guideKey="general" showHeader={false} {...panelProps} />
        </div>
      )}

      <MonitoringCard monitoring={data.monitoring} />
      <ProtectionCard />
      <AuditTable rows={audit} />
    </>
  );
}

function ProtectionCard() {
  const points = [
    'Keys are encrypted when stored, and the page can never read them back. After saving you only see that a key is set, and the last four characters of a long one.',
    'Only full admins can open this page, and every change asks for your password again, so a stolen login session alone cannot change a key.',
    'Wrong passwords are limited, and every change is logged by who and when. The log never holds a key.',
    'Payment keys and server addresses are not editable here at all. They live in the server\'s private file.',
  ];

  return (
    <section aria-labelledby="int-protection" className="rounded-card border border-line bg-surface p-5">
      <h2 id="int-protection" className="text-lg font-black text-ink flex items-center gap-2">
        <ShieldCheck className="w-4 h-4 text-success" /> How your keys are protected
      </h2>
      <ul className="mt-3 space-y-2 list-disc pl-5 text-sm text-ink-muted">
        {points.map((p) => <li key={p}>{p}</li>)}
      </ul>
    </section>
  );
}

// ── Payments (read-only) ────────────────────────────────────────────────

function PaymentsPanel({ payments }) {
  const [copied, setCopied] = useState(false);

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(payments.webhook_url);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      setCopied(false);
    }
  };

  const rows = [
    ['Razorpay keys', payments.configured ? 'Set on the server' : 'Not set'],
    ['Mode', payments.mode ? (payments.mode === 'live' ? 'Live (real money)' : 'Test (no real money)') : 'Unknown'],
    ['Webhook secret', payments.webhook_secret_set ? 'Set' : 'Not set'],
    ['Online payment at checkout', payments.online_payment_available ? 'Available' : 'Unavailable'],
  ];

  return (
    <div className="space-y-4">
      <div className="flex items-start justify-between gap-4">
        <div>
          <h2 id="int-payments" className="text-xl font-black text-ink flex items-center gap-2">
            <Lock className="w-4 h-4 text-ink-subtle" /> Payments
          </h2>
          <p className="text-sm text-ink-muted mt-0.5">{payments.note}</p>
        </div>
        <StatusBadge status={payments.configured ? 'configured' : 'missing'} />
      </div>

      <Guide guide={GUIDES.payments} defaultOpen={!payments.configured} />

      <section aria-label="Payment status" className="rounded-card border border-line bg-surface overflow-hidden">
        <div className="hidden md:grid grid-cols-[minmax(0,5fr)_minmax(0,7fr)] gap-x-6 px-5 py-2.5 bg-surface-muted border-b border-line text-2xs uppercase tracking-wider font-black text-ink-subtle">
          <span>Check</span>
          <span>Now</span>
        </div>
        <dl className="divide-y divide-line">
          {rows.map(([label, value]) => (
            <div key={label} className="grid gap-x-6 gap-y-1 px-5 py-3.5 md:grid-cols-[minmax(0,5fr)_minmax(0,7fr)]">
              <dt className="text-sm font-bold text-ink">{label}</dt>
              <dd className="text-sm text-ink-muted">{value}</dd>
            </div>
          ))}
          <div className="grid gap-x-6 gap-y-2 px-5 py-3.5 md:grid-cols-[minmax(0,5fr)_minmax(0,7fr)] items-start">
            <dt className="text-sm font-bold text-ink">
              Webhook URL
              <span className="block text-xs font-normal text-ink-subtle mt-1">Paste this into Razorpay when you add the webhook.</span>
            </dt>
            <dd className="flex items-center gap-2 min-w-0">
              <code className="flex-1 min-w-0 bg-surface-muted border border-line rounded-control px-3.5 py-2.5 text-xs text-ink font-mono break-all">
                {payments.webhook_url}
              </code>
              <button
                type="button"
                onClick={copy}
                className="flex items-center gap-1.5 px-3 py-2 rounded-pill border border-line text-xs font-bold text-ink-muted hover:text-ink"
              >
                <Copy className="w-3.5 h-3.5" /> {copied ? 'Copied' : 'Copy'}
              </button>
            </dd>
          </div>
        </dl>
      </section>
    </div>
  );
}

// ── Error tracking (read-only) ──────────────────────────────────────────

function MonitoringCard({ monitoring }) {
  if (!monitoring) return null;

  return (
    <section aria-labelledby="int-monitoring" className="rounded-card border border-line bg-surface">
      <div className="p-5 flex items-start justify-between gap-4">
        <div>
          <h2 id="int-monitoring" className="text-lg font-black text-ink flex items-center gap-2">
            <Lock className="w-4 h-4 text-ink-subtle" /> Error tracking
          </h2>
          <p className="text-sm text-ink-muted mt-0.5">{monitoring.note}</p>
          <p className="text-xs text-ink-subtle mt-2">
            Sentry tells you when something breaks for a shopper. Create a free project at sentry.io (platform: Laravel),
            copy its DSN from Project Settings → Client Keys, and give it to whoever runs the server. Reports have keys,
            passwords, cookies and request bodies removed before they leave the server.
          </p>
        </div>
        <Badge tone={monitoring.configured ? 'bg-success-soft text-success' : 'bg-surface-sunken text-ink-muted'}>
          {monitoring.configured ? 'Reporting' : 'Not set up'}
        </Badge>
      </div>
    </section>
  );
}
