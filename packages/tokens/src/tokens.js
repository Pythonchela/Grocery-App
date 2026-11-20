/**
 * packages/tokens — THE authored source of truth for the design system.
 *
 * Nothing else in the repo declares a colour, radius, shadow or type step by
 * hand. `npm run tokens:build` reads this file and emits every consumable form:
 *
 *   dist/tokens.css   CSS custom properties + a Tailwind v4 @theme block
 *   dist/tokens.js    plain JS object, for anything that needs values at runtime
 *   dist/tokens.json  platform-neutral, for non-JS consumers
 *   dist/tokens.dart  Flutter, for the mobile app
 *
 * Colours are authored as light/dark PAIRS. Because the emitted CSS puts the
 * dark value behind `.dark` and the Tailwind utilities reference the variable
 * rather than a literal, `bg-surface` is correct in both themes with no
 * `dark:` variant anywhere. That is what makes full dark-mode coverage a
 * property of the token layer instead of an 80-file retrofit.
 */

// ─── PRIMITIVES ──────────────────────────────────────────────────────────────
// Raw values. These are the only literals in the system; every semantic token
// below points at one of them. Components must never reference this object.
const palette = {
  white: '#FFFFFF',
  black: '#000000',

  // Neutral ramp — warm-tinted to sit with the off-white canvas
  neutral: {
    25:  '#FBFBFA',
    50:  '#F7F6F3',
    100: '#F1F0EC',
    200: '#E5E7EB',
    300: '#D1D5DB',
    400: '#9CA3AF',
    500: '#6B7280',
    600: '#4B5563',
    700: '#374151',
    800: '#1F2937',
    900: '#111827',
    950: '#0D0D0D',
  },

  // Dark-theme ramp — cool-tinted so it reads as a distinct surface family
  slate: {
    850: '#161A24',
    900: '#11151E',
    950: '#0B0F19',
    border: '#2A303C',
    borderStrong: '#3A4150',
  },

  blue:  { soft: '#E8F0FE', 500: '#1A56FF', 600: '#1444CC', dark: '#1E293B' },
  // The food and grocery app's own colours: fresh green for actions, warm yellow for highlights.
  fresh: { soft: '#E8F5E9', 500: '#0C831F', 600: '#0A6B19', dark: '#0F2A17' },
  sun:   { 400: '#F8CB46', 500: '#E7B82D' },
  neon:  { 500: '#00E699', 600: '#00C984', surface: '#05080E' },
  lime:  { 400: '#C8FF00', 500: '#A6D600' },
  green: { soft: '#E6F4EA', 500: '#16A34A', 600: '#15803D', 700: '#2E7D32', dark: '#0F2A17' },
  amber: { soft: '#FEF6E7', 500: '#D97706', 600: '#B45309', dark: '#2A1F0A' },
  red:   { soft: '#FEF2F2', 500: '#E53935', 600: '#DC2626', 700: '#B91C1C', dark: '#2A1111' },
  tan:   { soft: '#FBF7EE' },
};

// ─── SEMANTIC COLOUR TOKENS ──────────────────────────────────────────────────
// [light, dark]. These names are what components use.
const color = {
  // Surfaces, back to front
  'canvas':          [palette.neutral[50],  palette.slate[950]],
  'surface':         [palette.white,        palette.slate[850]],
  'surface-muted':   [palette.neutral[25],  palette.slate[900]],
  'surface-sunken':  [palette.neutral[100], palette.slate[950]],
  'inverse':         [palette.neutral[900], palette.neutral[100]],

  // Foreground / text
  'ink':             [palette.neutral[900], '#F3F4F6'],
  'ink-muted':       [palette.neutral[600], '#B6BCC8'],
  'ink-subtle':      [palette.neutral[400], '#7C8494'],
  'ink-inverse':     [palette.white,        palette.neutral[900]],

  // Lines
  'line':            [palette.neutral[200], palette.slate.border],
  'line-strong':     [palette.neutral[400], palette.slate.borderStrong],

  // Brand — primary is the near-black used for buttons and nav
  // Buttons and the open tab are the shop's green, as in quick-delivery apps.
  'primary':         [palette.fresh[500],   '#3DBE5A'],
  'primary-hover':   [palette.fresh[600],   '#63D07C'],
  'on-primary':      [palette.white,        palette.neutral[950]],

  // Brand — accent is the action colour: fresh green in the food and grocery app
  'accent':          [palette.fresh[500],   '#3DBE5A'],
  'accent-hover':    [palette.fresh[600],   '#63D07C'],
  'accent-soft':     [palette.fresh.soft,   palette.fresh.dark],
  'on-accent':       [palette.white,        palette.neutral[950]],

  // Brand — highlight is the warm yellow used for the main call to action and special badges
  'highlight':       [palette.sun[400],     palette.sun[400]],
  'highlight-hover': [palette.sun[500],     palette.sun[500]],
  'on-highlight':    [palette.neutral[950], palette.neutral[950]],

  // Status
  'success':         [palette.green[700],   '#4ADE80'],
  'success-soft':    [palette.green.soft,   palette.green.dark],
  'warning':         [palette.amber[600],   '#FBBF24'],
  'warning-soft':    [palette.amber.soft,   palette.amber.dark],
  'danger':          [palette.red[500],     '#F87171'],
  'danger-hover':    [palette.red[700],     '#FCA5A5'],
  'danger-soft':     [palette.red.soft,     palette.red.dark],
  'info':            [palette.blue[500],    '#5B8BFF'],
  'info-soft':       [palette.blue.soft,    palette.blue.dark],

  // AI copilot. A distinct accent so agent-generated surfaces are visually
  // separable from ordinary UI — it was six hardcoded #00E699 literals before.
  'agent':           [palette.neon[500],    palette.neon[500]],
  'agent-hover':     [palette.neon[600],    palette.neon[600]],
  'agent-surface':   [palette.neon.surface, palette.neon.surface],

  // Commerce-specific
  'sale':            [palette.red[600],     '#F87171'],
  'new':             [palette.green[500],   '#4ADE80'],
  'rating':          ['#F59E0B',            '#FBBF24'],

  // Decorative section fills used by the storefront
  'pastel-green':    [palette.green.soft,   palette.green.dark],
  'pastel-tan':      [palette.tan.soft,     palette.slate[900]],
  'pastel-blue':     [palette.blue.soft,    palette.blue.dark],

  // Scrollbars
  'scroll-track':    [palette.neutral[100], palette.slate[900]],
  'scroll-thumb':    [palette.neutral[300], palette.slate.borderStrong],
};

// ─── RADII ───────────────────────────────────────────────────────────────────
// Named by role, not by size, so "which rounding does a card get" has exactly
// one answer. Replaces the six-way rounded-md/lg/xl/2xl/3xl/full spread.
const radius = {
  chip:    '6px',    // tags, small badges
  control: '10px',   // inputs, selects, buttons
  card:    '12px',   // product cards, list rows, table containers
  panel:   '16px',   // modals, drawers, page sections
  pill:    '9999px', // filter chips, avatars, the active nav pill
};

// ─── SHADOWS ─────────────────────────────────────────────────────────────────
// Authored as structured layers, not CSS strings. CSS gets them joined into a
// box-shadow value; Flutter gets them as BoxShadow constructors. If these were
// strings the Dart generator would have to parse CSS, which is exactly the kind
// of second representation this package exists to avoid.
// `[x, y, blur, spread, r, g, b, alpha]`
const shadow = {
  subtle: {
    light: [[0, 1, 2, 0, 0, 0, 0, 0.04]],
    dark:  [[0, 1, 2, 0, 0, 0, 0, 0.40]],
  },
  card: {
    light: [[0, 1, 3, 0, 0, 0, 0, 0.05], [0, 4, 12, -4, 0, 0, 0, 0.06]],
    dark:  [[0, 1, 3, 0, 0, 0, 0, 0.40], [0, 4, 12, -4, 0, 0, 0, 0.35]],
  },
  hover: {
    light: [[0, 6, 20, -6, 0, 0, 0, 0.12]],
    dark:  [[0, 6, 20, -6, 0, 0, 0, 0.55]],
  },
  panel: {
    light: [[0, 25, 50, -12, 0, 0, 0, 0.25]],
    dark:  [[0, 25, 50, -12, 0, 0, 0, 0.70]],
  },
  button: {
    light: [[0, 2, 8, 0, 17, 24, 39, 0.15]],
    dark:  [[0, 2, 8, 0, 0, 0, 0, 0.45]],
  },
};

// ─── TYPOGRAPHY ──────────────────────────────────────────────────────────────
// Only families that are actually loaded belong here. `fontsToLoad` drives the
// stylesheet link, so a family can never be referenced without being fetched.
const font = {
  sans:    "'Plus Jakarta Sans', ui-sans-serif, system-ui, sans-serif",
  display: "'Outfit', 'Plus Jakarta Sans', ui-sans-serif, system-ui, sans-serif",
  mono:    "'JetBrains Mono', ui-monospace, SFMono-Regular, Menlo, monospace",
};

const fontsToLoad = [
  { family: 'Plus Jakarta Sans', weights: '400;500;600;700;800' },
  { family: 'Outfit',            weights: '400;500;600;700;800' },
  { family: 'JetBrains Mono',    weights: '400;500;600' },
];

// Named weights, so "bold" means one thing on web and mobile. The numbers are
// what Flutter's FontWeight.w### needs; CSS uses them directly.
// Lighter than before (bold was 700, black 800/900): headings read as confident
// rather than heavy, and body text stays crisp. Web gets the same numbers for
// Tailwind's font-bold / font-black through the @theme block.
const weight = {
  regular: 400,
  medium: 500,
  semibold: 600,
  bold: 600,
  black: 700,
};

// Spacing scale in px. Tailwind's own 4px scale covers the web side, but the
// Flutter app has no equivalent, so this is what keeps gutters and insets the
// same on both.
const space = {
  0: 0, 1: 4, 2: 8, 3: 12, 4: 16, 5: 20, 6: 24, 8: 32, 10: 40, 12: 48, 16: 64,
};

const text = {
  '2xs': ['0.6875rem', '1rem'],
  xs:    ['0.75rem',   '1.125rem'],
  sm:    ['0.8125rem', '1.25rem'],
  base:  ['0.875rem',  '1.375rem'],
  md:    ['1rem',      '1.5rem'],
  lg:    ['1.125rem',  '1.625rem'],
  xl:    ['1.375rem',  '1.75rem'],
  '2xl': ['1.75rem',   '2.125rem'],
  '3xl': ['2.25rem',   '2.5rem'],
  '4xl': ['3rem',      '3.25rem'],
};

// The phone's own type scale. A desktop-sized heading on a 360dp screen reads
// as a web page, so the app steps every size from `sm` up one notch smaller:
// body stays 13, titles 15-16, the biggest headline 22. Same names, so no
// screen changes; only the Flutter output uses it.
const mobileText = {
  '2xs': ['0.625rem',  '1rem'],
  xs:    ['0.6875rem', '1rem'],
  sm:    ['0.75rem',   '1.125rem'],
  base:  ['0.8125rem', '1.25rem'],
  md:    ['0.9375rem', '1.375rem'],
  lg:    ['1rem',      '1.5rem'],
  xl:    ['1.1875rem', '1.625rem'],
  '2xl': ['1.375rem',  '1.75rem'],
  '3xl': ['1.75rem',   '2.125rem'],
  '4xl': ['2.25rem',   '2.5rem'],
};

// ─── MOTION & LAYERING ───────────────────────────────────────────────────────
const motion = {
  fast:   '120ms',
  base:   '200ms',
  slow:   '320ms',
  ease:   'cubic-bezier(0.4, 0, 0.2, 1)',
  spring: 'cubic-bezier(0.34, 1.56, 0.64, 1)',
};

// Central z-index scale — stops the arms race of arbitrary z-50/z-[999] values.
const z = {
  base:     '0',
  raised:   '10',
  sticky:   '20',
  header:   '30',
  dropdown: '40',
  overlay:  '50',
  modal:    '60',
  toast:    '70',
};

// Font family names on their own — CSS wants a full fallback stack, Flutter
// wants just the family. Both derive from this one list.
const fontFamily = {
  sans: 'Plus Jakarta Sans',
  display: 'Outfit',
  mono: 'JetBrains Mono',
};

module.exports = {
  palette, color, radius, shadow, font, fontFamily, fontsToLoad,
  text, mobileText, weight, space, motion, z,
};
