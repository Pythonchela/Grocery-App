'use client';

import React, { useCallback, useEffect, useRef, useState } from 'react';
import Link from 'next/link';
import { ShieldAlert, CheckCircle2, AlertCircle, Copy, PlugZap, Lock } from 'lucide-react';
import { apiFetch } from '../../lib/apiClient';
import { useAdminAuth } from './AdminAuthContext';

const STATUS = {
  configured: { label: 'Configured', tone: 'bg-success-soft text-success' },
  partial: { label: 'Incomplete', tone: 'bg-warning-soft text-warning' },
  missing: { label: 'Not set up', tone: 'bg-surface-sunken text-ink-muted' },
  // Working, but the state to move off before going live.
  local: { label: 'Server disk', tone: 'bg-warning-soft text-warning' },
};

const SOURCE = {
  admin: 'Set here',
  environment: 'From the server',
  unset: 'Not set',
};

// Couriers are tested one at a time; everything else has a single test.
const TEST_TARGETS = {
  couriers: [{ target: 'shiprocket', label: 'Test Shiprocket' }],
  email: [{ target: undefined, label: 'Send test email' }],
  sms: [{ target: undefined, label: 'Send test message' }],
  storage: [{ target: undefined, label: 'Test storage' }],
};

// A choice decides which of the other fields apply, so only those are shown:
// picking the Log mailer hides the SMTP host, and the local disk hides the buckets.
const VISIBLE_WHEN = {
  email: {
    selector: 'mailer',
    fields: Object.fromEntries(
      ['from_address', 'from_name', 'smtp_host', 'smtp_port', 'smtp_username', 'smtp_password'].map((f) => [f, ['smtp']]),
    ),
  },
  sms: {
    selector: 'driver',
    fields: {
      order_updates: ['msg91', 'twilio'],
      msg91_authkey: ['msg91'],
      msg91_template_otp: ['msg91'],
      msg91_template_order: ['msg91'],
      twilio_sid: ['twilio'],
      twilio_token: ['twilio'],
      twilio_from: ['twilio'],
    },
  },
  storage: {
    selector: 'driver',
    fields: Object.fromEntries(
      ['bucket', 'private_bucket', 'public_url', 'region', 'endpoint', 'access_key', 'secret_key'].map((f) => [f, ['s3']]),
    ),
  },
};

const OPTION_LABELS = {
  log: 'Log only (send nothing)', smtp: 'SMTP', msg91: 'MSG91', twilio: 'Twilio',
  local: 'This server’s disk', s3: 'S3 or compatible bucket', off: 'Off', on: 'On',
};

const inputClass =
  'w-full bg-surface border border-line rounded-control px-3.5 py-2.5 text-base text-ink placeholder:text-ink-subtle focus:outline-none focus:border-accent';

function Badge({ tone, children }) {
  return (
    <span className={`inline-flex items-center px-2.5 py-1 rounded-pill text-2xs font-black ${tone}`}>
      {children}
    </span>
  );
}

/**
 * Everything the admin can configure, one card per integration.
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

  const closeConfirm = useCallback(() => setConfirm(null), []);

  if (forbidden) {
    return (
      <div className="max-w-md mx-auto text-center py-16">
        <ShieldAlert className="w-12 h-12 text-warning mx-auto mb-4" />
        <h2 className="text-xl font-black text-ink mb-2">Restricted to full admins</h2>
        <p className="text-base text-ink-muted mb-6">
          API keys and integration settings can only be changed by a full admin.
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
        {error || 'Could not load the integrations.'}
      </div>
    );
  }

  const done = async (message) => {
    setNotice(message);
    setConfirm(null);
    await load();
  };

  return (
    <div className="space-y-6">
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

      {!data.can_confirm && (
        <div role="alert" className="rounded-control bg-warning-soft border border-warning/20 px-4 py-3 text-base text-ink">
          <p className="font-bold flex items-center gap-2"><Lock className="w-4 h-4" /> Your account has no password</p>
          <p className="text-sm text-ink-muted mt-1">
            Changes are confirmed with your password, so you cannot save yet. Whoever runs the
            server can set one with <code className="font-mono">php artisan bazaarx:set-password your@email</code>.
          </p>
        </div>
      )}

      {data.groups.map((group) => (
        <GroupCard
          key={group.id}
          group={group}
          token={token}
          canSave={data.can_confirm}
          askPassword={setConfirm}
          onDone={done}
          onError={setError}
        />
      ))}

      <PaymentsCard payments={data.payments} />
      <MonitoringCard monitoring={data.monitoring} />
      <AuditTable rows={audit} />

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

// ── One integration ─────────────────────────────────────────────────────

function GroupCard({ group, token, canSave, askPassword, onDone, onError }) {
  const [drafts, setDrafts] = useState({});
  const [replacing, setReplacing] = useState({});
  const [fieldErrors, setFieldErrors] = useState({});
  const [result, setResult] = useState(null);
  const [testing, setTesting] = useState(null);
  const [testPhone, setTestPhone] = useState('');

  const dirty = Object.keys(drafts).length > 0;
  const status = STATUS[group.status] ?? STATUS.missing;

  const setDraft = (name, value) => setDrafts((d) => ({ ...d, [name]: value }));

  const errorsFrom = (err) => {
    const mapped = {};
    Object.entries(err.fieldErrors || {}).forEach(([key, messages]) => {
      mapped[key.replace(/^values\./, '')] = [].concat(messages).join(' ');
    });
    return mapped;
  };

  const save = () => {
    setResult(null);
    setFieldErrors({});
    askPassword({
      title: `Save ${group.label}`,
      run: async (password) => {
        try {
          const res = await apiFetch(`/admin/integrations/${group.id}`, {
            method: 'PUT',
            token,
            body: { current_password: password, values: drafts },
          });
          setDrafts({});
          setReplacing({});
          await onDone(res.message || 'Saved.');
        } catch (err) {
          // A wrong password stays in the dialog; a bad value goes back to its field.
          if (err.fieldErrors && !err.fieldErrors.current_password) {
            setFieldErrors(errorsFrom(err));
            askPassword(null);
            return null;
          }
          return err.message;
        }
        return null;
      },
    });
  };

  const revert = (field) => {
    askPassword({
      title: `Remove ${field.label}`,
      run: async (password) => {
        try {
          const res = await apiFetch(`/admin/integrations/${group.id}/${field.name}`, {
            method: 'DELETE',
            token,
            body: { current_password: password },
          });
          await onDone(res.message || 'Removed.');
        } catch (err) {
          return err.message;
        }
        return null;
      },
    });
  };

  const runTest = async (target) => {
    setTesting(target || 'default');
    setResult(null);
    try {
      // Unsaved entries are tested as typed, without being saved.
      const values = Object.fromEntries(Object.entries(drafts).filter(([, v]) => v !== '' && v != null));
      const res = await apiFetch(`/admin/integrations/${group.id}/test`, {
        method: 'POST',
        token,
        // An SMS test goes to the number typed beside the button.
        body: { values, target: group.id === 'sms' ? testPhone : target },
      });
      setResult(res.data);
    } catch (err) {
      setFieldErrors(errorsFrom(err));
      onError(err.message);
    } finally {
      setTesting(null);
    }
  };

  const targets = group.testable ? (TEST_TARGETS[group.id] ?? [{ target: undefined, label: 'Test connection' }]) : [];

  // What the choice field currently says (saved, or as just changed).
  const rule = VISIBLE_WHEN[group.id];
  const chosen = rule
    ? (drafts[rule.selector] ?? group.fields.find((f) => f.name === rule.selector)?.value)
    : null;
  const shown = group.fields.filter((f) => !rule || !rule.fields[f.name] || rule.fields[f.name].includes(chosen));

  return (
    <section aria-labelledby={`int-${group.id}`} className="rounded-card border border-line bg-surface">
      <div className="p-5 border-b border-line flex items-start justify-between gap-4">
        <div>
          <h2 id={`int-${group.id}`} className="text-lg font-black text-ink">{group.label}</h2>
          <p className="text-sm text-ink-muted mt-0.5">{group.description}</p>
        </div>
        <Badge tone={status.tone}>{status.label}</Badge>
      </div>

      <div className="p-5 space-y-5">
        {group.status === 'local' && (
          <div role="note" className="rounded-control bg-warning-soft border border-warning/20 px-3.5 py-2.5 text-sm text-ink">
            Files are on this server&apos;s disk. They are lost if you move servers, so switch to a bucket before going live.
          </div>
        )}

        {shown.map((field) => (
          <FieldRow
            key={field.key}
            field={field}
            draft={drafts[field.name]}
            replacing={!!replacing[field.name]}
            error={fieldErrors[field.name]}
            onChange={(value) => setDraft(field.name, value)}
            onReplace={() => setReplacing((r) => ({ ...r, [field.name]: true }))}
            onCancelReplace={() => {
              setReplacing((r) => ({ ...r, [field.name]: false }));
              setDrafts((d) => {
                const { [field.name]: _omit, ...rest } = d;
                return rest;
              });
            }}
            onRevert={() => revert(field)}
          />
        ))}

        {result && (
          <div
            role="status"
            className={`flex items-start gap-2 rounded-control px-3.5 py-2.5 text-sm ${
              result.status === 'ok'
                ? 'bg-success-soft text-success'
                : result.status === 'failed'
                  ? 'bg-danger-soft text-danger'
                  : 'bg-surface-muted text-ink-muted'
            }`}
          >
            {result.status === 'ok' ? <CheckCircle2 className="w-4 h-4 mt-0.5 shrink-0" /> : <AlertCircle className="w-4 h-4 mt-0.5 shrink-0" />}
            {result.message}
          </div>
        )}
      </div>

      <div className="px-5 py-4 border-t border-line flex flex-wrap items-center justify-end gap-3">
        {group.id === 'sms' && group.testable && (
          <div className="mr-auto flex items-center gap-2">
            <label htmlFor="sms-test-phone" className="text-xs font-bold text-ink-muted">Test number</label>
            <input
              id="sms-test-phone"
              type="tel"
              inputMode="numeric"
              maxLength={10}
              value={testPhone}
              onChange={(e) => setTestPhone(e.target.value.replace(/[^0-9]/g, ''))}
              placeholder="10 digits"
              className="w-32 bg-surface border border-line rounded-control px-3 py-2 text-base text-ink placeholder:text-ink-subtle focus:outline-none focus:border-accent"
            />
          </div>
        )}
        {targets.map((t) => (
          <button
            key={t.label}
            type="button"
            onClick={() => runTest(t.target)}
            disabled={testing !== null}
            className="flex items-center gap-1.5 px-4 py-2 rounded-pill border border-line text-sm font-bold text-ink-muted hover:text-ink disabled:opacity-50"
          >
            <PlugZap className="w-3.5 h-3.5" /> {testing === (t.target || 'default') ? 'Testing…' : t.label}
          </button>
        ))}
        <button
          type="button"
          onClick={save}
          disabled={!dirty || !canSave}
          className="px-5 py-2 rounded-pill bg-primary text-on-primary text-sm font-bold shadow-button hover:bg-primary-hover transition disabled:opacity-40"
        >
          Save changes
        </button>
      </div>
    </section>
  );
}

function FieldRow({ field, draft, replacing, error, onChange, onReplace, onCancelReplace, onRevert }) {
  const id = `field-${field.key}`;
  const source = SOURCE[field.source] ?? '';

  const heading = (
    <div className="flex items-center justify-between gap-3 mb-1.5">
      <label htmlFor={id} className="text-xs font-bold text-ink-muted">{field.label}</label>
      <span className="text-2xs text-ink-subtle">{source}</span>
    </div>
  );

  const hint = (
    <>
      {field.unreadable && (
        <p className="mt-1 text-2xs text-warning">
          A saved value could not be read (the server&apos;s encryption key changed). Enter it again.
        </p>
      )}
      {field.help && <p className="mt-1 text-2xs text-ink-subtle">{field.help}</p>}
      {error && <p role="alert" className="mt-1 text-xs text-danger">{error}</p>}
    </>
  );

  if (field.secret) {
    const showInput = !field.is_set || replacing || field.unreadable;

    return (
      <div>
        {heading}
        {showInput ? (
          <div className="flex gap-2">
            <input
              id={id}
              type="password"
              autoComplete="new-password"
              spellCheck={false}
              value={draft ?? ''}
              onChange={(e) => onChange(e.target.value)}
              placeholder={field.placeholder || 'Paste the key'}
              className={inputClass}
            />
            {replacing && (
              <button type="button" onClick={onCancelReplace} className="px-3 text-sm font-bold text-ink-muted hover:text-ink">
                Cancel
              </button>
            )}
          </div>
        ) : (
          <div className="flex items-center gap-3">
            <div id={id} className="flex-1 bg-surface-muted border border-line rounded-control px-3.5 py-2.5 text-base text-ink-muted font-mono">
              {field.source === 'environment' ? 'Set on the server' : (field.masked ?? 'Set')}
            </div>
            <button type="button" onClick={onReplace} className="px-3 py-2 text-sm font-bold text-accent hover:underline">
              Replace
            </button>
            {field.source === 'admin' && (
              <button type="button" onClick={onRevert} className="px-3 py-2 text-sm font-bold text-danger hover:underline">
                Remove
              </button>
            )}
          </div>
        )}
        {hint}
      </div>
    );
  }

  if (field.type === 'select') {
    return (
      <div>
        {heading}
        <select
          id={id}
          value={draft ?? field.value ?? ''}
          onChange={(e) => onChange(e.target.value)}
          className={inputClass}
        >
          {field.options.map((option) => (
            <option key={option} value={option}>{OPTION_LABELS[option] ?? option}</option>
          ))}
        </select>
        {hint}
      </div>
    );
  }

  if (field.type === 'list') {
    const selected = draft ?? field.value ?? [];
    const toggle = (option) =>
      onChange(selected.includes(option) ? selected.filter((o) => o !== option) : [...selected, option]);

    return (
      <fieldset>
        <legend className="flex w-full items-center justify-between gap-3 mb-1.5">
          <span className="text-xs font-bold text-ink-muted">{field.label}</span>
          <span className="text-2xs text-ink-subtle">{source}</span>
        </legend>
        <div className="flex flex-wrap gap-2">
          {field.options.map((option) => (
            <label
              key={option}
              className={`flex items-center gap-2 px-3 py-1.5 rounded-pill border text-sm cursor-pointer transition ${
                selected.includes(option) ? 'border-accent bg-accent-soft text-ink' : 'border-line text-ink-muted'
              }`}
            >
              <input
                type="checkbox"
                checked={selected.includes(option)}
                onChange={() => toggle(option)}
                className="accent-accent"
              />
              <span className="capitalize">{option}</span>
            </label>
          ))}
        </div>
        {hint}
      </fieldset>
    );
  }

  return (
    <div>
      {heading}
      <input
        id={id}
        type={field.type === 'number' ? 'number' : 'text'}
        inputMode={field.type === 'number' ? 'decimal' : undefined}
        step={field.type === 'number' ? 'any' : undefined}
        value={draft ?? field.value ?? ''}
        onChange={(e) => onChange(e.target.value)}
        placeholder={field.placeholder || undefined}
        className={inputClass}
      />
      {hint}
    </div>
  );
}

// ── Payments (read-only) ────────────────────────────────────────────────

function PaymentsCard({ payments }) {
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

  return (
    <section aria-labelledby="int-payments" className="rounded-card border border-line bg-surface">
      <div className="p-5 border-b border-line flex items-start justify-between gap-4">
        <div>
          <h2 id="int-payments" className="text-lg font-black text-ink flex items-center gap-2">
            <Lock className="w-4 h-4 text-ink-subtle" /> Payments
          </h2>
          <p className="text-sm text-ink-muted mt-0.5">{payments.note}</p>
        </div>
        <Badge tone={payments.configured ? 'bg-success-soft text-success' : 'bg-surface-sunken text-ink-muted'}>
          {payments.configured ? 'Configured' : 'Not set up'}
        </Badge>
      </div>

      <dl className="p-5 grid gap-4 sm:grid-cols-3 text-sm">
        <div>
          <dt className="text-xs font-bold text-ink-muted">Mode</dt>
          <dd className="text-ink mt-1 capitalize">{payments.mode ?? 'Unknown'}</dd>
        </div>
        <div>
          <dt className="text-xs font-bold text-ink-muted">Webhook secret</dt>
          <dd className="text-ink mt-1">{payments.webhook_secret_set ? 'Set' : 'Not set'}</dd>
        </div>
        <div>
          <dt className="text-xs font-bold text-ink-muted">Online payment at checkout</dt>
          <dd className="text-ink mt-1">{payments.online_payment_available ? 'Available' : 'Unavailable'}</dd>
        </div>
      </dl>

      <div className="px-5 pb-5">
        <p className="text-xs font-bold text-ink-muted mb-1.5">Webhook URL to register with the gateway</p>
        <div className="flex items-center gap-2">
          <code className="flex-1 bg-surface-muted border border-line rounded-control px-3.5 py-2.5 text-xs text-ink font-mono break-all">
            {payments.webhook_url}
          </code>
          <button
            type="button"
            onClick={copy}
            className="flex items-center gap-1.5 px-3 py-2 rounded-pill border border-line text-xs font-bold text-ink-muted hover:text-ink"
          >
            <Copy className="w-3.5 h-3.5" /> {copied ? 'Copied' : 'Copy'}
          </button>
        </div>
      </div>
    </section>
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
            Reports have keys, passwords, cookies and request bodies removed before they leave the server.
          </p>
        </div>
        <Badge tone={monitoring.configured ? 'bg-success-soft text-success' : 'bg-surface-sunken text-ink-muted'}>
          {monitoring.configured ? 'Reporting' : 'Not set up'}
        </Badge>
      </div>
    </section>
  );
}

// ── History ─────────────────────────────────────────────────────────────

const ACTION_LABEL = { SET: 'Changed', CLEAR: 'Removed', TEST: 'Tested', DENIED: 'Blocked' };

function AuditTable({ rows }) {
  return (
    <section aria-labelledby="int-audit" className="rounded-card border border-line bg-surface">
      <div className="p-5 border-b border-line">
        <h2 id="int-audit" className="text-lg font-black text-ink">Recent activity</h2>
        <p className="text-sm text-ink-muted mt-0.5">Who changed what, and when. Values are never recorded.</p>
      </div>
      {rows.length === 0 ? (
        <p className="p-5 text-base text-ink-muted">Nothing yet.</p>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full text-left text-sm">
            <thead className="bg-surface-muted border-b border-line">
              <tr className="text-2xs uppercase tracking-wider text-ink-subtle">
                <th className="px-4 py-3 font-black">When</th>
                <th className="px-4 py-3 font-black">Who</th>
                <th className="px-4 py-3 font-black">What</th>
                <th className="px-4 py-3 font-black">Result</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((row) => (
                <tr key={row.id} className="border-b border-line last:border-0">
                  <td className="px-4 py-3 text-ink-muted whitespace-nowrap">{new Date(row.at).toLocaleString()}</td>
                  <td className="px-4 py-3 text-ink">{row.who?.name ?? 'Unknown'}</td>
                  <td className="px-4 py-3 text-ink">
                    {ACTION_LABEL[row.action] ?? row.action} · {row.group}
                    {row.field ? ` · ${row.field}` : ''}
                  </td>
                  <td className="px-4 py-3 text-ink-muted">{row.outcome}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </section>
  );
}

// ── Password confirmation ───────────────────────────────────────────────

/**
 * Asks for the admin's password. `onConfirm(password)` resolves to an error
 * message to keep the dialog open with, or null once it succeeded (and the
 * parent closes it).
 */
function PasswordModal({ title, onClose, onConfirm }) {
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const input = useRef(null);

  // Focus moves into the dialog, and Escape leaves it.
  useEffect(() => {
    input.current?.focus();
    const onKey = (e) => e.key === 'Escape' && onClose();
    document.addEventListener('keydown', onKey);
    return () => document.removeEventListener('keydown', onKey);
  }, [onClose]);

  const submit = async (e) => {
    e.preventDefault();
    setBusy(true);
    setError(null);
    const message = await onConfirm(password);
    // Never keep the password in state longer than the request.
    setPassword('');
    if (message) {
      setError(message);
      setBusy(false);
    }
  };

  return (
    <div className="fixed inset-0 z-modal flex items-center justify-center p-4">
      <button type="button" aria-label="Close" onClick={onClose} className="absolute inset-0 bg-inverse/50 backdrop-blur-sm cursor-default" />
      <form
        onSubmit={submit}
        role="dialog"
        aria-modal="true"
        aria-labelledby="confirm-title"
        className="relative w-full max-w-sm bg-surface rounded-panel shadow-panel p-6 space-y-4"
      >
        <div>
          <h2 id="confirm-title" className="text-lg font-black text-ink">{title}</h2>
          <p className="text-xs text-ink-muted">Enter your password to confirm. This protects your keys if your session is ever taken over.</p>
        </div>

        {error && (
          <div role="alert" className="rounded-control bg-danger-soft border border-danger/20 px-3 py-2 text-sm text-danger">{error}</div>
        )}

        <div>
          <label htmlFor="confirm-password" className="block text-xs font-bold text-ink-muted mb-1.5">Your password</label>
          <input
            id="confirm-password"
            ref={input}
            type="password"
            autoComplete="current-password"
            required
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            className={inputClass}
          />
        </div>

        <div className="flex gap-3 pt-1">
          <button type="button" onClick={onClose} className="flex-1 px-4 py-2.5 rounded-pill border border-line text-sm font-bold text-ink-muted hover:text-ink">
            Cancel
          </button>
          <button type="submit" disabled={busy || !password} className="flex-1 px-4 py-2.5 rounded-pill bg-primary text-on-primary text-sm font-bold disabled:opacity-50">
            {busy ? 'Confirming…' : 'Confirm'}
          </button>
        </div>
      </form>
    </div>
  );
}
