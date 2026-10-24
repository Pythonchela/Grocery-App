'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { apiFetch } from '../../lib/apiClient';

const POLL_MS = 15000;
const RING_EVERY_MS = 20000;
const STORAGE_KEY = 'seller.orderSound';

function readSoundPreference() {
  try { return window.localStorage.getItem(STORAGE_KEY) === 'on'; } catch { return false; }
}

/** Three short beeps. Needs an AudioContext that a click has already unlocked. */
function beep(ctx) {
  if (!ctx) return;
  [0, 0.28, 0.56].forEach((offset) => {
    const osc = ctx.createOscillator();
    const gain = ctx.createGain();
    osc.type = 'sine';
    osc.frequency.value = 880;
    gain.gain.setValueAtTime(0.0001, ctx.currentTime + offset);
    gain.gain.exponentialRampToValueAtTime(0.35, ctx.currentTime + offset + 0.02);
    gain.gain.exponentialRampToValueAtTime(0.0001, ctx.currentTime + offset + 0.2);
    osc.connect(gain).connect(ctx.destination);
    osc.start(ctx.currentTime + offset);
    osc.stop(ctx.currentTime + offset + 0.22);
  });
}

/**
 * Keeps an eye on the shop while the dashboard is open: how many orders wait for
 * an answer, how many are late to pack. A new order rings (when the seller has
 * switched sound on), keeps ringing until it is answered, puts the count in the
 * tab title, and raises a desktop notification if allowed.
 */
export default function useOrderAlerts(token, enabled) {
  const [counts, setCounts] = useState({ newOrders: 0, late: 0, toPack: 0 });
  const [soundOn, setSoundOnState] = useState(false);
  const ctxRef = useRef(null);
  const seenRef = useRef(0);
  const countRef = useRef(0);
  const baseTitle = useRef('');

  useEffect(() => {
    setSoundOnState(readSoundPreference());
    baseTitle.current = document.title;
    return () => { document.title = baseTitle.current; };
  }, []);

  const setSoundOn = useCallback((on) => {
    setSoundOnState(on);
    try { window.localStorage.setItem(STORAGE_KEY, on ? 'on' : 'off'); } catch { /* private mode: still works for this visit */ }
    if (on) {
      try {
        const AudioCtx = window.AudioContext || window.webkitAudioContext;
        if (AudioCtx && !ctxRef.current) ctxRef.current = new AudioCtx();
        ctxRef.current?.resume();
        beep(ctxRef.current);
      } catch { /* no audio on this device */ }
      if (typeof Notification !== 'undefined' && Notification.permission === 'default') {
        Notification.requestPermission().catch(() => {});
      }
    }
  }, []);

  const refresh = useCallback(async () => {
    if (!token || !enabled) return;
    try {
      const res = await apiFetch('/seller/overview', { token });
      const data = res.data || {};
      const next = { newOrders: data.new_orders || 0, late: data.late_to_pack || 0, toPack: data.to_pack || 0 };
      setCounts(next);
      countRef.current = next.newOrders;

      if (next.newOrders > seenRef.current) {
        if (soundOn) beep(ctxRef.current);
        if (typeof Notification !== 'undefined' && Notification.permission === 'granted') {
          try { new Notification('New order', { body: `${next.newOrders} waiting for your answer` }); } catch { /* ignore */ }
        }
      }
      seenRef.current = next.newOrders;
      document.title = next.newOrders > 0 ? `(${next.newOrders}) New orders — ${baseTitle.current}` : baseTitle.current;
    } catch { /* a missed poll is fine; the next one catches up */ }
  }, [token, enabled, soundOn]);

  useEffect(() => {
    if (!token || !enabled) return undefined;
    refresh();
    const id = setInterval(() => { if (!document.hidden) refresh(); }, POLL_MS);
    const onVisible = () => { if (!document.hidden) refresh(); };
    document.addEventListener('visibilitychange', onVisible);
    return () => { clearInterval(id); document.removeEventListener('visibilitychange', onVisible); };
  }, [token, enabled, refresh]);

  // An unanswered order keeps ringing, like a till, until somebody deals with it.
  useEffect(() => {
    if (!soundOn || !enabled) return undefined;
    const id = setInterval(() => { if (countRef.current > 0) beep(ctxRef.current); }, RING_EVERY_MS);
    return () => clearInterval(id);
  }, [soundOn, enabled]);

  return { ...counts, soundOn, setSoundOn, refresh };
}
