'use client';

import React from 'react';
import { useParams } from 'next/navigation';
import { useAdminAuth } from '../../../../components/admin/AdminAuthContext';
import ProductEditor from '../../../../components/admin/ProductEditor';

// /admin/products/new adds a product; /admin/products/<id> edits one. The session gate is
// app/admin/layout.js, so by the time this renders there is a token.
export default function ProductEditorPage() {
  const { id } = useParams();
  const { token } = useAdminAuth();
  return <ProductEditor productId={id} token={token} />;
}
