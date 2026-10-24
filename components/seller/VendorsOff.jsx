import React from 'react';
import Link from 'next/link';

/**
 * What /sell and /seller show when this store sells only its own goods. The links
 * to them are already hidden; this covers someone who types the address.
 */
export default function VendorsOff() {
  return (
    <main className="mx-auto max-w-md space-y-4 px-4 py-20 text-center">
      <h1 className="text-xl font-black text-ink">This store does not take outside sellers</h1>
      <p className="text-sm text-ink-muted">Everything here is sold by the store itself.</p>
      <Link href="/" className="inline-block rounded-control bg-accent px-4 py-2 text-sm font-bold text-on-accent">Back to the shop</Link>
    </main>
  );
}
