'use client';

import React from 'react';
import Link from 'next/link';
import { ArrowLeft, KeyRound } from 'lucide-react';
import IntegrationsClient from '../../../components/admin/IntegrationsClient';

/**
 * Settings & API keys. Full admins only — the API enforces that; the client
 * component explains the refusal for anyone who navigates here anyway.
 */
export default function IntegrationsPage() {
  return (
    <div className="min-h-screen bg-canvas">
      <header className="sticky top-0 z-header bg-surface border-b border-line">
        <div className="max-w-5xl mx-auto px-6 py-4 flex items-center gap-4">
          <Link href="/admin" className="text-ink-muted hover:text-ink" aria-label="Back to admin">
            <ArrowLeft className="w-5 h-5" />
          </Link>
          <div className="flex-1">
            <h1 className="text-xl font-black text-ink flex items-center gap-2">
              <KeyRound className="w-5 h-5 text-accent" /> Settings &amp; API keys
            </h1>
            <p className="text-xs text-ink-muted">
              Set up sign-in, email, SMS, delivery and storage. Keys are encrypted, never shown again after saving, and take effect within a minute.
            </p>
          </div>
        </div>
      </header>

      <main className="max-w-5xl mx-auto px-6 py-8">
        <IntegrationsClient />
      </main>
    </div>
  );
}
