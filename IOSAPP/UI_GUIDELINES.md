# PhotoDelete iOS UI Guidelines

This is the source of truth for the current native SwiftUI app UI. Historical
HTML prototypes and visual explorations must not define current app behavior.

## Navigation And Presentation

- Root tab screens may hide the system navigation bar only when they own the
  full top-level chrome for that tab.
- Pushed detail screens created by `NavigationLink` or `navigationDestination`
  should use the system navigation bar, system back button, and native
  edge-swipe return gesture. Do not hand-draw back buttons for ordinary pushed
  detail pages.
- Modal-only detail screens presented by `sheet` or `fullScreenCover` should use
  system toolbar actions such as Done, Cancel, or Close. Wrap them in a local
  `NavigationStack` when they need a title or toolbar.
- Full-screen photo review can keep custom chrome when it protects pending batch
  operations. If native edge-swipe return is added there, first design an exit
  confirmation flow that preserves staged delete/favorite work.
- Avoid forcing toolbar backgrounds on pushed detail pages unless the product
  design explicitly requires it. Prefer system navigation chrome so iOS 26
  Liquid Glass can render naturally.

## iOS 26 Liquid Glass

- Prefer system `NavigationStack`, toolbar, tab bar, sheet, and button behavior
  before adding custom glass surfaces.
- Use iOS 26 Liquid Glass APIs only for interactive controls or floating chrome
  that genuinely need custom treatment, and always provide an `#available`
  fallback for iOS 16-25.
- Do not layer opaque custom backgrounds over system bars unless there is a
  deliberate product reason.

## Accessibility And Dynamic Type

- Prefer semantic SwiftUI text styles or shared scaled typography from
  `DesignSystem.swift` instead of fixed font sizes for core UI text.
- Icon-only controls must have an accessibility label, a clear role, and at
  least a 44 x 44 point hit target.
- Prefer `Button`, `NavigationLink`, `Toggle`, `Picker`, and `Menu` over
  `onTapGesture` for interactive controls so VoiceOver, Voice Control, focus,
  and hit testing work predictably.
- Do not rely on color alone to communicate state. Pair color with text, icons,
  shape, or layout.
- Respect Reduce Motion for decorative animation and nonessential transitions.

## Lists, Settings, And Controls

- Prefer system list, form, row, toolbar, and confirmation patterns for settings
  and management screens unless a custom layout materially improves the photo
  workflow.
- Settings, album, and list-heavy screens should prefer `List(.insetGrouped)`,
  `Form`, or grouped surfaces that match system behavior. Avoid hand-drawn
  nested card groups inside list rows.
- Album rows should stay compact: cover, name, count, a concise progress signal,
  and the system disclosure affordance. Put deeper progress and statistics in
  detail or advanced screens.
- Use native `swipeActions` for edit and destructive row actions so gestures,
  roles, and accessibility remain system-consistent.
- Long scrollable settings or list screens should keep scroll indicators unless
  hiding them is an intentional visual choice.
- Use `foregroundStyle`, semantic materials, and system roles where possible so
  controls adapt to light/dark mode, contrast, tint, and future OS styling.
- First-use guidance should be short-lived toast, hint, menu, or sheet copy.
  Do not permanently insert tutorial text into dense primary lists.

## Localization And Public Copy

- All user-visible text must go through `L10n` and `Localizable.xcstrings` for
  Simplified Chinese, Traditional Chinese, and English.
- Keep public UI copy concise and user-facing. Do not put internal notes,
  implementation instructions, diagnostics, or agent process text into visible
  app UI or localized strings.
