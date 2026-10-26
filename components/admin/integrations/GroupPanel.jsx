'use client';

import React, { useEffect, useState } from 'react';
import { CheckCircle2, AlertCircle, PlugZap } from 'lucide-react';
import { apiFetch } from '../../../lib/apiClient';
import { GUIDES } from '../../../lib/integrationGuides';
import Guide from './Guide';
import { StatusBadge, inputClass } from './shared';

const SOURCE = {
  admin: { label: 'Set here', tone: 'text-success' },
  environment: { label: 'From the server', tone: 'text-ink-muted' },
  unset: { label: 'Not set', tone: 'text-ink-subtle' },
};

// Couriers are tested one at a time; everything else has a single test.
const TEST_TARGETS = {
  couriers: [{ target: 'shiprocket', label: 'Test Shiprocket' }],
  email: [{ target: undefined, label: 'Send test email' }],
  sms: [{ target: undefined, label: 'Send test message' }],
  storage: [{ target: undefined, label: 'Test storage' }],
};

// A choice decides which of the other fields apply, so only those are shown:
// picking the Log mailer hides the SMTP host, and the local disk hides the bucket.
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
      ['bucket', 'public_url', 'region', 'endpoint', 'access_key', 'secret_key'].map((f) => [f, ['s3']]),
    ),
  },
};

// Long forms are cut into labelled blocks by the start of the field's name.
const SECTIONS = {
  couriers: {
    fallback: 'Which couriers',
    prefixes: [['shiprocket_', 'Shiprocket'], ['delhivery_', 'Delhivery'], ['ola_', 'Ola'], ['rapido_', 'Rapido'], ['porter_', 'Porter']],
  },
  sms: { fallback: 'Provider', prefixes: [['msg91_', 'MSG91'], ['twilio_', 'Twilio']] },
  shipping: { fallback: 'Shipping rules', prefixes: [['pickup_', 'Pickup address']] },
};

const OPTION_LABELS = {
  log: 'Log only (send nothing)', smtp: 'SMTP', msg91: 'MSG91', twilio: 'Twilio',
  local: 'This server’s disk', s3: 'S3 or compatible bucket', off: 'Off', on: 'On',
};

function sectionOf(groupId, field) {
  const sections = SECTIONS[groupId];
  if (!sections) return null;
  return sections.prefixes.find(([prefix]) => field.name.startsWith(prefix))?.[1] ?? sections.fallback;
}

/**
 * One integration: its step-by-step guide, its settings as a table, and the test
 * and save buttons.
 *
 * A secret is write-only here: the API never returns one, so the page can only
 * show that it is set. Saving or removing anything asks for the admin's password
 * again, in a dialog, and the password is sent with that one request only.
 */
export default function GroupPanel({ group, guideKey, token, canSave, askPassword, onDone, onError, onDirty, showHeader = true }) {
  const [drafts, setDrafts] = useState({});
  const [replacing, setReplacing] = useState({});
  const [fieldErrors, setFieldErrors] = useState({});
  const [result, setResult] = useState(null);
  const [testing, setTesting] = useState(null);
  const [testPhone, setTestPhone] = useState('');

  const dirty = Object.keys(drafts).length > 0;
  useEffect(() => { onDirty?.(group.id, dirty); }, [dirty, group.id, onDirty]);

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

  const rows = [];
  let lastSection = null;
  shown.forEach((field) => {
    const section = sectionOf(group.id, field);
    if (section && section !== lastSection) rows.push({ section });
    lastSection = section;
    rows.push({ field });
  });

  const guide = GUIDES[guideKey ?? group.id];

  return (
    <div className="space-y-4">
      {showHeader && (
        <div className="flex items-start justify-between gap-4">
          <div>
            <h2 id={`int-${group.id}`} className="text-xl font-black text-ink">{group.label}</h2>
            <p className="text-sm text-ink-muted mt-0.5">{group.description}</p>
          </div>
          <StatusBadge status={group.status} />
        </div>
      )}

      <Guide guide={guide} defaultOpen={group.status !== 'configured'} skipTo={`settings-${group.id}`} />

      <section id={`settings-${group.id}`} aria-label={`${group.label} settings`} className="rounded-card border border-line bg-surface overflow-hidden">
        {group.status === 'local' && (
          <div role="note" className="border-b border-line bg-warning-soft px-5 py-2.5 text-sm text-ink">
            Files are on this server&apos;s disk. They are lost if you move servers, so switch to a bucket before going live.
          </div>
        )}

        <div className="hidden md:grid grid-cols-[minmax(0,5fr)_minmax(0,7fr)] gap-x-6 px-5 py-2.5 bg-surface-muted border-b border-line text-2xs uppercase tracking-wider font-black text-ink-subtle">
          <span>Setting</span>
          <span>Value</span>
        </div>

        <div className="divide-y divide-line">
          {rows.map((row) =>
            row.section ? (
              <div key={`s-${row.section}`} className="px-5 py-2 bg-surface-muted/60 text-2xs uppercase tracking-wider font-black text-ink-muted">
                {row.section}
              </div>
            ) : (
              <FieldRow
                key={row.field.key}
                field={row.field}
                draft={drafts[row.field.name]}
                replacing={!!replacing[row.field.name]}
                error={fieldErrors[row.field.name]}
                onChange={(value) => setDraft(row.field.name, value)}
                onReplace={() => setReplacing((r) => ({ ...r, [row.field.name]: true }))}
                onCancelReplace={() => {
                  setReplacing((r) => ({ ...r, [row.field.name]: false }));
                  setDrafts((d) => {
                    const { [row.field.name]: _omit, ...rest } = d;
                    return rest;
                  });
                }}
                onRevert={() => revert(row.field)}
              />
            ),
          )}
        </div>

        {result && (
          <div
            role="status"
            className={`mx-5 my-4 flex items-start gap-2 rounded-control px-3.5 py-2.5 text-sm ${
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

        <div className="px-5 py-4 border-t border-line bg-surface-muted/40 flex flex-wrap items-center justify-end gap-3">
          {dirty && <span className="mr-auto text-xs font-bold text-warning">Unsaved changes</span>}
          {group.id === 'sms' && group.testable && (
            <div className={`${dirty ? '' : 'mr-auto'} flex items-center gap-2`}>
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
              className="flex items-center gap-1.5 px-4 py-2 rounded-pill border border-line bg-surface text-sm font-bold text-ink-muted hover:text-ink disabled:opacity-50"
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
    </div>
  );
}

// ── One row of the table ────────────────────────────────────────────────

function FieldRow({ field, draft, replacing, error, onChange, onReplace, onCancelReplace, onRevert }) {
  const id = `field-${field.key}`;
  const source = SOURCE[field.source] ?? SOURCE.unset;

  const label = (
    <div>
      {field.type === 'list' ? (
        <span id={`${id}-label`} className="text-sm font-bold text-ink">{field.label}</span>
      ) : (
        <label htmlFor={id} className="text-sm font-bold text-ink">{field.label}</label>
      )}
      <p className={`text-2xs font-bold mt-0.5 ${source.tone}`}>{source.label}</p>
      {field.help && <p className="mt-1 text-xs text-ink-subtle leading-relaxed">{field.help}</p>}
    </div>
  );

  const notes = (
    <>
      {field.unreadable && (
        <p className="mt-1 text-2xs text-warning">
          A saved value could not be read (the server&apos;s encryption key changed). Enter it again.
        </p>
      )}
      {error && <p role="alert" className="mt-1 text-xs text-danger">{error}</p>}
    </>
  );

  return (
    <div className="grid gap-x-6 gap-y-2 px-5 py-4 md:grid-cols-[minmax(0,5fr)_minmax(0,7fr)] items-start">
      {label}
      <div className="min-w-0">
        <Control
          field={field}
          id={id}
          draft={draft}
          replacing={replacing}
          onChange={onChange}
          onReplace={onReplace}
          onCancelReplace={onCancelReplace}
          onRevert={onRevert}
        />
        {notes}
      </div>
    </div>
  );
}

function Control({ field, id, draft, replacing, onChange, onReplace, onCancelReplace, onRevert }) {
  if (field.secret) {
    const showInput = !field.is_set || replacing || field.unreadable;

    return showInput ? (
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
    );
  }

  if (field.type === 'select') {
    return (
      <select id={id} value={draft ?? field.value ?? ''} onChange={(e) => onChange(e.target.value)} className={inputClass}>
        {field.options.map((option) => (
          <option key={option} value={option}>{OPTION_LABELS[option] ?? option}</option>
        ))}
      </select>
    );
  }

  if (field.type === 'list') {
    const selected = draft ?? field.value ?? [];
    const toggle = (option) =>
      onChange(selected.includes(option) ? selected.filter((o) => o !== option) : [...selected, option]);

    return (
      <div role="group" aria-labelledby={`${id}-label`} className="flex flex-wrap gap-2">
        {field.options.map((option) => (
          <label
            key={option}
            className={`flex items-center gap-2 px-3 py-1.5 rounded-pill border text-sm cursor-pointer transition ${
              selected.includes(option) ? 'border-accent bg-accent-soft text-ink' : 'border-line text-ink-muted'
            }`}
          >
            <input type="checkbox" checked={selected.includes(option)} onChange={() => toggle(option)} className="accent-accent" />
            <span className="capitalize">{option}</span>
          </label>
        ))}
      </div>
    );
  }

  return (
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
  );
}
