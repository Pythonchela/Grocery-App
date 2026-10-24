'use client';

import React, { useState } from 'react';
import { ClipboardList, Users } from 'lucide-react';
import SellerApplicationsClient from '../../../components/admin/SellerApplicationsClient';
import SellerRosterClient from '../../../components/admin/SellerRosterClient';
import { useStoreConfig } from '../../../components/admin/useStoreConfig';

const VIEWS = [
  { key: 'applications', label: 'Applications', icon: ClipboardList },
  { key: 'roster', label: 'All sellers', icon: Users },
];

export default function AdminSellersPage() {
  const [view, setView] = useState('applications');
  const store = useStoreConfig();

  // A single-business store has no vendors and no applications: this page is
  // only the owner's own shop (the roster client shows just that).
  const single = store ? !store.vendors_enabled : false;

  return (
    <div className="min-h-screen bg-surface-sunken">
      <div className="max-w-4xl mx-auto px-4 py-8 space-y-5">
        {!single && (
          <div className="flex gap-2">
            {VIEWS.map(v => {
              const Icon = v.icon;
              return (
                <button
                  key={v.key}
                  onClick={() => setView(v.key)}
                  className={`flex items-center gap-1.5 px-3.5 py-2 rounded-control text-xs font-black transition ${
                    view === v.key
                      ? 'bg-ink text-ink-inverse'
                      : 'bg-surface border border-line text-ink-muted hover:text-ink'
                  }`}
                >
                  <Icon className="w-3.5 h-3.5" /> {v.label}
                </button>
              );
            })}
          </div>
        )}

        {single || view === 'roster' ? <SellerRosterClient /> : <SellerApplicationsClient />}
      </div>
    </div>
  );
}
