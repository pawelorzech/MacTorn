# MacTorn visual identity

Last verified: 2026-08-26

## Direction

The MacTorn mark combines a broad tornado arc with a lightning cut. It represents
live state, alerts, and speed without reusing Torn's official identity. Its shape is
deliberately simple enough to survive the 16 px Finder and menu contexts.

The visual system borrows the energy of Material 3 Expressive — stronger color,
contrasting rounded shapes, and a clearer selected state — but uses native SwiftUI and
macOS controls. Material is an influence, not a component library for this macOS app.

## Palette

| Role | Light | Dark | Use |
| --- | --- | --- | --- |
| Accent | `#B53A2F` | `#FFB08A` | selection, links, primary actions |
| Icon background | deep indigo/plum | deep indigo/plum | full-bleed icon ground |
| Icon primary | coral to amber | coral to amber | tornado and bolt mark |
| Icon detail | electric cyan | electric cyan | one supporting accent only |

Semantic colors such as success, warning, destructive, Energy, Nerve, Happy, and Life
keep their existing meanings. The brand accent must not replace them.

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
- Use a capsule only for the top-level three-way group navigation. Module navigation and
  cards stay quieter and closer to native macOS geometry.
- Honor Reduce Transparency and Increase Contrast exactly as the current UI does.
- Prefer SF Symbols for interface actions; the custom mark is for product identity.

## References

- [Apple Human Interface Guidelines: App icons](https://developer.apple.com/design/human-interface-guidelines/app-icons)
- [Apple Human Interface Guidelines: Branding](https://developer.apple.com/design/human-interface-guidelines/branding)
- [Material Design 3](https://m3.material.io/)
