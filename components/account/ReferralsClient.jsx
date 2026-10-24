'use client';

import React, { useEffect, useState } from 'react';
import { useStore } from '../providers/StoreProvider';
import { apiFetch, formatINR, formatDate } from '../../lib/apiClient';
import { Gift, Copy, Check, RefreshCw, Users, IndianRupee } from 'lucide-react';

const STATUS_LABELS = {
  PENDING: 'Pending first order',
  REWARDED: 'Rewarded',
};

/**
 * Refer & earn: the code, a share link, and the running tally.
 *
 * The backend has carried this end-to-end since day one — a code minted per
 * user, a reward paid on the referee's first qualifying order — but nothing
 * ever showed a shopper their own code. A referral program nobody can find
 * their invite link for doesn't run.
 */
export default function ReferralsClient() {
  const { authToken } = useStore();
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);
  const [copied, setCopied] = useState(false);

  useEffect(() => {
    if (!authToken) return;
    apiFetch('/referrals', { token: authToken })
      .then(res => setData(res.data))
      .finally(() => setLoading(false));
  }, [authToken]);

  if (loading) {
    return (
      <div className="flex items-center justify-center gap-2 py-16 text-ink-subtle font-bold">
        <RefreshCw className="w-4 h-4 animate-spin" /> Loading referrals...
      </div>
    );
  }

  if (!data) {
    return <p className="text-sm text-ink-subtle font-bold py-10 text-center">Sign in to see your referral code.</p>;
  }

  const shareLink = typeof window !== 'undefined'
    ? `${window.location.origin}/?ref=${data.code}`
    : `/?ref=${data.code}`;

  const copyLink = async () => {
    try {
      await navigator.clipboard.writeText(shareLink);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      // Clipboard API can be denied by the browser; the code is still
      // selectable text, so this isn't a dead end for the shopper.
    }
  };

  const invites = data.invites || [];

  return (
    <div className="space-y-5">
      <div className="bg-gradient-to-br from-inverse to-accent text-ink-inverse rounded-panel p-6">
        <Gift className="w-6 h-6 opacity-80 mb-3" />
        <p className="text-sm font-bold opacity-80">Your referral code</p>
        <p className="text-3xl font-black tracking-wide mt-1">{data.code}</p>
        <p className="text-[11px] opacity-70 mt-2 font-medium">
          You earn {formatINR(data.referrer_reward)} and they get {formatINR(data.referee_reward)} off,
          once their first order is delivered.
        </p>

        <div className="mt-4 flex items-center gap-2 bg-inverse/15 rounded-control px-3 py-2.5">
          <span className="flex-1 text-xs font-mono truncate">{shareLink}</span>
          <button
            onClick={copyLink}
            className="shrink-0 flex items-center gap-1 text-[11px] font-black bg-inverse/20 hover:bg-inverse/30 px-2.5 py-1.5 rounded-control transition"
          >
            {copied ? <Check className="w-3.5 h-3.5" /> : <Copy className="w-3.5 h-3.5" />}
            {copied ? 'Copied' : 'Copy link'}
          </button>
        </div>
      </div>

      <div className="grid grid-cols-2 gap-4">
        <div className="bg-surface border border-line rounded-panel p-5">
          <IndianRupee className="w-5 h-5 text-success mb-2" />
          <p className="text-2xl font-black text-ink">{formatINR(data.total_earned)}</p>
          <p className="text-xs font-bold text-ink-subtle mt-0.5">Total earned</p>
        </div>
        <div className="bg-surface border border-line rounded-panel p-5">
          <Users className="w-5 h-5 text-warning mb-2" />
          <p className="text-2xl font-black text-ink">{data.pending_count}</p>
          <p className="text-xs font-bold text-ink-subtle mt-0.5">Awaiting first order</p>
        </div>
      </div>

      <div className="bg-surface border border-line rounded-panel overflow-hidden">
        <div className="px-5 py-4 border-b border-line">
          <h2 className="font-black text-ink text-sm">People you've invited</h2>
        </div>

        {invites.length === 0 ? (
          <div className="p-10 text-center text-ink-subtle font-bold text-sm">
            Nobody yet — share your link above to start earning.
          </div>
        ) : (
          <div className="divide-y divide-line">
            {invites.map(inv => (
              <div key={inv.id} className="flex items-center justify-between gap-3 px-5 py-3.5">
                <div>
                  <p className="text-sm font-bold text-ink">{inv.name}</p>
                  <p className="text-[11px] text-ink-subtle font-medium">
                    Joined {formatDate(inv.joined_at)}
                  </p>
                </div>
                <div className="text-right shrink-0">
                  <span className={`text-[10px] font-black px-2 py-1 rounded-pill ${
                    inv.status === 'REWARDED' ? 'bg-success/10 text-success' : 'bg-warning/10 text-warning'
                  }`}>
                    {STATUS_LABELS[inv.status] || inv.status}
                  </span>
                  {inv.status === 'REWARDED' && (
                    <p className="text-[11px] font-bold text-success mt-1">+{formatINR(inv.reward)}</p>
                  )}
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
