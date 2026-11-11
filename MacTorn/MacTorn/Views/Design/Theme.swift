import AppKit
import SwiftUI

// MacTorn's visual language: "the dispatch board".
//
// Torn is a game of waiting, so the countdown is the hero. Surfaces are flat and neutral,
// structure comes from hairlines and a strict grid, colour means *state* and nothing else,
// and hierarchy comes from numerals set in condensed SF. There are no tinted cards, no
// gradients and no translucency: every colour below is opaque, which is also why Reduce
// Transparency needs no special handling outside this folder.
//
// Every screen takes its colours, type and spacing from here. A view that reaches for
// `Color.green.opacity(0.1)` or `.cornerRadius(8)` on its own is drifting from the system.

enum Board {
    // MARK: Layout

    /// The panel is one fixed width in the menu bar and in the window a widget opens.
    static let panelWidth: CGFloat = 360
    static let panelHeight: CGFloat = 640
    static let railWidth: CGFloat = 48
    /// Horizontal inset of module content.
    static let gutter: CGFloat = 16

    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
    }

    /// Two radii only: controls, and the small things inside them.
    enum Radius {
        static let control: CGFloat = 7
        static let small: CGFloat = 3
    }

    // MARK: Surfaces

    static let surface = Color(light: 0xFFFFFF, dark: 0x232325)
    static let rail = Color(light: 0xF0F0F2, dark: 0x1A1A1C)
    /// Text fields and other wells sunk into the surface.
    static let well = Color(light: 0xF6F6F8, dark: 0x1A1A1C)
    /// Row separators.
    static let hairline = Color(light: 0xE4E4E7, dark: 0x3A3A3D, lightHC: 0x8E8E93, darkHC: 0x8E8E93)
    /// Control outlines: one step stronger than a separator.
    static let outline = Color(light: 0xD6D6DA, dark: 0x4A4A4E, lightHC: 0x6E6E73, darkHC: 0xAEAEB2)
    /// The unfilled part of a meter or progress line.
    static let track = Color(light: 0xE9E9EC, dark: 0x3A3A3D, lightHC: 0xC7C7CC, darkHC: 0x636366)

    // MARK: Ink

    static let ink = Color(light: 0x1D1D1F, dark: 0xF2F2F4)
    static let inkSecondary = Color(light: 0x5F5F66, dark: 0xA4A4AB, lightHC: 0x3A3A3F, darkHC: 0xD1D1D6)

    // MARK: Accent (selection and primary actions; from the app icon)

    static let accent = Color(light: 0xB53A2F, dark: 0xFFB08A)
    static let onAccent = Color(light: 0xFFFFFF, dark: 0x3A1408)

    // MARK: State

    /// What a row, value or control is telling the player. Colour is never decoration here.
    enum Tone {
        /// Available right now; acting on it is possible.
        case ready
        /// Counting down or filling up.
        case counting
        /// Needs attention: a danger, an error, a hit against the player.
        case alert
        /// Informational or far away.
        case idle

        /// Fills: rails, meter bars, dots.
        var fill: Color {
            switch self {
            case .ready: return Color(light: 0x2E9E57, dark: 0x5FD38C)
            case .counting: return Color(light: 0xD99A00, dark: 0xF0B341)
            case .alert: return Color(light: 0xD5402C, dark: 0xFF7A6B)
            case .idle: return Color(light: 0xC9C9CE, dark: 0x5A5A5F)
            }
        }

        /// Text on the surface: darker than the fill in light mode so it holds 4.5:1.
        var ink: Color {
            switch self {
            case .ready: return Color(light: 0x17753F, dark: 0x5FD38C)
            case .counting: return Color(light: 0x8F5300, dark: 0xF0B341)
            case .alert: return Color(light: 0xB3261E, dark: 0xFF8A7A)
            case .idle: return Board.inkSecondary
            }
        }

        /// A barely-there wash for a control in this state.
        var wash: Color {
            switch self {
            case .ready: return Color(light: 0xF1F9F4, dark: 0x1F2E25)
            case .counting: return Color(light: 0xFCF6E8, dark: 0x302A1C)
            case .alert: return Color(light: 0xFDF1EF, dark: 0x33211F)
            case .idle: return Board.well
            }
        }

        var outline: Color {
            switch self {
            case .ready: return Color(light: 0xBFE0CC, dark: 0x2F5A41)
            case .counting: return Color(light: 0xEBD9A8, dark: 0x5E4D22)
            case .alert: return Color(light: 0xF0C4BE, dark: 0x6B332D)
            case .idle: return Board.outline
            }
        }
    }

    /// The four Torn bars keep the colours players know from the game.
    enum Meter {
        static let energy = Color(light: 0x2E9E57, dark: 0x4CC078)
        static let nerve = Color(light: 0xD5402C, dark: 0xF0604B)
        static let happy = Color(light: 0xD99A00, dark: 0xF0B341)
        static let life = Color(light: 0x2D78CC, dark: 0x5AA2F0)
    }
}

// MARK: - Type

extension Font {
    /// Screen and player names.
    static let boardTitle = Font.system(size: 16, weight: .semibold)
    /// Section headings above a strong rule.
    static let boardSection = Font.system(size: 12, weight: .semibold)
    static let boardBody = Font.system(size: 13)
    /// Row titles.
    static let boardStrong = Font.system(size: 13, weight: .medium)
    static let boardCaption = Font.system(size: 12)
    /// Secondary lines under a row title; the smallest text in the app.
    static let boardDetail = Font.system(size: 11)

    /// Numerals: condensed SF with fixed-width digits, so a ticking countdown never shifts.
    /// The one place the app is typographically loud.
    static func figure(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        Font.system(size: size, weight: weight).width(.condensed).monospacedDigit()
    }

    /// The countdown in a "Next up" row.
    static let figureRow = Font.figure(24)
    /// Values beside a label: meter readings, prices, counts.
    static let figureValue = Font.figure(16)
    /// A screen's single headline number: a flight countdown, a total.
    static let figureHero = Font.figure(52)
}

// MARK: - Colour plumbing

extension Color {
    /// An opaque colour for light and dark, optionally stronger under Increase Contrast.
    init(light: UInt32, dark: UInt32, lightHC: UInt32? = nil, darkHC: UInt32? = nil) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [
                .aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua,
            ])
            switch match {
            case .darkAqua: return NSColor(hex: dark)
            case .accessibilityHighContrastAqua: return NSColor(hex: lightHC ?? light)
            case .accessibilityHighContrastDarkAqua: return NSColor(hex: darkHC ?? dark)
            default: return NSColor(hex: light)
            }
        })
    }
}

private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
