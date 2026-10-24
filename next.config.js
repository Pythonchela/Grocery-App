/** @type {import('next').NextConfig} */

// The browser talks directly to the Laravel API, so its origin has to be
// allowed in connect-src. Without this, default-src 'self' silently blocks
// every client-side fetch (cart, checkout, admin, wishlist...).
const API_ORIGIN = (() => {
  try {
    return new URL(process.env.NEXT_PUBLIC_API_URL || 'http://127.0.0.1:8001/api/v1').origin;
  } catch {
    return 'http://127.0.0.1:8001';
  }
})();

const isDev = process.env.NODE_ENV !== 'production';

const csp = [
  "default-src 'self'",
  // Next.js needs inline for hydration payloads; eval is dev-only (HMR).
  // Razorpay's hosted checkout: its script, the payment frame, and the
  // telemetry/API hosts the widget calls. Google Sign-In (Google Identity
  // Services) needs its client script, its button/prompt frames, its styles and
  // its token requests, all under accounts.google.com/gsi/.
  `script-src 'self' 'unsafe-inline' https://checkout.razorpay.com https://accounts.google.com/gsi/client${isDev ? " 'unsafe-eval'" : ''}`,
  "frame-src https://api.razorpay.com https://checkout.razorpay.com https://accounts.google.com/gsi/",
  "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com https://accounts.google.com/gsi/style",
  "font-src 'self' data: https://fonts.gstatic.com",
  "img-src 'self' data: blob: https:",
  "media-src 'self' blob: https:",
  `connect-src 'self' ${API_ORIGIN} https://api.razorpay.com https://lumberjack.razorpay.com https://accounts.google.com/gsi/${isDev ? ' ws: wss:' : ''}`,
  "frame-ancestors 'none'",
  "base-uri 'self'",
  "form-action 'self'",
].join('; ');

const nextConfig = {
  images: {
    remotePatterns: [
      { protocol: 'https', hostname: 'images.unsplash.com' },
      { protocol: 'http', hostname: '127.0.0.1' },
      { protocol: 'http', hostname: 'localhost' },
    ],
  },
  async headers() {
    return [
      {
        source: '/(.*)',
        headers: [
          { key: 'X-Frame-Options', value: 'DENY' },
          { key: 'X-Content-Type-Options', value: 'nosniff' },
          { key: 'Referrer-Policy', value: 'strict-origin-when-cross-origin' },
          // camera/mic are needed by visual + voice search, geolocation by the
          // checkout address detector. Scoped to same-origin rather than off.
          { key: 'Permissions-Policy', value: 'camera=(self), microphone=(self), geolocation=(self)' },
          { key: 'Content-Security-Policy', value: csp },
        ],
      },
      {
        // The service worker must not be cached, or clients get stuck on an
        // old version and never pick up new precache manifests.
        source: '/sw.js',
        headers: [
          { key: 'Cache-Control', value: 'no-cache, no-store, must-revalidate' },
          { key: 'Service-Worker-Allowed', value: '/' },
        ],
      },
    ];
  },
};

module.exports = nextConfig;
