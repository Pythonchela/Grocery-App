'use client';

import React from 'react';
import PayoutsClient from '../../../components/admin/PayoutsClient';
import { useStoreConfig } from '../../../components/admin/useStoreConfig';

export default function AdminPayoutsPage() {
  const store = useStoreConfig();

  return (
    <div className="min-h-screen bg-surface-sunken">
      <div className="max-w-4xl mx-auto px-4 py-8 space-y-5">
        {/* A single-business store has no vendors to pay. */}
        {store && !store.vendors_enabled ? (
          <p className="text-sm font-bold text-ink-muted">This store sells only its own goods, so there are no vendor payouts.</p>
        ) : (
          <PayoutsClient />
        )}
      </div>
    </div>
  );
}
