# MacTorn visual identity

Last verified: 2026-11-11 | `redesign/dispatch-board`

## Direction

The MacTorn mark combines a broad tornado arc with a lightning cut. It represents
live state, alerts, and speed without reusing Torn's official identity. Its shape is
deliberately simple enough to survive the 16 px Finder and menu contexts.

The interface is "the dispatch board" (2026-11-11): flat opaque surfaces, sections as a
heading over a rule, rows closed by hairlines, and countdowns set in large condensed SF
numerals. Colour means state — ready, counting, alert, idle — plus the four game bar
colours; the coral accent marks selection and the one primary action. The design system
lives in `MacTorn/MacTorn/Views/Design/`, and the rules for using it are in the Frontend
Theme section of `CLAUDE.md`. It replaced the earlier Material-3-influenced look of tinted
rounded cards.

## Palette

| Role | Light | Dark | Use |
| --- | --- | --- | --- |
| Accent | `#B53A2F` | `#FFB08A` | selection, links, primary actions |
| Icon background | deep indigo/plum | deep indigo/plum | full-bleed icon ground |
| Icon primary | coral to amber | coral to amber | tornado and bolt mark |
| Icon detail | electric cyan | electric cyan | one supporting accent only |

State colours (`Board.Tone`) and the Energy, Nerve, Happy and Life bar colours
(`Board.Meter`) keep their meanings. The brand accent must not replace them.

## Assets

- Full-bleed identity master: `docs/assets/mactorn-app-icon-source.png` (1024 x
  1024 PNG), retained for the future layered Icon Composer migration.
- Shipping macOS 14 master: `docs/assets/mactorn-app-icon-legacy-1024.png`. It
  adds the transparent production margin and rounded artwork required before
  system-managed app-icon masking.
- Shipping renditions: `MacTorn/MacTorn/Assets.xcassets/AppIcon.appiconset/`.
- `make icon-check` verifies that all ten renditions contain real PNG data and have the
  dimensions and alpha channel declared by the asset catalog.

The project keeps the classic macOS asset catalog because CI is pinned to Xcode 16.4.
When the minimum release toolchain moves to Xcode 26, migrate the same mark to Apple's
layered Icon Composer format instead of maintaining two icon systems in parallel.

## Source generation prompt

The source concept was generated with OpenAI image generation from this art-direction
prompt, then adapted into the legacy macOS shipping geometry and optical sizes:

> Design a completely new, production-ready 1024 x 1024 macOS app icon for MacTorn, a
> native menu-bar companion for Torn. Use one bold, simple tornado arc cut by a lightning
> shape on a deep indigo-to-plum ground; coral-to-amber is primary and electric cyan is
> one restrained accent. Crisp vector-like geometry, generous safe space, readable at
> 16 px, no text, no official Torn logo, no extra rings, chrome, fine streaks, or mockup.

## Rules

- Keep the mark centered with generous safe space.
- Do not add text, rings, chrome, drop shadows, or fine streaks.
- Navigation is the icon rail on the left of the panel: nine modules in three groups and
  Settings at the bottom. There are no cards, capsules or tinted backgrounds.
- Every colour is opaque, so Reduce Transparency changes nothing but the modal scrim;
  Increase Contrast strengthens hairlines, outlines and secondary ink inside `Theme.swift`.
- Prefer SF Symbols for interface actions; the custom mark is for product identity.

## References

- [Apple Human Interface Guidelines: App icons](https://developer.apple.com/design/human-interface-guidelines/app-icons)
- [Apple Human Interface Guidelines: Branding](https://developer.apple.com/design/human-interface-guidelines/branding)
- [Material Design 3](https://m3.material.io/)
