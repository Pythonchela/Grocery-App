'use client';

import React, { createContext, useContext } from 'react';

/**
 * The store logo an admin uploaded, or null while the shipped initials mark is in
 * use. Read on the server in the root layout and handed down here, so the first
 * paint already has it and the header does not flash the default mark.
 */
const BrandLogoContext = createContext(null);

export function BrandProvider({ logoUrl, children }) {
  return <BrandLogoContext.Provider value={logoUrl || null}>{children}</BrandLogoContext.Provider>;
}

export function useBrandLogo() {
  return useContext(BrandLogoContext);
}
