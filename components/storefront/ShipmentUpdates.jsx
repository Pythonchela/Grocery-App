'use client';

import { useEffect, useState } from 'react';
import { ExternalLink, MapPin, Truck } from 'lucide-react';
import { apiFetch, formatDate } from '../../lib/apiClient';

const when = (iso) => {
  const d = iso ? new Date(iso) : null;
  if (!d || Number.isNaN(d.getTime())) return '';
  return d.toLocaleString('en-IN', { day: 'numeric', month: 'short', hour: 'numeric', minute: '2-digit' });
};

/**
 * Where a parcel is and when it is due, for deliveries that take days.
 *
 * Shown instead of the live map: the API says which applies
 * (GET /delivery/orders/{id}/track -> mode). Renders nothing for fast rider
 * deliveries, which keep the map, or when the order has not been dispatched.
 */
export default function ShipmentUpdates({ orderId, status, token }) {
  const [data, setData] = useState(null);

  useEffect(() => {
    if (!orderId || !token || status === 'CANCELLED') return undefined;
    let alive = true;
    const load = () =>
      apiFetch(`/delivery/orders/${orderId}/track`, { token })
        .then((res) => alive && setData(res.data))
        .catch(() => {});
    load();
    // Parcels move slowly: a gentle refresh is plenty.
    const id = setInterval(load, 120000);
    return () => { alive = false; clearInterval(id); };
  }, [orderId, token, status]);

  if (!data || data.mode !== 'status_updates') return null;

  const problem = ['DELAYED', 'DELIVERY_FAILED', 'RETURNING'].includes(data.status);
  const delivered = data.status === 'DELIVERED';

  return (
    <div className="bg-surface border border-line rounded-card overflow-hidden mt-8">
      <div className="p-4 border-b border-line flex items-start justify-between gap-4">
        <div className="flex items-center gap-3 min-w-0">
          <div className="w-10 h-10 bg-accent-soft text-accent rounded-pill flex items-center justify-center shrink-0">
            <Truck className="w-5 h-5" />
          </div>
          <div className="min-w-0">
            <h3 className="font-semibold text-ink">{data.status_label}</h3>
            {data.carrier_label && (
              <p className="text-xs text-ink-subtle truncate">
                {data.carrier_label}{data.tracking_no ? ` · #${data.tracking_no}` : ''}
              </p>
            )}
          </div>
        </div>
        {!delivered && data.expected_by && (
          <div className="text-right shrink-0">
            <p className="text-xs text-ink-subtle">Expected by</p>
            <p className="font-semibold text-ink">{formatDate(data.expected_by)}</p>
          </div>
        )}
      </div>

      {problem && (
        <p className="px-4 py-2 text-sm font-medium bg-warning-soft text-warning border-b border-line">
          {data.events?.[0]?.description || 'The courier reported a problem with this shipment.'}
        </p>
      )}

      {data.location && !delivered && (
        <p className="px-4 py-3 text-sm text-ink-muted flex items-center gap-2 border-b border-line">
          <MapPin className="w-4 h-4 text-accent shrink-0" />
          Last seen at <span className="font-semibold text-ink">{data.location}</span>
        </p>
      )}

      <ol className="p-4 space-y-4">
        {(data.events || []).map((e, i) => (
          <li key={`${e.status}-${e.at}-${i}`} className="flex gap-3">
            <span className="flex flex-col items-center">
              <span className={`w-3 h-3 rounded-pill border-2 mt-1 ${i === 0 ? 'bg-accent border-accent' : 'bg-surface border-line-strong'}`} />
              {i < data.events.length - 1 && <span className="w-0.5 flex-1 bg-line mt-1" />}
            </span>
            <span className="pb-1">
              <span className={`block text-sm ${i === 0 ? 'font-semibold' : 'font-medium'} text-ink`}>{e.label}</span>
              {e.location && <span className="block text-xs text-ink-muted">{e.location}</span>}
              {when(e.at) && <span className="block text-xs text-ink-subtle">{when(e.at)}</span>}
            </span>
          </li>
        ))}
      </ol>

      {data.track_url && (
        <a
          href={data.track_url}
          target="_blank"
          rel="noreferrer"
          className="flex items-center justify-center gap-2 px-4 py-3 border-t border-line text-sm font-semibold text-accent hover:bg-surface-sunken"
        >
          Track on {data.carrier_label || 'courier'} <ExternalLink className="w-4 h-4" />
        </a>
      )}
    </div>
  );
}
