# UI Design System Notes

Last audit: 2026-05-24 Europe/Istanbul

Use this before changing Flutter UI. The goal is to keep KlioAI visually coherent while making focused fixes.

## Current Visual Language

- Dark, immersive learning interface.
- Theme-aware gradients, glass cards, animated backgrounds, and neon-like accents.
- The app has multiple selectable themes, so most UI color choices must come from the selected theme instead of local hardcoded colors.
- Existing screens favor rounded glass panels, compact stats, icon-led actions, and animated backgrounds.

## Theme Source Of Truth

- `flutter_vocabmaster/lib/theme/app_theme.dart`
- `flutter_vocabmaster/lib/theme/theme_catalog.dart`
- `flutter_vocabmaster/lib/theme/theme_provider.dart`
- `flutter_vocabmaster/lib/widgets/animated_background.dart`
- `flutter_vocabmaster/lib/widgets/modern_background.dart`
- `flutter_vocabmaster/lib/widgets/modern_card.dart`

Current theme catalog includes:

- `Ice Blue`
- `Neural Glow`
- `Midnight Focus`
- `Emerald Calm`
- `Solar Energy`

## UI Rules For Agents

- Reuse `ThemeProvider` and `AppThemeConfig` when a screen already participates in the theme system.
- Prefer `selectedTheme.colors.primary`, `accent`, `accentGlow`, `textPrimary`, `textSecondary`, `cardBackground`, and `cardBorder` over raw `Color(...)`.
- Do not introduce a new dominant palette for a local feature.
- Avoid making a screen mostly one hardcoded hue. Several legacy screens still have hardcoded cyan/blue; do not copy that pattern into new work.
- Keep `ModernCard`/glass panels as the framed unit. Do not nest card-looking containers inside other cards unless the existing screen already does this for a specific component.
- Buttons should be clear commands; icon buttons should use existing Flutter/Lucide icon conventions when available.
- Text must fit on small screens. Use wrapping, shorter labels, or layout changes instead of shrinking by viewport width.
- Do not add landing-page style hero sections inside app workflows.

## Subscription Page Specifics

The current subscription UI is a focused mobile paywall:

- Background: `ModernBackground`.
- Visible plans currently come from `PRO_MONTHLY` and `PRO_ANNUAL`.
- It currently uses several local cyan constants. If changing this page, prefer converting touched parts to `ThemeProvider` rather than doing a broad visual rewrite.
- Keep the restore purchases action visible on Android/iOS.
- Do not hide errors that are needed for billing diagnosis; make user-facing copy actionable but keep debug logs specific.

## Practice Page Specifics

- Practice is the core value surface.
- Do not reintroduce page-level subscription locks that block free users from opening practice.
- Backend AI endpoints and quota status should enforce AI access.
- Keep Word Galaxy and Neural Game visuals aligned with theme state.

## Checklist For UI Changes

1. Identify whether the screen already reads `ThemeProvider`.
2. Reuse existing widgets and spacing before adding new primitives.
3. Check mobile overflow risk manually in the changed layout.
4. Run targeted `flutter analyze` on touched files.
5. Add/adjust widget tests when the behavior is more than cosmetic.
