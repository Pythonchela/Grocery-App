'use client';

import React, { useState, useEffect } from 'react';
import { useStore } from '../providers/StoreProvider';
import { apiFetch, mapProduct } from '../../lib/apiClient';
import { Star, Sparkles, TrendingUp, Flame, Gift } from 'lucide-react';

import HeroBanner from './home/HeroBanner';
import CategoryGrid from './home/CategoryGrid';
import ProductRow from './home/ProductRow';
import ShoppertainmentPromo from './home/ShoppertainmentPromo';
import TrustBanner from './home/TrustBanner';
import FloatingCompareBar from './home/FloatingCompareBar';

import ProductComparisonModal from '../ProductComparisonModal';
import AIAgentCopilot from '../AIAgentCopilot';
import VerifiedReviewModal from '../VerifiedReviewModal';

/**
 * What each admin-chosen product-row source shows. Mirrors the mobile app so a
 * layout built once reads the same on both.
 */
function productsForSource(section, { products, recommended, newArrivals, bestSellers }) {
  switch (section.source) {
    case 'new':
      return newArrivals;
    case 'personalized':
      return recommended;
    case 'deals':
      return products.filter(p => (p.discount || 0) > 0)
        .sort((a, b) => (b.discount || 0) - (a.discount || 0)).slice(0, 10);
    case 'category':
      return products.filter(p => p.categoryId === section.category_id).slice(0, 10);
    default:
      return bestSellers;
  }
}

const SOURCE_TITLES = {
  trending: 'Trending Now',
  new: 'New Arrivals',
  personalized: 'Picked For You',
  deals: 'Deals',
  category: 'Shop Now',
};

export default function HomeClient({ categories, products, hasReels = false, heroBannerSlides, sections = [] }) {
  const { handleAddToCart, setIsVoiceOpen, authToken } = useStore();
  const [reviewProduct, setReviewProduct] = useState(null);
  const [activeCategory, setActiveCategory] = useState('all');
  const [showFloatingPromo, setShowFloatingPromo] = useState(false); // disabled

  /**
   * The real recommendation engine — collaborative filtering for a signed-in
   * shopper with order/view history, order+view velocity trending for
   * everyone else. `null` means "still on the naive fallback below"; the row
   * always has something to show, it just upgrades once the real answer
   * arrives rather than the section ever sitting empty.
   */
  const [engineRecommended, setEngineRecommended] = useState(null);

  useEffect(() => {
    let cancelled = false;
    const path = authToken ? '/recommendations/personalized' : '/recommendations/trending';

    apiFetch(path, { token: authToken || undefined })
      .then(res => {
        if (cancelled) return;
        const mapped = (res.data || []).map(mapProduct);
        // A cold-start account or empty catalog still has to fall back rather
        // than blank the row — the naive slice below is exactly that fallback.
        if (mapped.length > 0) setEngineRecommended(mapped);
      })
      .catch(() => { /* naive fallback below covers this */ });

    return () => { cancelled = true; };
  }, [authToken]);

  // Comparison State
  const [compareList, setCompareList] = useState([]);
  const [isCompareModalOpen, setIsCompareModalOpen] = useState(false);

  const handleToggleCompare = (product) => {
    setCompareList((prev) => {
      const exists = prev.find((p) => p.id === product.id);
      if (exists) return prev.filter((p) => p.id !== product.id);
      if (prev.length >= 3) { alert('You can compare up to 3 products at a time!'); return prev; }
      return [...prev, product];
    });
  };

  // Filter products by active category
  const categoryProducts = activeCategory === 'all'
    ? products
    : products.filter(p => p.categoryId === activeCategory || p.category?.slug === activeCategory);

  // Derive product sections. "Recommended for You" prefers the real
  // engine result — collaborative filtering / trending, not an arbitrary
  // slice — but only on the unfiltered "all" tab, since the engine doesn't
  // take a category and mixing a fixed top-8 list with a category filter the
  // shopper just picked would be misleading either way.
  const recommended = (activeCategory === 'all' && engineRecommended)
    ? engineRecommended
    : categoryProducts.slice(0, 10);
  const newArrivals  = categoryProducts.filter(p => p.isNew).slice(0, 10);
  const bestSellers  = [...categoryProducts].sort((a, b) => (b.rating || 0) - (a.rating || 0)).slice(0, 10);

  const sharedRowProps = {
    onAddToCart: handleAddToCart,
    onToggleCompare: handleToggleCompare,
    compareList,
  };

  /**
   * One block of the admin's layout. Unknown types render nothing, so a section
   * type added later cannot break an older deployment of the storefront.
   */
  const renderSection = (section) => {
    switch (section.type) {
      case 'HERO':
        return (
          <HeroBanner
            key={section.id}
            slides={[{
              id: section.id,
              title: section.title,
              subtitle: section.subtitle,
              cta_text: 'Shop now',
              cta_url: section.link_url || '/search',
              bg_image: section.image_url || undefined,
            }]}
          />
        );
      case 'BANNER':
        return (
          <a
            key={section.id}
            href={section.link_url || '#'}
            className="relative block rounded-panel overflow-hidden bg-inverse text-white min-h-[160px]"
          >
            {section.image_url && (
              <img src={section.image_url} alt="" className="absolute inset-0 w-full h-full object-cover opacity-70" />
            )}
            <div className="relative z-10 flex flex-col justify-end h-full min-h-[160px] p-6 bg-gradient-to-t from-black/60 to-transparent">
              <h2 className="text-2xl font-black">{section.title}</h2>
              {section.subtitle && <p className="text-white/80 text-sm font-medium">{section.subtitle}</p>}
            </div>
          </a>
        );
      case 'CATEGORY_GRID':
        return <CategoryGrid key={section.id} categories={categories} />;
      case 'PRODUCT_ROW': {
        const rowProducts = productsForSource(section, { products: categoryProducts, recommended, newArrivals, bestSellers });
        return (
          <ProductRow
            key={section.id}
            title={section.title || SOURCE_TITLES[section.source] || 'Shop Now'}
            icon={<Sparkles className="w-4 h-4" />}
            accentColor="text-accent"
            products={rowProducts}
            viewAllHref="/search"
            {...sharedRowProps}
          />
        );
      }
      case 'REELS':
        return hasReels ? <ShoppertainmentPromo key={section.id} /> : null;
      case 'TRUST':
        return (
          <TrustBanner
            key={section.id}
            onOpenReviewModal={(p) => setReviewProduct(p)}
            sampleProduct={products[0]}
          />
        );
      default:
        return null;
    }
  };

  const hasLayout = sections.length > 0;

  return (
    <div className="max-w-7xl w-full mx-auto px-4 sm:px-6 lg:px-8 py-6 space-y-10">


      {hasLayout ? (<>
        {sections.map((section) => (
          <React.Fragment key={section.id}>
            {renderSection(section)}
          </React.Fragment>
        ))}
      </>) : (<>

      {/* 1. PROMOTIONAL HERO BANNER CAROUSEL */}
      <HeroBanner slides={heroBannerSlides} />

      {/* 2. SHOP BY CATEGORY GRID */}
      <CategoryGrid categories={categories} />

      {/* 3. RECOMMENDED FOR YOU */}
      <ProductRow
        title="Recommended for You"
        icon={<Sparkles className="w-4 h-4" />}
        accentColor="text-warning"
        products={recommended}
        viewAllHref="/search"
        {...sharedRowProps}
      />

      {/* 4. NEW ARRIVALS */}
      {newArrivals.length > 0 && (
        <ProductRow
          title="New Arrivals"
          icon={<Gift className="w-4 h-4" />}
          accentColor="text-accent"
          products={newArrivals}
          viewAllHref="/search?sort=newest"
          {...sharedRowProps}
        />
      )}

      {/* 5. SHOPPERTAINMENT VIDEO FEED — only when reels exist */}
      {hasReels && <ShoppertainmentPromo />}

      {/* 6. BEST SELLERS */}
      <ProductRow
        title="Best Sellers"
        icon={<Flame className="w-4 h-4" />}
        accentColor="text-danger"
        products={bestSellers}
        viewAllHref="/search?sort=rating"
        {...sharedRowProps}
      />

      {/* 7. EDITORIAL / PROMO BAND */}
      <div className="relative rounded-panel overflow-hidden bg-gradient-to-br from-stone-800 to-stone-900 text-white">
        <div className="absolute inset-0 opacity-20" style={{backgroundImage: 'url(https://images.unsplash.com/photo-1490481651871-ab68de25d43d?auto=format&fit=crop&w=1200&q=60)', backgroundSize: 'cover', backgroundPosition: 'center'}} />
        <div className="relative z-10 flex flex-col items-center text-center py-14 px-6 space-y-4">
          <p className="text-xs font-black uppercase tracking-widest text-white/60">Trending This Season</p>
          <h2 className="text-3xl sm:text-4xl font-black leading-tight">The Festive Edit</h2>
          <p className="text-white/70 text-sm font-medium max-w-sm">Discover handcrafted styles curated for every occasion — from weddings to workdays</p>
          <a href="/category/ethnic-wear" className="mt-2 inline-flex items-center gap-2 px-6 py-3 bg-white text-stone-900 font-black text-sm rounded-control hover:bg-stone-100 transition-all hover:-translate-y-0.5">
            <TrendingUp className="w-4 h-4" />
            Shop the Edit
          </a>
        </div>
      </div>

      {/* 8. TRUST & COMPLIANCE BANNER */}
      <TrustBanner
        onOpenReviewModal={(p) => setReviewProduct(p)}
        sampleProduct={products[0]}
      />

      </>)}

      {/* 9. FLOATING STICKY COMPARISON BAR */}
      <FloatingCompareBar
        compareList={compareList}
        onLaunchMatrix={() => setIsCompareModalOpen(true)}
        onClearCompare={() => setCompareList([])}
      />


      {/* 11. AI SHOPPING AGENT COPILOT */}
      {/* Queries the catalog itself now, so it no longer takes a product list. */}
      <AIAgentCopilot onAddToCart={handleAddToCart} />

      {/* 12. PRODUCT COMPARISON MODAL */}
      <ProductComparisonModal
        isOpen={isCompareModalOpen}
        onClose={() => setIsCompareModalOpen(false)}
        compareProducts={compareList}
        onAddToCart={handleAddToCart}
        onRemove={(id) => setCompareList(list => list.filter(p => p.id !== id))}
      />

      {/* 13. VERIFIED REVIEW SUBMISSION MODAL */}
      <VerifiedReviewModal
        isOpen={!!reviewProduct}
        onClose={() => setReviewProduct(null)}
        product={reviewProduct}
        onSubmitReview={(rev) => alert(`Thank you ${rev.user}! Your review is sent for staff approval.`)}
      />
    </div>
  );
}
