import Foundation
import SwiftUI

/// Centralized, high-performance formatters for numbers and currency.
///
/// Replaces repeated instantiations of `NumberFormatter` across SwiftUI views
/// to eliminate main-thread allocations during rendering and scrolling.
/// Uses `en_US` locale to match Torn's standard currency and integer formatting.
enum TornFormatter {
    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .currency
        formatter.currencySymbol = "$"
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    private static let decimalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .decimal
        return formatter
    }()

    /// Formats an integer amount as currency (e.g. "$1,250,000").
    static func formatMoney(_ amount: Int) -> String {
        currencyFormatter.string(from: NSNumber(value: amount)) ?? "$\(amount)"
    }

    /// Currency for an optional amount: `nil` renders as "Unavailable". Every money
    /// surface in the app used to reimplement this guard (audit D-2).
    static func formatMoney(_ amount: Int?) -> String {
        guard let amount else { return "Unavailable" }
        return formatMoney(amount)
    }

    /// Formats an integer with decimal grouping separators (e.g. "1,250,000").
    static func formatNumber(_ number: Int) -> String {
        decimalFormatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }

    // MARK: - Durations

    /// `H:MM:SS` above an hour, else `M:SS`. Negative input clamps to zero. This is the
    /// one countdown format; it used to be copy-pasted into ten views (audit D-1).
    static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let hours = s / 3600
        let minutes = (s % 3600) / 60
        let secs = s % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// `clock`, with a caller-supplied label for the non-positive case ("Ready",
    /// "Arrived!", …).
    static func clock(_ seconds: Int, zeroText: String) -> String {
        seconds <= 0 ? zeroText : clock(seconds)
    }

    /// Always `M:SS`, even past an hour (e.g. a 90-minute chain timeout reads "90:00").
    static func minutesSeconds(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// Day-aware duration for long timers (education, rent): "2d 3h", "3h 5m", "12m".
    static func coarseDuration(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let days = s / 86_400
        let hours = (s % 86_400) / 3600
        let minutes = (s % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    /// Compact human countdown for the Next Action strip: "45s", "4:32", "2h 05m", "1d 3h".
    static func compactETA(_ seconds: Int) -> String {
        let s = max(0, seconds)
        if s < 60 { return "\(s)s" }
        if s < 3600 { return String(format: "%d:%02d", s / 60, s % 60) }
        if s < 86_400 { return String(format: "%dh %02dm", s / 3600, (s % 3600) / 60) }
        return String(format: "%dd %dh", s / 86_400, (s % 86_400) / 3600)
    }

    // MARK: - Relative dates

    private static let shortRelativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    private static let abbreviatedRelativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    /// "2 min ago" / "in 3 hours". `abbreviated` gives "2m ago". Cached — these used to be
    /// allocated per call inside view bodies (audit D-8).
    static func relativeDate(_ date: Date, relativeTo now: Date = Date(), abbreviated: Bool = false) -> String {
        let formatter = abbreviated ? abbreviatedRelativeFormatter : shortRelativeFormatter
        return formatter.localizedString(for: date, relativeTo: now)
    }
}

extension View {
    /// Opens a Torn web URL in the user's preferred browser. Every tab used to carry its
    /// own `openURL(_:)` private helper (audit D-3); this is the one copy.
    /// `BrowserManager.open` rejects non-web schemes.
    func openTorn(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        BrowserManager.shared.open(url)
    }
}

extension String {
    /// Strips HTML tags and decodes common HTML entities returned by the Torn API.
    var strippedHTMLAndDecodedEntities: String {
        self.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
