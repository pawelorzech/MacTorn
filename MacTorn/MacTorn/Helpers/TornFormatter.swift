import Foundation

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

    /// Formats an integer with decimal grouping separators (e.g. "1,250,000").
    static func formatNumber(_ number: Int) -> String {
        decimalFormatter.string(from: NSNumber(value: number)) ?? "\(number)"
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
