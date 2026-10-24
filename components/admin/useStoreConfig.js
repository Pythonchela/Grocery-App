'use client';

import { useEffect, useState } from 'react';
import { apiFetch } from '../../lib/apiClient';

/**
 * What kind of store this installation is (single business, vendors plus the
 * owner, vendors only), as the server states it. Null until it arrives, so a
 * screen can wait rather than flash the wrong menu.
 */
export function useStoreConfig() {
  const [config, setConfig] = useState(null);

  useEffect(() => {
    let cancelled = false;
    apiFetch('/config')
      .then((res) => { if (!cancelled) setConfig(res.data); })
      // If it cannot be read, behave as a marketplace: nothing is hidden by mistake.
      .catch(() => { if (!cancelled) setConfig({ mode: 'hybrid', vendors_enabled: true, shows_shops: true }); });
    return () => { cancelled = true; };
  }, []);

  return config;
}
