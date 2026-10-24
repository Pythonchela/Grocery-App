# The mobile design system

The app is the main product, so it has its own design system rather than a
port of the web's. This file says which parts are shared, which parts the app
owns, and the rules that keep it feeling like a phone app.

```
lib/design/
├── tokens.g.dart            SHARED  colour, type, radius, spacing  (generated from packages/tokens)
├── brand.g.dart             SHARED  names, legal text              (generated from packages/brand)
├── theme_overrides.dart     SHARED  the admin's colour choices, applied live from GET /theme
├── theme.dart               MOBILE  DsThemeScope + Material theme: native transitions, nav bars
├── mobile.dart              MOBILE  touch, motion, haptics, window classes
├── mobile_components.dart   MOBILE  BxPressable, BxBottomBar, BxQuantityStepper, BxSwipeToRemove…
└── components.dart          MIXED   BxButton, BxField, BxCard… — shared names, mobile geometry
```

## What is shared, and why

Colour, typeface, corner radius and the brand's name and voice come from
`packages/tokens` and `packages/brand`. A shopper who uses both should recognise
one product, and an admin who changes the accent colour in the web panel should
see it change in the app too (`theme_overrides.dart`). Nothing in this folder
hard-codes a hex value.

## What the app owns, and why

A phone is not a small desktop. These are decisions about the device, so they
are made here and not inherited.

| Concern | Rule | Where |
|---|---|---|
| **Touch targets** | Anything pressable is at least 48dp (44 for `sm` buttons). Primary actions are 56. Visuals may be smaller; hit areas may not. | `DsTouch`, `BxButton` |
| **Thumb zone** | A screen's primary action lives in a bottom bar, above the gesture area. | `BxBottomBar` |
| **Navigation** | Phones: a bottom `NavigationBar`. Tablets, foldables, landscape: a side `NavigationRail`, content held to a readable width. | `AppShell`, `DsWindowClass` |
| **Gestures** | Swipe a list row to remove it, with Undo. Pull to refresh. Android predictive back; iOS edge-swipe back. | `BxSwipeToRemove`, `theme.dart` |
| **Feedback** | A tap on glass has no click, so a short haptic confirms it. Same meaning every time: `tap` press, `select` choice changed, `success` done, `warn` destructive. | `DsHaptics` |
| **Motion** | Short and decelerating (90–400ms). Respects the system "remove animations" setting. | `DsMobileMotion` |
| **Sheets** | Bottom sheets show a drag handle and dismiss by drag, scrim tap or back. | `showBxSheet` |
| **Text** | Layouts survive the system font scale up to 200%; nothing is sized in a way that clips at large type. | tests at 320 / 1.5× / 2× |
| **Safe areas** | Notches, cut-outs and the gesture bar are never drawn under. | `BxBottomBar`, `SafeArea` |

## Rules for new screens

1. Reach for a `Bx*` component before writing a widget. If one is missing,
   add it here rather than inlining it.
2. Colours come from `context.ds`; sizes from `DsSpace`, `DsText`, `DsRadius`,
   `DsTouch`. No literals.
3. Every pressable thing is ≥ 48dp. Use `BxPressable` for non-button rows.
4. Put the main action in `BxBottomBar`, not at the end of a long scroll.
5. Destructive list actions are swipeable *and* undoable.
6. Test it at 320dp wide and at 1.5× / 2× text, and at 900dp wide.
7. `BxButtonSize.xs` is for dense inline actions that sit beside a larger
   target. It is never a screen's only path to an action.

## Seeing it

Open **Design system** from the debug entry point (`main_design_system.dart`).
The first sections mirror the web page; **Mobile patterns** at the end is the
part that has no web twin.
