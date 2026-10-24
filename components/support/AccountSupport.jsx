'use client';

import React, { useEffect, useState } from 'react';
import { useStore } from '../providers/StoreProvider';
import SupportClient from './SupportClient';

/** Shopper help page. `?order=<id>` (from an order page) pre-fills the order. */
export default function AccountSupport() {
  const { authToken } = useStore();
  const [orderId, setOrderId] = useState(null);

  useEffect(() => {
    setOrderId(new URLSearchParams(window.location.search).get('order') || '');
  }, []);

  // Wait one tick for the query string so the form opens with the order already chosen.
  if (!authToken || orderId === null) return null;
  return <SupportClient token={authToken} orderId={orderId} />;
}
