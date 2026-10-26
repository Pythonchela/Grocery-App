'use client';

import React, { useEffect, useRef, useState } from 'react';

export const STATUS = {
  configured: { label: 'Configured', tone: 'bg-success-soft text-success', dot: 'bg-success' },
  partial: { label: 'Incomplete', tone: 'bg-warning-soft text-warning', dot: 'bg-warning' },
  missing: { label: 'Not set up', tone: 'bg-surface-sunken text-ink-muted', dot: 'bg-line-strong' },
  // Working, but the state to move off before going live.
  local: { label: 'Server disk', tone: 'bg-warning-soft text-warning', dot: 'bg-warning' },
};

export const inputClass =
  'w-full bg-surface border border-line rounded-control px-3.5 py-2.5 text-base text-ink placeholder:text-ink-subtle focus:outline-none focus:border-accent';

export function Badge({ tone, children }) {
  return (
    <span className={`inline-flex items-center px-2.5 py-1 rounded-pill text-2xs font-black whitespace-nowrap ${tone}`}>
      {children}
    </span>
  );
}

export function StatusBadge({ status }) {
  const s = STATUS[status] ?? STATUS.missing;
  return <Badge tone={s.tone}>{s.label}</Badge>;
}

// ── History ─────────────────────────────────────────────────────────────

const ACTION_LABEL = { SET: 'Changed', CLEAR: 'Removed', TEST: 'Tested', DENIED: 'Blocked' };

export function AuditTable({ rows }) {
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
export function PasswordModal({ title, onClose, onConfirm }) {
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
