import Foundation

// MARK: - Menu Bar Display

/// What the menu bar label should render at any given moment.
/// Priority: traveling > hospital > jail > soonest cooldown > fallback icon.
///
/// The cases carry **meaning** (destination name, cooldown kind), not presentation.
/// The flag/emoji glyphs are derived at render time. Storing only the glyph — as this
/// enum used to — made the state unspeakable: VoiceOver read "airplane, flag of United
/// Kingdom, 2 colon 35" because there was no name left in the model to say instead.
enum MenuBarDisplay: Equatable {
    case traveling(destination: String?, seconds: Int)
    case hospitalAbroad(destination: String?, seconds: Int)
    case hospitalAtHome(seconds: Int)
    case jail(seconds: Int)
    case cooldown(kind: CooldownKind, seconds: Int)
    case fallbackIcon

    /// Spoken description for the menu-bar label — the app's only always-visible surface.
    /// Pure function of the case, so it is unit-testable without a running menu bar.
    var accessibilityDescription: String {
        switch self {
        case .traveling(let destination, let seconds):
            let place = destination.map { " to \($0)" } ?? ""
            return "Traveling\(place), arriving in \(Self.spokenDuration(seconds))"
        case .hospitalAbroad(let destination, let seconds):
            let place = destination.map { " in \($0)" } ?? " abroad"
            return "In hospital\(place), \(Self.spokenDuration(seconds)) remaining"
        case .hospitalAtHome(let seconds):
            return "In hospital, \(Self.spokenDuration(seconds)) remaining"
        case .jail(let seconds):
            return "In jail, \(Self.spokenDuration(seconds)) remaining"
        case .cooldown(let kind, let seconds):
            return "\(kind.displayName) cooldown, \(Self.spokenDuration(seconds)) remaining"
        case .fallbackIcon:
            return "MacTorn — no active timer"
        }
    }

    /// "1 hour 4 minutes", "2 minutes 35 seconds", "12 seconds". Zero-valued leading
    /// components are dropped so the phrase stays short enough to be useful in speech.
    static func spokenDuration(_ seconds: Int) -> String {
        guard seconds > 0 else { return "0 seconds" }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60

        func unit(_ value: Int, _ name: String) -> String {
            "\(value) \(name)\(value == 1 ? "" : "s")"
        }

        if hours > 0 {
            return minutes > 0
                ? "\(unit(hours, "hour")) \(unit(minutes, "minute"))"
                : unit(hours, "hour")
        }
        if minutes > 0 {
            return secs > 0
                ? "\(unit(minutes, "minute")) \(unit(secs, "second"))"
                : unit(minutes, "minute")
        }
        return unit(secs, "second")
    }
}
