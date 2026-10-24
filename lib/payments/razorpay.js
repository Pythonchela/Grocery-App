// Razorpay Checkout (web). Opens Razorpay's hosted payment window for an order
// the server already created, and resolves with the payment id + signature the
// server needs to verify. Nothing here is trusted: the server re-checks the
// signature and asks Razorpay whether the payment really captured.
//
// One of the handlers registered in ./index.js. It knows Razorpay's SDK and
// nothing about carts, coupons or refunds.

const SCRIPT_SRC = 'https://checkout.razorpay.com/v1/checkout.js';

let scriptPromise = null;

function loadScript() {
  if (typeof window === 'undefined') {
    return Promise.reject(new Error('Payment is only available in the browser.'));
  }
  if (window.Razorpay) return Promise.resolve();
  if (scriptPromise) return scriptPromise;

  scriptPromise = new Promise((resolve, reject) => {
    const el = document.createElement('script');
    el.src = SCRIPT_SRC;
    el.async = true;
    el.onload = () => resolve();
    el.onerror = () => {
      // Allow a retry after a dropped connection instead of caching the failure.
      scriptPromise = null;
      el.remove();
      reject(new Error('Could not load the payment window. Check your connection and try again.'));
    };
    document.body.appendChild(el);
  });
  return scriptPromise;
}

/**
 * @param {object} quote  the `data` from POST /payments/intent
 * @param {object} opts   { name, description, prefill: { name, contact, email }, themeColor }
 * @returns {Promise<{ payment_id: string, signature: string }>} the evidence the API expects
 */
export async function collectRazorpayPayment(quote, opts = {}) {
  await loadScript();

  return new Promise((resolve, reject) => {
    const rzp = new window.Razorpay({
      key: quote.client.key_id,
      order_id: quote.provider_intent_id,
      amount: quote.amount_paise,
      currency: 'INR',
      name: opts.name,
      description: opts.description,
      prefill: opts.prefill,
      theme: opts.themeColor ? { color: opts.themeColor } : undefined,
      // The quote and the order were priced for UPI, so only offer UPI —
      // otherwise the order would be recorded as UPI whatever was actually used.
      method: { upi: true, card: false, netbanking: false, wallet: false, emi: false, paylater: false },
      handler: (response) =>
        resolve({
          payment_id: response.razorpay_payment_id,
          signature: response.razorpay_signature,
        }),
      modal: {
        // Closing the window is a normal outcome, not an error worth a red banner.
        ondismiss: () => reject(Object.assign(new Error('Payment cancelled.'), { cancelled: true })),
      },
    });

    rzp.on('payment.failed', (response) => {
      reject(new Error(response?.error?.description || 'The payment failed. You have not been charged.'));
    });

    rzp.open();
  });
}
