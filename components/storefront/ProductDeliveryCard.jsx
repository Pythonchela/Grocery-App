'use client';

import React, { useEffect, useRef, useState } from 'react';
import { CheckCircle2, MapPin, Truck, XCircle, Zap } from 'lucide-react';
import { useStore } from '../providers/StoreProvider';
import { apiFetch, formatINR } from '../../lib/apiClient';
import { etaPhrase, fastestOption, generalDelivery } from '../../lib/productPage';

const PIN_KEY = 'haatvia_pincode';
const PIN = /^[1-9][0-9]{5}$/;

function rememberedPin() {
  try {
    return localStorage.getItem(PIN_KEY) || '';
  } catch {
    return '';
  }
}

/**
 * "Delivery details": when this would arrive at the shopper's PIN code, from the
 * same delivery quote the cart uses, so it is the real promise rather than a
 * guess. The code comes from their default address, or the last one they typed.
 * With no code it says how the item is delivered in general instead.
 */
export default function ProductDeliveryCard({ product, price }) {
  const { authToken } = useStore();
  const [pincode, setPincode] = useState('');
  const [place, setPlace] = useState('');
  const [busy, setBusy] = useState(false);
  const [quote, setQuote] = useState(null);
  const [error, setError] = useState('');
  const latest = useRef(0);

  const check = async (code) => {
    const run = ++latest.current;
    setBusy(true);
    setError('');
    try {
      const res = await apiFetch('/delivery/quote', {
        method: 'POST',
        body: { pincode: code, cod: false, order_value: price, items: [{ product_id: product.id, quantity: 1 }] },
      });
      if (run !== latest.current) return;
      setQuote(res.data);
      try { localStorage.setItem(PIN_KEY, code); } catch { /* non-critical */ }
    } catch (e) {
      if (run !== latest.current) return;
      setQuote(null);
      setError(e.message);
    } finally {
      if (run === latest.current) setBusy(false);
    }
  };

  // Start from the default address, else the last code typed on this browser.
  useEffect(() => {
    let cancelled = false;
    const start = async () => {
      if (authToken) {
        try {
          const res = await apiFetch('/addresses', { token: authToken });
          const list = res.data || [];
          const address = list.find((a) => a.is_default) || list[0];
          if (address && PIN.test(address.pincode) && !cancelled) {
            setPincode(address.pincode);
            setPlace([address.line1, address.city].filter(Boolean).join(', '));
            check(address.pincode);
            return;
          }
        } catch { /* fall through to the remembered code */ }
      }
      const saved = rememberedPin();
      if (PIN.test(saved) && !cancelled) {
        setPincode(saved);
        check(saved);
      }
    };
    start();
    return () => { cancelled = true; };
  }, [authToken, product.id]);

  const option = quote?.serviceable ? fastestOption(quote.options) : null;
  const phrase = option ? etaPhrase(option) : null;
  const blocked = quote && !quote.serviceable;

  return (
    <div className="rounded-card border border-line overflow-hidden">
      <div className="px-4 pt-4 pb-2 flex items-center gap-2 text-sm font-black text-ink">
        <Truck className="w-5 h-5 text-accent" /> Delivery details
      </div>

      <form
        className="px-4 pb-3 flex gap-2"
        onSubmit={(e) => { e.preventDefault(); if (PIN.test(pincode)) check(pincode); }}
      >
        <input
          type="text"
          inputMode="numeric"
          autoComplete="postal-code"
          aria-label="Delivery PIN code"
          placeholder="Enter PIN code"
          value={pincode}
          maxLength={6}
          onChange={(e) => { setPincode(e.target.value.replace(/\D/g, '')); setPlace(''); }}
          className="flex-1 min-w-0 bg-surface border border-line rounded-control px-4 py-2 text-sm font-semibold focus:outline-none focus:border-ink"
        />
        <button
          type="submit"
          disabled={!PIN.test(pincode) || busy}
          className="bg-accent text-ink-inverse px-6 py-2 rounded-control text-sm font-bold disabled:opacity-50"
        >
          {busy ? 'Checking...' : 'Check'}
        </button>
      </form>

      <div className="border-t border-line divide-y divide-line">
        {quote && (
          <div className="px-4 py-3 flex items-center gap-3 text-sm font-semibold text-ink">
            <MapPin className="w-5 h-5 text-ink-muted shrink-0" />
            <span className="truncate">{[place, quote.pincode].filter(Boolean).join(', ')}</span>
          </div>
        )}

        <div className="px-4 py-3 flex items-start gap-3 text-sm">
          {blocked ? (
            <XCircle className="w-5 h-5 text-danger shrink-0" />
          ) : phrase ? (
            <CheckCircle2 className="w-5 h-5 text-success shrink-0" />
          ) : product.deliveryProfile === 'instant' ? (
            <Zap className="w-5 h-5 text-ink-muted shrink-0" />
          ) : (
            <Truck className="w-5 h-5 text-ink-muted shrink-0" />
          )}

          {blocked ? (
            <p className="font-semibold text-danger">
              {quote.message || 'We do not deliver to this PIN code yet.'}
            </p>
          ) : phrase ? (
            <div className="font-semibold">
              <p>
                <span className="text-ink-muted">{phrase.lead} </span>
                <span className="font-bold text-ink">{phrase.when}</span>
              </p>
              {option && (
                <p className="text-xs text-ink-subtle font-medium mt-0.5">
                  {option.price > 0 ? `Delivery ${formatINR(option.price)}` : option.free_reason || 'Free delivery'}
                </p>
              )}
            </div>
          ) : (
            <p className="font-semibold text-ink">{error || generalDelivery(product)}</p>
          )}
        </div>
      </div>
    </div>
  );
}
