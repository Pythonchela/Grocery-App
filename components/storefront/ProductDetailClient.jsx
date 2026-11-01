'use client';

import React, { useEffect, useState } from 'react';
import { Button } from '@ds/ui';
import Link from 'next/link';
import { useStore } from '../providers/StoreProvider';
import ProductReviews from '../reviews/ProductReviews';
import ProductQnA from './ProductQnA';
import ProductDetailsTabs from './ProductDetailsTabs';
import ProductDeliveryCard from './ProductDeliveryCard';
import BundleOffer from './BundleOffer';
import Product360Viewer from './Product360Viewer';
import RelatedProducts from './RelatedProducts';
import ProductZoomLens from './ProductZoomLens';
import HotspotDetailModal from './HotspotDetailModal';
import { apiFetch } from '../../lib/apiClient';
import { OptionPicker, VariantPicker } from './OptionPicker';
import { optionUnitPrice, selectionDefaults, selectionProblem } from '../../lib/productOptions';
import { assurances, galleryImages, openingVariant, ratingWord } from '../../lib/productPage';
import { brand } from '@ds/brand';
import { LEGAL } from '../../lib/legal';
import {
  Star,
  ShoppingBag,
  Award,
  Leaf,
  Cpu,
  Zap,
  Sparkles,
  ArrowLeft,
  ShieldCheck,
  CheckCircle2,
  Heart,
  RotateCcw,
  Camera,
  CheckCircle,
  Banknote,
  CreditCard,
  Share2,
} from 'lucide-react';

const ASSURANCE_ICONS = { return: RotateCcw, cash: Banknote, card: CreditCard, bolt: Zap };

export default function ProductDetailClient({ product }) {
  const { handleAddToCart, authToken } = useStore();
  // Opens on a colour/size that is in stock, and shows that colour's own pictures.
  const [selectedVariant, setSelectedVariant] = useState(() => openingVariant(product.variants));
  const images = galleryImages(product, selectedVariant);
  const [pickedImage, setPickedImage] = useState(null);
  const selectedImage = images.includes(pickedImage) ? pickedImage : images[0];
  const [wishlistItemId, setWishlistItemId] = useState(null);
  const [wishlistBusy, setWishlistBusy] = useState(false);
  const [shareNote, setShareNote] = useState('');
  const wishlisted = Boolean(wishlistItemId);
  const [viewMode, setViewMode] = useState('photos'); // 'photos' | 'spin'
  const [activeHotspot, setActiveHotspot] = useState(null);

  // Custom options (portion, add-ons, weight...) and the price they come to.
  const groups = product.optionGroups || [];
  const [selection, setSelection] = useState(() => selectionDefaults(groups));
  const basePrice = selectedVariant?.price ?? product.price;
  const unitPrice = optionUnitPrice(basePrice, groups, selection);
  const unitMrp = unitPrice === basePrice || basePrice <= 0
    ? product.mrp
    : Math.max(unitPrice, product.mrp * (unitPrice / basePrice));
  const optionProblem = selectionProblem(groups, selection);
  const addToCart = () => {
    if (optionProblem) return false;
    handleAddToCart(product, selectedVariant, groups.length ? selection : null);
    return true;
  };
  const outOfStock = selectedVariant ? selectedVariant.stock === 0 : product.inStock === false;

  const hasSpin = product.spinImages?.length > 0;
  const hasHotspots = product.hotspots?.length > 0;
  // Hotspots are authored against the main image only (that's what the admin
  // canvas places them on), so only overlay them while it's the one showing.
  const showHotspotsOnCurrentImage = hasHotspots && selectedImage === product.images[0];

  // Whether this product is already saved, so the heart can show it and undo it.
  useEffect(() => {
    if (!authToken) { setWishlistItemId(null); return; }
    let cancelled = false;
    apiFetch('/wishlists', { token: authToken })
      .then((res) => {
        if (cancelled) return;
        const item = (res.data || []).flatMap((w) => w.items || []).find((i) => i.product_id === product.id);
        setWishlistItemId(item?.id || null);
      })
      .catch(() => { /* the heart just starts empty */ });
    return () => { cancelled = true; };
  }, [authToken, product.id]);

  const toggleWishlist = async () => {
    if (!authToken) { window.location.href = '/account/wishlist'; return; }
    setWishlistBusy(true);
    try {
      if (wishlistItemId) {
        await apiFetch(`/wishlist-items/${wishlistItemId}`, { method: 'DELETE', token: authToken });
        setWishlistItemId(null);
      } else {
        const res = await apiFetch('/wishlist-items', {
          method: 'POST',
          token: authToken,
          body: { product_id: product.id, variant_id: selectedVariant?.id || null },
        });
        setWishlistItemId(res.data?.id || null);
      }
    } finally {
      setWishlistBusy(false);
    }
  };

  const share = async () => {
    const url = window.location.href;
    try {
      if (navigator.share) {
        await navigator.share({ title: product.title, url });
        return;
      }
      await navigator.clipboard.writeText(url);
      setShareNote('Link copied');
    } catch {
      setShareNote('');
    }
    setTimeout(() => setShareNote(''), 2000);
  };

  const renderBadgeIcon = (badgeName) => {
    if (badgeName.includes('Heritage') || badgeName.includes('GI')) return <Award className="w-4 h-4 text-warning" />;
    if (badgeName.includes('Organic') || badgeName.includes('Ayush') || badgeName.includes('Paraben')) return <Leaf className="w-4 h-4 text-success" />;
    if (badgeName.includes('ANC') || badgeName.includes('Battery') || badgeName.includes('Voice')) return <Cpu className="w-4 h-4 text-accent" />;
    if (badgeName.includes('Rebound') || badgeName.includes('Ortho') || badgeName.includes('Marathon')) return <Zap className="w-4 h-4 text-accent" />;
    return <Sparkles className="w-4 h-4 text-danger" />;
  };

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 pb-28 md:pb-8">
      {/* Breadcrumbs */}
      <div className="flex items-center gap-2 text-xs font-semibold text-ink-subtle mb-6">
        <Link href="/" className="hover:text-ink transition flex items-center gap-1">
          <ArrowLeft className="w-3.5 h-3.5" /> Back to Store
        </Link>
        <span>/</span>
        <span className="capitalize">{product.category?.name || 'Category'}</span>
        <span>/</span>
        <span className="text-ink truncate max-w-[200px]">{product.title}</span>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-12">
        {/* Left: Image Gallery */}
        <div className="space-y-4">
          {hasSpin && (
            <div className="flex items-center gap-1 bg-surface-sunken rounded-pill p-1 w-fit">
              <button
                onClick={() => setViewMode('photos')}
                className={`flex items-center gap-1.5 px-3.5 py-1.5 rounded-pill text-xs font-bold transition ${
                  viewMode === 'photos' ? 'bg-surface shadow-subtle text-ink' : 'text-ink-subtle'
                }`}
              >
                <Camera className="w-3.5 h-3.5" /> Photos
              </button>
              <button
                onClick={() => setViewMode('spin')}
                className={`flex items-center gap-1.5 px-3.5 py-1.5 rounded-pill text-xs font-bold transition ${
                  viewMode === 'spin' ? 'bg-surface shadow-subtle text-ink' : 'text-ink-subtle'
                }`}
              >
                <RotateCcw className="w-3.5 h-3.5" /> 360°
              </button>
            </div>
          )}

          {viewMode === 'spin' && hasSpin ? (
            <Product360Viewer images={product.spinImages} alt={product.title} />
          ) : (
            <ProductZoomLens src={selectedImage} alt={product.title} className="aspect-square bg-canvas rounded-panel overflow-hidden border border-line group">
              <img
                src={selectedImage || 'https://via.placeholder.com/800'}
                alt={product.title}
                className="w-full h-full object-cover group-hover:scale-105 transition duration-500"
              />
              {product.isNew && (
                <span className="absolute top-4 left-4 z-10 bg-success text-ink-inverse text-[10px] font-black px-3 py-1 rounded-pill uppercase tracking-wider shadow-card">
                  NEW ARRIVAL
                </span>
              )}

              {/* Interactive hotspot pins — clicking one opens a macro
                  close-up with detail + tech specs. Previously configured in
                  the admin but never rendered anywhere on the storefront. */}
              {showHotspotsOnCurrentImage && product.hotspots.map((hs) => (
                <button
                  key={hs.id}
                  type="button"
                  onClick={(e) => { e.stopPropagation(); setActiveHotspot(hs); }}
                  style={{ top: hs.top, left: hs.left }}
                  title={hs.title}
                  className="absolute z-20 -translate-x-1/2 -translate-y-1/2 w-8 h-8 rounded-pill bg-surface/90 border-2 border-accent text-accent flex items-center justify-center shadow-card hover:scale-110 hover:bg-accent hover:text-ink-inverse transition-all before:absolute before:inset-0 before:rounded-pill before:border-2 before:border-accent before:animate-ping before:opacity-60"
                >
                  <span className="relative text-xs font-black">+</span>
                </button>
              ))}
            </ProductZoomLens>
          )}

          {images.length > 1 && viewMode === 'photos' && (
            <div className="flex gap-4 overflow-x-auto pb-2 scrollbar-hide">
              {images.map((img, idx) => (
                <button
                  key={idx}
                  onClick={() => setPickedImage(img)}
                  className={`w-20 h-20 shrink-0 rounded-card overflow-hidden border-2 transition ${selectedImage === img ? 'border-ink' : 'border-transparent opacity-60 hover:opacity-100'}`}
                >
                  <img src={img} alt={`Thumbnail ${idx}`} className="w-full h-full object-cover bg-canvas" />
                </button>
              ))}
            </div>
          )}

          {showHotspotsOnCurrentImage && (
            <p className="text-[11px] text-ink-subtle font-medium flex items-center gap-1.5">
              <Zap className="w-3.5 h-3.5 text-accent" /> Tap the <span className="font-black text-accent">+</span> markers on the photo for close-up details
            </p>
          )}
        </div>

        <HotspotDetailModal hotspot={activeHotspot} onClose={() => setActiveHotspot(null)} />

        {/* Right: Product Info */}
        <div className="space-y-6">
          
          <div className="space-y-3">
            {/* Badges */}
            <div className="flex items-center gap-2 flex-wrap">
              {product.lifestyleBadges.map((badge, i) => (
                <span key={i} className="text-[11px] font-extrabold text-ink bg-surface-sunken border border-line px-2.5 py-1 rounded-pill flex items-center gap-1.5">
                  {renderBadgeIcon(badge)}
                  <span>{badge}</span>
                </span>
              ))}
            </div>

            <h1 className="text-3xl font-black text-ink leading-tight">
              {product.title}
            </h1>

            {/* Ratings */}
            {product.rating > 0 && (
              <div className="flex items-center gap-3 flex-wrap">
                <div className="flex items-center gap-1 bg-warning-soft border border-warning px-2 py-1 rounded-control">
                  <Star className="w-4 h-4 fill-rating text-warning" />
                  <span className="text-xs font-black text-warning">{Number(product.rating).toFixed(1)}</span>
                </div>
                <span className="text-xs font-bold text-success bg-success-soft rounded-pill px-2.5 py-1">
                  {ratingWord(product.rating)}
                </span>
                <a
                  href="#reviews"
                  className="text-sm font-semibold text-ink-subtle underline decoration-line-strong underline-offset-4 hover:text-ink"
                >
                  {product.reviewsCount} {product.reviewsCount === 1 ? 'rating' : 'ratings'} by verified buyers
                </a>
              </div>
            )}
          </div>

          {/* Pricing */}
          <div className="pt-4 border-t border-line">
            <div className="flex items-end gap-3 mb-1">
              <span className="text-4xl font-bold text-ink">₹{unitPrice.toLocaleString('en-IN')}</span>
              {unitMrp > unitPrice && (
                <span className="text-lg text-ink-subtle line-through font-medium mb-1">MRP ₹{Math.round(unitMrp).toLocaleString('en-IN')}</span>
              )}
              {product.discount > 0 && (
                <span className="bg-danger text-ink-inverse text-xs font-black px-2 py-1 rounded-control mb-1.5">
                  {product.discount}% OFF
                </span>
              )}
            </div>
            <p className="text-xs font-medium text-success flex items-center gap-1 mt-2">
              <CheckCircle2 className="w-4 h-4" /> Inclusive of all taxes
            </p>
            <ul className="flex flex-wrap gap-2 mt-4">
              {assurances(product, LEGAL.returnDays).map((a) => {
                const Icon = ASSURANCE_ICONS[a.icon] || ShieldCheck;
                return (
                  <li key={a.label} className="inline-flex items-center gap-2 border border-line rounded-card px-3 py-2 text-sm font-semibold text-ink">
                    <Icon className="w-[18px] h-[18px] text-accent" /> {a.label}
                  </li>
                );
              })}
            </ul>
          </div>

          {/* Variants: colour swatches and size chips, or a plain list */}
          {product.variants?.length > 1 && (
            <div className="pt-4">
              <VariantPicker variants={product.variants} selected={selectedVariant} onChange={setSelectedVariant} />
            </div>
          )}
          {selectedVariant?.stock <= 5 && selectedVariant?.stock > 0 && (
            <p className="text-xs font-bold text-danger">Only {selectedVariant.stock} left in stock!</p>
          )}
          {outOfStock && (
            <p className="text-xs font-bold text-danger">Out of Stock</p>
          )}

          {/* Custom options set up for this product's category */}
          <OptionPicker groups={groups} selection={selection} onChange={setSelection} />

          {/* Actions (on a phone these sit in the bar at the bottom of the screen) */}
          <div className="hidden md:grid grid-cols-2 gap-4 pt-2">
            <Button
              size="lg"
              onClick={addToCart}
              disabled={outOfStock || Boolean(optionProblem)}
              className="shadow-hover"
              leadingIcon={<ShoppingBag className="w-5 h-5" />}
            >
              {outOfStock ? 'Out of Stock' : 'Add to Cart'}
            </Button>

            <Button
              variant="highlight"
              size="lg"
              onClick={addToCart}
              disabled={outOfStock || Boolean(optionProblem)}
              className="shadow-hover"
              leadingIcon={<Zap className="w-5 h-5 fill-current" />}
            >
              Buy at ₹{unitPrice.toLocaleString('en-IN')}
            </Button>
          </div>

          {optionProblem && (
            <p className="text-xs font-semibold text-warning -mt-2">{optionProblem} to continue.</p>
          )}

          <div className="flex gap-3">
            <button
              onClick={toggleWishlist}
              disabled={wishlistBusy}
              aria-pressed={wishlisted}
              className={`flex-1 flex items-center justify-center gap-2 py-3 rounded-pill text-sm font-bold border-2 transition disabled:opacity-50 ${
                wishlisted
                  ? 'bg-danger-soft border-danger text-danger'
                  : 'bg-surface border-line text-ink-muted hover:border-line-strong'
              }`}
            >
              <Heart className={`w-4 h-4 ${wishlisted ? 'fill-danger text-danger' : ''}`} />
              {wishlisted ? 'Saved to Wishlist' : 'Add to Wishlist'}
            </button>
            <button
              onClick={share}
              className="flex items-center justify-center gap-2 px-5 py-3 rounded-pill text-sm font-bold border-2 border-line bg-surface text-ink-muted hover:border-line-strong transition"
            >
              <Share2 className="w-4 h-4" /> {shareNote || 'Share'}
            </button>
          </div>

          {/* Where it goes and when it arrives, from the same quote the cart uses */}
          <ProductDeliveryCard product={product} price={unitPrice} />

          {/* Live "buy together" deals featuring this product */}
          <BundleOffer product={product} addCurrent={addToCart} />

          {/* Key Features */}
          {product.features?.length > 0 && (
            <div className="pt-6 border-t border-line">
              <h3 className="text-lg font-black text-ink mb-3">Key Features</h3>
              <ul className="grid grid-cols-1 sm:grid-cols-2 gap-x-4 gap-y-2.5">
                {product.features.map((feat, i) => (
                  <li key={i} className="flex items-start gap-2 text-sm text-ink-muted font-medium">
                    <CheckCircle className="w-4 h-4 text-success shrink-0 mt-0.5" />
                    <span>{feat}</span>
                  </li>
                ))}
              </ul>
            </div>
          )}

          {/* All details: specifications, description, manufacturer info */}
          <ProductDetailsTabs product={product} />

          {/* Trust Banner Inline */}
          <div className="bg-pastel-blue p-4 rounded-control border border-accent flex items-start gap-3 mt-4">
            <ShieldCheck className="w-6 h-6 text-accent shrink-0" />
            <div>
              <h4 className="text-xs font-black text-ink">100% Authentic Product</h4>
              <p className="text-[11px] text-ink-muted mt-0.5">Verified by {brand.nameDisplay} Quality Check. Eligible for 7-day hassle-free returns.</p>
            </div>
          </div>

        </div>
      </div>

      <div id="reviews" className="mt-16 pt-10 border-t border-line scroll-mt-24">
        <ProductReviews productId={product.id} />
      </div>

      <div className="pt-4">
        <ProductQnA productId={product.id} />
      </div>

      <div className="mt-16 pt-10 border-t border-line">
        <RelatedProducts productId={product.id} />
      </div>

      {/* Phone: the buy buttons stay at the bottom of the screen, as in the app */}
      <div className="md:hidden fixed inset-x-0 bottom-0 z-30 bg-surface border-t border-line px-4 py-3 flex gap-3 shadow-card">
        <Button
          size="lg"
          variant="secondary"
          onClick={addToCart}
          disabled={outOfStock || Boolean(optionProblem)}
          className="flex-1"
        >
          {outOfStock ? 'Out of stock' : 'Add to cart'}
        </Button>
        <Button
          variant="highlight"
          size="lg"
          onClick={addToCart}
          disabled={outOfStock || Boolean(optionProblem)}
          className="flex-1"
        >
          Buy at ₹{unitPrice.toLocaleString('en-IN')}
        </Button>
      </div>
    </div>
  );
}
