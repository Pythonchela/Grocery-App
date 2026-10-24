'use client';

import React, { useState, useEffect } from 'react';
import {
  X,
  Trash2,
  Plus,
  Minus,
  MapPin,
  CheckCircle2,
  ShieldCheck,
  QrCode,
  Sparkles,
  ArrowRight,
  Smartphone,
  Lock,
  ShoppingBag,
  User,
  Mail,
  KeyRound,
  RefreshCw,
  Tag,
  Wallet,
  Truck,
  Gift,
  XCircle
} from 'lucide-react';
import confetti from 'canvas-confetti';
import { useStore } from './providers/StoreProvider';
import { cartShop } from '../lib/shopRules';
import { apiFetch, formatINR } from '../lib/apiClient';
import { brand } from '@ds/brand';
import { collectPayment } from '../lib/payments';
import { cartLineRequest } from '../lib/productOptions';
import { OptionPicks } from './storefront/OptionPicker';

export default function CheckoutDrawer({ isOpen, onClose, cartItems, onUpdateQty, onRemoveItem, onClearCart }) {
  const { authToken, login, register, storeConfig } = useStore();
  // Which shop the basket is from, when the store keeps a basket to one shop.
  const basketShop = storeConfig.one_shop_per_cart ? cartShop(cartItems) : null;
  const [step, setStep] = useState('cart'); // 'cart' | 'auth' | 'checkout' | 'success'
  const [paymentMethod, setPaymentMethod] = useState('gpay');
  const [isGpsLoading, setIsGpsLoading] = useState(false);
  const [isPaying, setIsPaying] = useState(false);
  const [address, setAddress] = useState({
    name: 'Abrar Patel',
    phone: '+91 98765 43210',
    street: 'Flat 402, Green Glen Layout, Bellandur',
    city: 'Bengaluru',
    state: 'Karnataka',
    pincode: '560103'
  });
  const [savedAddresses, setSavedAddresses] = useState([]);
  const [orderNumber, setOrderNumber] = useState(null);
  const [checkoutError, setCheckoutError] = useState('');

  // Coupon + wallet
  const [couponInput, setCouponInput] = useState('');
  const [appliedCoupon, setAppliedCoupon] = useState(null);
  const [couponError, setCouponError] = useState('');
  const [couponBusy, setCouponBusy] = useState(false);
  const [useWallet, setUseWallet] = useState(false);
  const [walletBalance, setWalletBalance] = useState(0);

  // Auth step state
  const [authMode, setAuthMode] = useState('login'); // 'login' | 'register'
  const [authName, setAuthName] = useState('');
  const [authEmail, setAuthEmail] = useState('');
  const [authPhone, setAuthPhone] = useState('');
  const [authPassword, setAuthPassword] = useState('');
  const [authError, setAuthError] = useState('');
  const [authLoading, setAuthLoading] = useState(false);

  // Server-issued quote. Until it arrives we show a local estimate, clearly
  // marked as one — the authoritative numbers (real carrier rate, correctly
  // scoped coupon) come from /payments/intent, which is also what checkout
  // will be held to. The old flat "₹99, free over ₹1999" guess was routinely
  // wrong: the server has always priced delivery from a live carrier quote.
  const [quote, setQuote] = useState(null);
  const [quoteError, setQuoteError] = useState('');
  const [quoting, setQuoting] = useState(false);

  // Delivery speed and loyalty redemption. Both have been accepted by the API
  // all along (`service_level`, `redeem_points`) with nothing on the storefront
  // sending them — so every order shipped standard and no one could spend the
  // points the store had been diligently awarding them.
  const [serviceLevel, setServiceLevel] = useState('STANDARD');
  const [deliveryOptions, setDeliveryOptions] = useState([]);
  // Why nothing is offered, in the server's words (hot food in the same basket as a courier parcel).
  const [deliveryMessage, setDeliveryMessage] = useState('');
  const [loyalty, setLoyalty] = useState(null);
  const [redeemPoints, setRedeemPoints] = useState(0);

  const localSubtotal = cartItems.reduce((acc, item) => acc + (item.price * item.quantity), 0);
  const hasUnavailable = cartItems.some(i => i.unavailable);

  const subtotal = quote?.breakdown.subtotal ?? localSubtotal;
  const discount = quote ? quote.breakdown.coupon_discount : (appliedCoupon?.discount || 0);
  const shipping = quote?.breakdown.shipping ?? null;
  const walletApplied = quote
    ? quote.breakdown.wallet_applicable
    : (useWallet ? Math.min(walletBalance, Math.max(0, localSubtotal - discount)) : 0);
  const grandTotal = quote
    ? quote.breakdown.total
    : Math.max(0, localSubtotal - discount - walletApplied);

  const cartPayload = () => cartItems.map(cartLineRequest);

  const addressComplete = Boolean(
    address.name && address.phone && address.street && address.city && address.state
    && /^[0-9]{6}$/.test(String(address.pincode || ''))
  );

  // Pull saved addresses + wallet balance once the user reaches checkout.
  useEffect(() => {
    if (step !== 'checkout' || !authToken) return;

    apiFetch('/addresses', { token: authToken }).then(res => {
      const list = res.data || [];
      setSavedAddresses(list);
      const preferred = list.find(a => a.is_default) || list[0];
      if (preferred) {
        setAddress({
          name: preferred.name,
          phone: preferred.phone,
          street: [preferred.line1, preferred.line2].filter(Boolean).join(', '),
          city: preferred.city,
          state: preferred.state,
          pincode: preferred.pincode,
        });
      }
    }).catch(() => {});

    apiFetch('/wallet', { token: authToken })
      .then(res => setWalletBalance(res.data.balance || 0))
      .catch(() => {});

    apiFetch('/loyalty', { token: authToken })
      .then(res => setLoyalty(res.data))
      .catch(() => {});
  }, [step, authToken]);

  // Delivery options for this destination. Rate-shopped server-side across
  // every enabled carrier; the storefront only picks from what comes back.
  useEffect(() => {
    if (step !== 'checkout' || !addressComplete || cartItems.length === 0) {
      setDeliveryOptions([]);
      setDeliveryMessage('');
      return;
    }

    let cancelled = false;

    apiFetch('/delivery/quote', {
      method: 'POST',
      token: authToken,
      body: {
        pincode: address.pincode,
        items: cartItems.map(i => ({ product_id: i.id, quantity: i.quantity })),
        order_value: localSubtotal,
      },
    })
      .then(res => {
        if (cancelled) return;
        const options = res.data?.options || [];
        setDeliveryOptions(options);
        setDeliveryMessage(res.data?.message || '');
        // Keep the current choice only if it's still offered here — a pincode
        // change can withdraw same-day entirely, and some items (hot food) have no
        // standard parcel at all. Fall back to what the server recommends: the
        // cheapest for ordinary goods, the fastest for quick-delivery items.
        if (options.length && !options.some(o => o.service_level === serviceLevel)) {
          setServiceLevel(res.data?.recommended_service_level || options[options.length - 1].service_level);
        }
      })
      .catch(() => { if (!cancelled) setDeliveryOptions([]); });

    return () => { cancelled = true; };
  }, [step, authToken, address.pincode, addressComplete, cartItems, localSubtotal]);

  // Ask the server to price the cart the moment it can — which needs a full
  // address, since delivery is rate-shopped against the destination pincode.
  // Re-runs whenever anything that moves the price changes, so the number on
  // the button is always one the server has committed to.
  useEffect(() => {
    if (step !== 'checkout' || !authToken || cartItems.length === 0 || !addressComplete) {
      setQuote(null);
      return;
    }

    let cancelled = false;
    setQuoting(true);
    setQuoteError('');

    // Quoting is a write — it opens a payment with the gateway — and it sits
    // behind the sensitive-write throttle. Settling briefly keeps a shopper
    // correcting their pincode from burning that budget on quotes they'll
    // never use.
    const timer = setTimeout(() => {
      apiFetch('/payments/intent', {
        method: 'POST',
        token: authToken,
        body: {
          items: cartPayload(),
          pincode: address.pincode,
          payment_method: 'UPI',
          coupon_code: appliedCoupon?.code || null,
          use_wallet: useWallet,
          service_level: serviceLevel,
          redeem_points: redeemPoints || 0,
        },
      })
        .then(res => { if (!cancelled) setQuote(res.data); })
        .catch(err => {
          if (cancelled) return;
          setQuote(null);
          setQuoteError(err.message || 'We could not price this order.');
        })
        .finally(() => { if (!cancelled) setQuoting(false); });
    }, 400);

    // A quote in flight is stale the moment any of these change; ignore it.
    return () => { cancelled = true; clearTimeout(timer); };
    // Every dependency here moves the price, and the intent's fingerprint
    // covers all of them — so a change to any one must re-quote or checkout
    // will reject the intent it's holding.
  }, [step, authToken, cartItems, address.pincode, addressComplete, appliedCoupon?.code, useWallet, serviceLevel, redeemPoints]);

  const applyCoupon = async () => {
    if (!couponInput.trim()) return;
    setCouponBusy(true);
    setCouponError('');
    try {
      const res = await apiFetch('/coupons/preview', {
        method: 'POST',
        token: authToken,
        body: { code: couponInput.trim(), items: cartPayload() },
      });
      setAppliedCoupon(res.data);
      setCouponInput('');
    } catch (err) {
      setCouponError(err.message);
      setAppliedCoupon(null);
    } finally {
      setCouponBusy(false);
    }
  };

  const handleDetectGps = () => {
    setIsGpsLoading(true);
    setTimeout(() => {
      setAddress(a => ({
        ...a,
        street: 'Auto-detected via GPS: HSR Layout Sector 1, near Metro Station',
        city: 'Bengaluru',
        state: 'Karnataka',
        pincode: '560102'
      }));
      setIsGpsLoading(false);
    }, 1000);
  };

  const handleProceedToCheckout = () => {
    setStep(authToken ? 'checkout' : 'auth');
  };

  const handleAuthSubmit = async (e) => {
    e.preventDefault();
    setAuthLoading(true);
    setAuthError('');
    try {
      if (authMode === 'login') {
        await login(authEmail, authPassword);
      } else {
        await register(authName, authEmail, authPhone, authPassword);
      }
      setStep('checkout');
    } catch (err) {
      setAuthError(err.message || 'Authentication failed');
    } finally {
      setAuthLoading(false);
    }
  };

  const handlePayNow = async () => {
    if (!quote) {
      setCheckoutError('Please wait for the order total to load.');
      return;
    }

    setIsPaying(true);
    setCheckoutError('');

    try {
      // With Razorpay configured the payment window runs here and returns the
      // payment id and signature it produced; the sandbox driver has nothing to
      // collect. Either way the server decides whether the payment is real,
      // and it will reject an intent whose amount or cart no longer matches.
      const paymentProof = await collectPayment(quote, {
        name: brand.name,
        description: `${cartItems.length} item${cartItems.length === 1 ? '' : 's'}`,
        prefill: { name: address.name, contact: address.phone },
      });

      const res = await apiFetch('/orders/checkout', {
        method: 'POST',
        token: authToken,
        body: {
          items: cartPayload(),
          shipping_address: {
            name: address.name,
            phone: address.phone,
            line1: address.street,
            city: address.city,
            state: address.state,
            pincode: address.pincode,
          },
          payment_method: 'UPI',
          payment_intent_id: quote.payment_intent_id,
          ...paymentProof,
          coupon_code: appliedCoupon?.code || null,
          use_wallet: useWallet,
          service_level: serviceLevel,
          redeem_points: redeemPoints || 0,
        },
      });

      setOrderNumber(res.data.order_number);
      setStep('success');
      try {
        confetti({ particleCount: 120, spread: 70, origin: { y: 0.6 } });
      } catch (e) { /* non-critical: ignore */ }
    } catch (error) {
      // Dismissing the payment window is the shopper's choice, not a failure.
      setCheckoutError(error.cancelled ? '' : (error.message || 'Failed to place order'));
    } finally {
      setIsPaying(false);
    }
  };

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 overflow-hidden bg-inverse/60 backdrop-blur-sm animate-fadeIn">
      <div className="absolute inset-y-0 right-0 max-w-full flex pl-10">
        <div className="w-screen max-w-md bg-surface text-ink shadow-panel flex flex-col justify-between border-l border-line">

          {/* Header */}
          <div className="p-5 border-b border-line flex items-center justify-between bg-surface-muted">
            <div className="flex items-center gap-2.5">
              <div className="w-9 h-9 rounded-control bg-accent text-ink-inverse flex items-center justify-center font-black text-sm shadow-subtle">
                {brand.logoInitials}
              </div>
              <h2 className="text-lg font-black text-ink">
                {step === 'cart' && 'Your Shopping Bag'}
                {step === 'auth' && 'Sign In to Continue'}
                {step === 'checkout' && '1-Click UPI Checkout'}
                {step === 'success' && 'Order Confirmed!'}
              </h2>
            </div>
            <button
              onClick={onClose}
              className="text-ink-subtle hover:text-ink p-2 rounded-pill hover:bg-surface-sunken transition"
            >
              <X className="w-5 h-5" />
            </button>
          </div>

          {/* Body Content */}
          <div className="flex-1 overflow-y-auto p-5 space-y-4">

            {/* STEP 1: CART LIST */}
            {step === 'cart' && (
              <>
                {cartItems.length === 0 ? (
                  <div className="py-16 text-center text-ink-subtle space-y-3">
                    <div className="w-16 h-16 rounded-pill bg-surface-sunken mx-auto flex items-center justify-center text-ink-subtle">
                      <ShoppingBag className="w-8 h-8" />
                    </div>
                    <p className="text-base font-bold text-ink-muted">Your bag is empty</p>
                    <p className="text-xs text-ink-subtle">Explore products or video reels to add items!</p>
                  </div>
                ) : (
                  <div className="space-y-3">
                    {basketShop?.name && (
                      <p className="text-xs font-bold text-ink-muted">
                        From <span className="text-ink">{basketShop.name}</span>
                      </p>
                    )}
                    {cartItems.map((item) => (
                      <div key={item.cartItemId} className="flex gap-4 p-4 border border-line rounded-card bg-surface shadow-subtle hover:shadow-card transition group">
                        <div className="w-20 h-20 bg-surface-sunken rounded-control overflow-hidden shrink-0">
                          <img src={item.image || item.images?.[0]} alt={item.title} className="w-full h-full object-cover group-hover:scale-105 transition" />
                        </div>
                        <div className="flex-1">
                          <h4 className="text-sm font-black text-ink leading-tight">{item.title}</h4>
                          {item.variantName && (
                            <p className="text-[10px] font-bold text-ink-subtle uppercase tracking-wide mt-0.5">
                              {item.variantName}
                            </p>
                          )}
                          <OptionPicks picks={item.optionPicks} className="mt-1" />
                          <p className="text-xs text-accent font-black mt-0.5">
                            ₹{item.price.toLocaleString('en-IN')}
                            {/* Shown rather than swapped silently — a number
                                that changes on its own reads as a trick. */}
                            {item.previousPrice != null && (
                              <span className="ml-1.5 text-[10px] font-bold text-ink-subtle line-through">
                                ₹{item.previousPrice.toLocaleString('en-IN')}
                              </span>
                            )}
                          </p>
                          {item.previousPrice != null && (
                            <p className="text-[10px] font-bold text-warning mt-0.5">
                              Price {item.previousPrice > item.price ? 'dropped' : 'changed'} since you added this
                            </p>
                          )}
                          {item.stockNotice && (
                            <p className={`text-[10px] font-bold mt-0.5 ${item.unavailable ? 'text-danger' : 'text-warning'}`}>
                              {item.stockNotice}
                            </p>
                          )}

                          <div className="flex items-center gap-2 mt-2">
                            <button
                              onClick={() => onUpdateQty(item.cartItemId, item.quantity - 1)}
                              className="w-6 h-6 rounded bg-surface-sunken hover:bg-surface-sunken flex items-center justify-center text-xs font-bold"
                            >
                              <Minus className="w-3 h-3" />
                            </button>
                            <span className="text-xs font-bold w-4 text-center">{item.quantity}</span>
                            <button
                              onClick={() => onUpdateQty(item.cartItemId, item.quantity + 1)}
                              className="w-6 h-6 rounded bg-surface-sunken hover:bg-surface-sunken flex items-center justify-center text-xs font-bold"
                            >
                              <Plus className="w-3 h-3" />
                            </button>
                          </div>
                        </div>

                        <button
                          onClick={() => onRemoveItem(item.cartItemId)}
                          className="text-ink-subtle hover:text-danger p-1"
                        >
                          <Trash2 className="w-4 h-4" />
                        </button>
                      </div>
                    ))}
                  </div>
                )}
              </>
            )}

            {/* STEP 2: AUTH (real Sanctum login/register against Laravel) */}
            {step === 'auth' && (
              <div className="space-y-5">
                <div className="flex bg-surface-sunken rounded-card p-1">
                  <button
                    onClick={() => { setAuthMode('login'); setAuthError(''); }}
                    className={`flex-1 py-2 rounded-control text-xs font-bold transition ${authMode === 'login' ? 'bg-surface shadow-subtle text-ink' : 'text-ink-subtle'}`}
                  >
                    Login
                  </button>
                  <button
                    onClick={() => { setAuthMode('register'); setAuthError(''); }}
                    className={`flex-1 py-2 rounded-control text-xs font-bold transition ${authMode === 'register' ? 'bg-surface shadow-subtle text-ink' : 'text-ink-subtle'}`}
                  >
                    Create Account
                  </button>
                </div>

                {authError && (
                  <div className="bg-danger-soft border border-danger text-danger p-3 rounded-card text-xs font-bold">
                    {authError}
                  </div>
                )}

                <form onSubmit={handleAuthSubmit} className="space-y-3">
                  {authMode === 'register' && (
                    <div className="relative">
                      <User className="absolute left-4 top-1/2 -translate-y-1/2 w-4 h-4 text-ink-subtle" />
                      <input type="text" required value={authName} onChange={e => setAuthName(e.target.value)}
                        placeholder="Full name"
                        className="w-full bg-surface-muted border border-line rounded-card pl-11 pr-4 py-3 text-sm font-semibold focus:outline-none focus:border-line-strong"
                      />
                    </div>
                  )}
                  <div className="relative">
                    <Mail className="absolute left-4 top-1/2 -translate-y-1/2 w-4 h-4 text-ink-subtle" />
                    <input type="email" required value={authEmail} onChange={e => setAuthEmail(e.target.value)}
                      placeholder="Email address"
                      className="w-full bg-surface-muted border border-line rounded-card pl-11 pr-4 py-3 text-sm font-semibold focus:outline-none focus:border-line-strong"
                    />
                  </div>
                  {authMode === 'register' && (
                    <div className="relative">
                      <Smartphone className="absolute left-4 top-1/2 -translate-y-1/2 w-4 h-4 text-ink-subtle" />
                      <input type="tel" value={authPhone} onChange={e => setAuthPhone(e.target.value)}
                        placeholder="Phone (optional)"
                        className="w-full bg-surface-muted border border-line rounded-card pl-11 pr-4 py-3 text-sm font-semibold focus:outline-none focus:border-line-strong"
                      />
                    </div>
                  )}
                  <div className="relative">
                    <KeyRound className="absolute left-4 top-1/2 -translate-y-1/2 w-4 h-4 text-ink-subtle" />
                    <input type="password" required minLength={8} value={authPassword} onChange={e => setAuthPassword(e.target.value)}
                      placeholder="Password"
                      className="w-full bg-surface-muted border border-line rounded-card pl-11 pr-4 py-3 text-sm font-semibold focus:outline-none focus:border-line-strong"
                    />
                  </div>
                  <button type="submit" disabled={authLoading}
                    className="btn-primary w-full justify-center text-sm py-3.5 disabled:opacity-50">
                    {authLoading ? <RefreshCw className="w-4 h-4 animate-spin" /> : <ArrowRight className="w-4 h-4" />}
                    {authLoading ? 'Please wait...' : (authMode === 'login' ? 'Sign In' : 'Create Account')}
                  </button>
                </form>
                {process.env.NODE_ENV !== 'production' && (
                  <p className="text-[11px] text-ink-subtle text-center">
                    Try: priya.sharma@example.com / Password@123
                  </p>
                )}
              </div>
            )}

            {/* STEP 3: CHECKOUT (GPS & UPI) */}
            {step === 'checkout' && (
              <div className="space-y-5">
                {checkoutError && (
                  <div className="bg-danger-soft border border-danger text-danger p-3 rounded-card text-xs font-bold">
                    {checkoutError}
                  </div>
                )}

                {/* GPS Address Auto-Detect */}
                <div className="bg-surface-muted p-4 rounded-card border border-line space-y-3 shadow-subtle">
                  <div className="flex items-center justify-between">
                    <span className="text-xs font-extrabold text-accent uppercase tracking-wider flex items-center gap-1">
                      <MapPin className="w-3.5 h-3.5" /> Delivery Address
                    </span>
                    <button
                      onClick={handleDetectGps}
                      disabled={isGpsLoading}
                      className="text-[11px] font-bold text-success hover:text-success bg-success-soft border border-success px-2.5 py-0.5 rounded-pill transition"
                    >
                      {isGpsLoading ? 'Locating GPS...' : '📍 Auto-detect GPS'}
                    </button>
                  </div>

                  {savedAddresses.length > 0 && (
                    <select
                      onChange={e => {
                        const a = savedAddresses.find(x => x.id === e.target.value);
                        if (a) setAddress({
                          name: a.name, phone: a.phone,
                          street: [a.line1, a.line2].filter(Boolean).join(', '),
                          city: a.city, state: a.state, pincode: a.pincode,
                        });
                      }}
                      className="w-full bg-surface border border-line rounded-control px-3 py-2 text-xs font-semibold focus:outline-none focus:border-line-strong"
                    >
                      {savedAddresses.map(a => (
                        <option key={a.id} value={a.id}>
                          {a.tag} — {a.line1}, {a.city} {a.is_default ? '(default)' : ''}
                        </option>
                      ))}
                    </select>
                  )}

                  <div className="text-xs text-ink-muted space-y-1">
                    <p className="font-bold text-ink">{address.name} ({address.phone})</p>
                    <p>{address.street}, {address.city}, {address.state} - {address.pincode}</p>
                  </div>

                  <div>
                    <label className="block text-[10px] font-bold text-ink-subtle uppercase mb-1" htmlFor="checkoutdrawer-f1">State</label>
                    <input id="checkoutdrawer-f1"
                      type="text"
                      value={address.state}
                      onChange={e => setAddress(a => ({ ...a, state: e.target.value }))}
                      className="w-full bg-surface border border-line rounded-control px-3 py-2 text-xs font-semibold focus:outline-none focus:border-line-strong"
                    />
                  </div>
                </div>

                {/* Coupon */}
                <div className="bg-surface-muted p-4 rounded-card border border-line space-y-3 shadow-subtle">
                  <span className="text-xs font-extrabold text-success uppercase tracking-wider flex items-center gap-1">
                    <Tag className="w-3.5 h-3.5" /> Apply Coupon
                  </span>

                  {appliedCoupon ? (
                    <div className="flex items-center justify-between gap-2 bg-success-soft border border-success rounded-control px-3 py-2.5">
                      <div className="min-w-0">
                        <p className="font-black text-success text-xs">{appliedCoupon.code}</p>
                        <p className="text-[11px] text-success font-medium truncate">
                          {appliedCoupon.description} · saves {formatINR(appliedCoupon.discount)}
                        </p>
                      </div>
                      <button onClick={() => { setAppliedCoupon(null); setCouponError(''); }}
                        className="text-success hover:text-danger shrink-0">
                        <XCircle className="w-4 h-4" />
                      </button>
                    </div>
                  ) : (
                    <>
                      <div className="flex gap-2">
                        <input
                          value={couponInput}
                          onChange={e => setCouponInput(e.target.value.toUpperCase())}
                          onKeyDown={e => { if (e.key === 'Enter') { e.preventDefault(); applyCoupon(); } }}
                          placeholder="Enter code e.g. BHARAT15"
                          className="flex-1 bg-surface border border-line rounded-control px-3 py-2 text-xs font-bold uppercase focus:outline-none focus:border-line-strong"
                        />
                        <button onClick={applyCoupon} disabled={couponBusy || !couponInput.trim()}
                          className="bg-inverse text-ink-inverse px-4 rounded-control text-xs font-bold disabled:opacity-40">
                          {couponBusy ? '...' : 'Apply'}
                        </button>
                      </div>
                      {couponError && <p className="text-[11px] font-bold text-danger">{couponError}</p>}
                    </>
                  )}
                </div>

                {deliveryOptions.length === 0 && deliveryMessage && (
                  <div className="bg-warning-soft border border-warning text-warning p-3 rounded-card text-xs font-bold">
                    {deliveryMessage}
                  </div>
                )}

                {/* Delivery speed — options come from the server's live
                    carrier rate-shop, never from a hardcoded list here. */}
                {deliveryOptions.length > 0 && (
                  <div className="bg-surface-muted p-4 rounded-card border border-line space-y-2 shadow-subtle">
                    <span className="text-xs font-extrabold text-accent uppercase tracking-wider flex items-center gap-1">
                      <Truck className="w-3.5 h-3.5" /> Delivery Speed
                    </span>
                    {deliveryOptions.map(option => (
                      <label
                        key={option.service_level}
                        className={`flex items-center justify-between gap-3 p-3 rounded-control border cursor-pointer transition ${
                          serviceLevel === option.service_level
                            ? 'border-accent bg-accent/5'
                            : 'border-line hover:border-line-strong'
                        }`}
                      >
                        <div className="flex items-center gap-2.5">
                          <input
                            type="radio"
                            name="service_level"
                            checked={serviceLevel === option.service_level}
                            onChange={() => setServiceLevel(option.service_level)}
                            className="w-4 h-4 accent-primary cursor-pointer"
                          />
                          <div>
                            <p className="text-xs font-extrabold text-ink">{option.label}</p>
                            <p className="text-[10px] text-ink-subtle font-medium">{option.description}</p>
                          </div>
                        </div>
                        <span className="text-xs font-black text-ink shrink-0">
                          {option.price === 0 ? 'FREE' : formatINR(option.price)}
                        </span>
                      </label>
                    ))}
                  </div>
                )}

                {/* Loyalty points */}
                {loyalty?.points > 0 && (
                  <div className="bg-surface-muted p-4 rounded-card border border-line space-y-2 shadow-subtle">
                    <div className="flex items-center justify-between gap-2">
                      <span className="text-xs font-extrabold text-accent uppercase tracking-wider flex items-center gap-1">
                        <Gift className="w-3.5 h-3.5" /> Loyalty Points
                      </span>
                      <span className="text-[11px] text-ink-subtle font-bold">
                        {loyalty.points.toLocaleString('en-IN')} available
                      </span>
                    </div>
                    <div className="flex gap-2">
                      <input
                        type="number"
                        min="0"
                        max={loyalty.points}
                        value={redeemPoints || ''}
                        placeholder="Points to redeem"
                        onChange={e => setRedeemPoints(
                          Math.max(0, Math.min(loyalty.points, parseInt(e.target.value, 10) || 0))
                        )}
                        className="flex-1 bg-surface border border-line rounded-control px-3 py-2 text-xs font-bold text-ink focus:outline-none focus:border-accent"
                      />
                      {redeemPoints > 0 && (
                        <button
                          onClick={() => setRedeemPoints(0)}
                          className="px-3 py-2 text-xs font-bold text-ink-muted hover:text-ink"
                        >
                          Clear
                        </button>
                      )}
                    </div>
                    <p className="text-[10px] text-ink-subtle font-medium">
                      {/* The server caps redemption at a percentage of the
                          order, so what's applied can be less than requested. */}
                      {quote && quote.breakdown.points_discount > 0
                        ? `Applying ${quote.breakdown.points_redeemable.toLocaleString('en-IN')} points · −${formatINR(quote.breakdown.points_discount)}`
                        : `Worth ₹${loyalty.redeem_value} each, up to ${loyalty.max_redeem_percent}% of the order.`}
                    </p>
                  </div>
                )}

                {/* Wallet */}
                {walletBalance > 0 && (
                  <label className="flex items-center justify-between gap-3 bg-surface-muted p-4 rounded-card border border-line cursor-pointer shadow-subtle">
                    <div className="flex items-center gap-2">
                      <Wallet className="w-4 h-4 text-accent" />
                      <div>
                        <p className="text-xs font-extrabold text-ink">Use {brand.walletName}</p>
                        <p className="text-[11px] text-ink-subtle font-medium">
                          Balance {formatINR(walletBalance)}
                          {useWallet && walletApplied > 0 && ` · applying ${formatINR(walletApplied)}`}
                        </p>
                      </div>
                    </div>
                    <input type="checkbox" checked={useWallet} onChange={e => setUseWallet(e.target.checked)}
                      className="w-5 h-5 accent-primary cursor-pointer" />
                  </label>
                )}

                {/* UPI Payment Options */}
                <div className="bg-surface-muted p-4 rounded-card border border-line space-y-3 shadow-subtle">
                  <span className="text-xs font-extrabold text-accent uppercase tracking-wider flex items-center gap-1">
                    <Smartphone className="w-3.5 h-3.5" /> Default Payment Method: Instant UPI
                  </span>

                  <div className="grid grid-cols-2 gap-2.5">
                    {[
                      { id: 'gpay', name: 'Google Pay', icon: '🔵' },
                      { id: 'phonepe', name: 'PhonePe', icon: '🟣' },
                      { id: 'paytm', name: 'Paytm UPI', icon: '🔷' },
                      { id: 'bhim', name: 'BHIM QR', icon: '🟠' }
                    ].map((m) => (
                      <button
                        key={m.id}
                        onClick={() => setPaymentMethod(m.id)}
                        className={`p-3 rounded-control border text-xs font-bold flex items-center gap-2 transition ${
                          paymentMethod === m.id
                            ? 'bg-accent text-ink-inverse border-accent shadow-card'
                            : 'bg-surface border-line text-ink-muted hover:border-line'
                        }`}
                      >
                        <span>{m.icon}</span>
                        <span>{m.name}</span>
                      </button>
                    ))}
                  </div>

                  {paymentMethod === 'bhim' && (
                    <div className="bg-surface p-4 rounded-control text-center space-y-2 border border-line shadow-inner">
                      <div className="w-28 h-28 bg-surface p-2 mx-auto rounded-control shadow-card flex items-center justify-center text-ink border">
                        <QrCode className="w-24 h-24 text-ink" />
                      </div>
                      <p className="text-[11px] text-ink-subtle font-medium">Scan using any UPI App to pay ₹{grandTotal.toLocaleString('en-IN')}</p>
                    </div>
                  )}
                </div>

                <div className="flex items-center gap-2 text-[11px] text-ink-muted bg-surface-sunken p-3 rounded-control border border-line font-medium">
                  <Lock className="w-4 h-4 text-success shrink-0" />
                  <span>256-Bit SSL Encrypted. No manual card entry required for Indian UPI flows.</span>
                </div>
              </div>
            )}

            {/* STEP 4: ORDER SUCCESS */}
            {step === 'success' && (
              <div className="py-8 text-center space-y-4">
                <div className="w-20 h-20 rounded-pill bg-success-soft text-success border border-success mx-auto flex items-center justify-center animate-bounce shadow-card">
                  <CheckCircle2 className="w-10 h-10" />
                </div>

                <div>
                  <h3 className="text-xl font-black text-ink">Payment Successful!</h3>
                  <p className="text-xs text-ink-subtle mt-1">Order Number: <span className="text-accent font-mono font-bold">{orderNumber}</span></p>
                </div>

                <div className="bg-surface-muted p-4 rounded-card text-left text-xs space-y-2 border border-line shadow-subtle">
                  <div className="flex justify-between border-b border-line pb-2">
                    <span className="text-ink-subtle">Logistics Partner</span>
                    <span className="font-bold text-success">Shiprocket Express</span>
                  </div>
                  <div className="flex justify-between border-b border-line pb-2">
                    <span className="text-ink-subtle">Estimated Delivery</span>
                    <span className="font-bold text-ink">Tomorrow, by 4:00 PM</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-ink-subtle">WhatsApp Updates</span>
                    <span className="font-bold text-accent">Sent to {address.phone}</span>
                  </div>
                </div>

                <button
                  onClick={() => {
                    onClearCart();
                    setStep('cart');
                    onClose();
                  }}
                  className="btn-primary w-full justify-center"
                >
                  Continue Shopping
                </button>
              </div>
            )}
          </div>

          {/* Footer Totals & Action Buttons */}
          {(step === 'cart' || step === 'checkout') && cartItems.length > 0 && (
            <div className="p-5 border-t border-line bg-surface-muted space-y-3">
              <div className="space-y-1.5 text-xs text-ink-muted font-medium">
                <div className="flex justify-between">
                  <span>Subtotal</span>
                  <span className="text-ink font-bold">{formatINR(subtotal)}</span>
                </div>
                {discount > 0 && (
                  <div className="flex justify-between">
                    <span>Coupon ({appliedCoupon.code})</span>
                    <span className="text-success font-bold">− {formatINR(discount)}</span>
                  </div>
                )}
                <div className="flex justify-between">
                  <span>Delivery Charge</span>
                  <span className="text-success font-bold">
                    {shipping === null
                      ? <span className="text-ink-muted font-medium">Enter pincode</span>
                      : shipping === 0 ? 'FREE' : formatINR(shipping)}
                  </span>
                </div>
                {quote?.breakdown.service_level && (
                  <div className="flex justify-between">
                    <span>Delivery</span>
                    <span className="text-ink font-bold">
                      {quote.breakdown.service_level.replace(/_/g, ' ').toLowerCase()}
                    </span>
                  </div>
                )}
                {quote?.breakdown.points_discount > 0 && (
                  <div className="flex justify-between">
                    <span>Points ({quote.breakdown.points_redeemable.toLocaleString('en-IN')})</span>
                    <span className="text-success font-bold">− {formatINR(quote.breakdown.points_discount)}</span>
                  </div>
                )}
                {walletApplied > 0 && (
                  <div className="flex justify-between">
                    <span>Wallet applied</span>
                    <span className="text-success font-bold">− {formatINR(walletApplied)}</span>
                  </div>
                )}
                <div className="flex justify-between text-sm font-black text-ink pt-2 border-t border-line">
                  <span>Total Payable</span>
                  <span className="text-accent text-lg">{formatINR(grandTotal)}</span>
                </div>
                {step === 'checkout' && !quote && !quoteError && (
                  <p className="text-[10px] text-ink-muted font-medium pt-1">
                    {quoting
                      ? 'Confirming your final total…'
                      : 'Enter your delivery address to see the final total.'}
                  </p>
                )}
                {quoteError && (
                  <p className="text-[10px] text-danger font-semibold pt-1">{quoteError}</p>
                )}
              </div>

              {step === 'cart' ? (
                <button
                  onClick={handleProceedToCheckout}
                  // An item that sold out while the cart sat in localStorage
                  // would be rejected by checkout anyway; saying so here beats
                  // a 422 after they've filled in an address.
                  disabled={hasUnavailable}
                  className="btn-primary w-full justify-center text-sm py-3.5 shadow-card disabled:opacity-50"
                >
                  <span>{hasUnavailable ? 'Remove unavailable items to continue' : 'Proceed to 1-Click Checkout'}</span>
                  {!hasUnavailable && <ArrowRight className="w-4 h-4" />}
                </button>
              ) : (
                <button
                  onClick={handlePayNow}
                  // Disabled until the server has quoted: paying against a
                  // total we invented locally is exactly what this flow exists
                  // to stop.
                  disabled={isPaying || !quote}
                  className="btn-primary w-full justify-center text-sm py-3.5 bg-gradient-to-r from-success via-success to-accent hover:from-success hover:to-accent shadow-card disabled:opacity-50"
                >
                  <Sparkles className="w-4 h-4" />
                  <span>
                    {isPaying
                      ? 'Processing...'
                      : quote
                        ? `Pay ${formatINR(grandTotal)} via UPI`
                        : quoting ? 'Calculating total…' : 'Complete your address'}
                  </span>
                </button>
              )}
            </div>
          )}

        </div>
      </div>
    </div>
  );
}
