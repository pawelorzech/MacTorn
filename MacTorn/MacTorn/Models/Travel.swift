import Foundation

// MARK: - Travel
struct Travel: Codable, Equatable {
    let destination: String?
    let timestamp: Int?
    let departed: Int?
    let timeLeft: Int?

    enum CodingKeys: String, CodingKey {
        case destination
        case timestamp
        case departed
        case timeLeft = "time_left"
    }

    var isAbroad: Bool {
        guard let dest = destination, let time = timeLeft else { return false }
        return dest != "Torn" && time == 0
    }

    var isTraveling: Bool {
        guard let time = timeLeft else { return false }
        return time > 0
    }

    var arrivalDate: Date? {
        guard isTraveling, let ts = timestamp else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(ts))
    }

    /// Remaining seconds of flight.
    ///
    /// `timestamp` is an absolute **server** timestamp and `time_left` is measured from
    /// the instant the *server* generated the response, so both `fetchTime` and `now`
    /// must be expressed on Torn's clock (`AppState.serverFetchTime` / `AppState.serverNow`)
    /// — mixing the two clocks is exactly the bug in issue #46. The `Date()` default is
    /// for pure-model callers that have no skew to correct.
    func remainingSeconds(from fetchTime: Date, now: Date = Date()) -> Int {
        // Primary: Use timestamp directly if available (more accurate)
        if let timestamp = timestamp, timestamp > 0 {
            guard let nowUnix = NumericSafety.integerAmount(now.timeIntervalSince1970) else { return 0 }
            return NumericSafety.remaining(until: timestamp, now: nowUnix) ?? 0
        }

        // Fallback: Use timeLeft with fetchTime offset (backward compatibility)
        guard let timeLeft = timeLeft, timeLeft > 0 else { return 0 }
        guard let elapsed = NumericSafety.integerAmount(max(0, now.timeIntervalSince(fetchTime))) else { return 0 }
        return max(0, timeLeft - elapsed)
    }

    /// Calculate flight progress (0.0 to 1.0) based on fetch time
    func flightProgress(from fetchTime: Date, now: Date = Date()) -> Double {
        guard let departed = departed, let timestamp = timestamp else { return 0 }
        let remaining = remainingSeconds(from: fetchTime, now: now)
        return Self.flightProgress(arrival: timestamp, departure: departed, remainingSeconds: remaining)
    }

    /// Shared by the model and the live UI. Remote timestamps must not overflow Int
    /// subtraction or crash rendering when a malformed response supplies Int.min.
    static func flightProgress(arrival: Int, departure: Int, remainingSeconds: Int) -> Double {
        guard departure > 0, arrival > departure else { return 0 }
        let duration = Double(arrival) - Double(departure)
        guard duration > 0 else { return 0 }
        return min(1, max(0, (duration - Double(max(0, remainingSeconds))) / duration))
    }
}

// MARK: - Travel Destinations
enum TornDestination: String, CaseIterable, Identifiable {
    case mexico = "Mexico"
    case caymanIslands = "Cayman Islands"
    case canada = "Canada"
    case hawaii = "Hawaii"
    case unitedKingdom = "United Kingdom"
    case argentina = "Argentina"
    case switzerland = "Switzerland"
    case japan = "Japan"
    case china = "China"
    case uae = "UAE"
    case southAfrica = "South Africa"

    var id: String { rawValue }

    enum FlightMethod: String, CaseIterable {
        case standard = "Standard"
        case airstrip = "Airstrip + pilot"
    }

    /// Torn documents up to 3% variance around the published base durations.
    static let estimateVariancePercent = 3

    var flag: String {
        switch self {
        case .mexico: return "🇲🇽"
        case .caymanIslands: return "🇰🇾"
        case .canada: return "🇨🇦"
        case .hawaii: return "🇺🇸"
        case .unitedKingdom: return "🇬🇧"
        case .argentina: return "🇦🇷"
        case .switzerland: return "🇨🇭"
        case .japan: return "🇯🇵"
        case .china: return "🇨🇳"
        case .uae: return "🇦🇪"
        case .southAfrica: return "🇿🇦"
        }
    }

    /// Current one-way base duration published by Torn.
    ///
    /// Patch #438 (2026-06-23) reduced every travel method by 5.26%. These values
    /// intentionally mirror the official table instead of deriving one method from
    /// another, because Torn rounds each displayed duration independently.
    /// Live flights never use this estimate: their countdown comes from the API's
    /// `travel.timestamp`, `departed`, and `time_left` fields.
    func flightTimeMinutes(method: FlightMethod = .standard) -> Int {
        switch (self, method) {
        case (.mexico, .standard): return 24
        case (.caymanIslands, .standard): return 33
        case (.canada, .standard): return 39
        case (.hawaii, .standard): return 127
        case (.unitedKingdom, .standard): return 151
        case (.argentina, .standard): return 158
        case (.switzerland, .standard): return 166
        case (.japan, .standard): return 213
        case (.china, .standard): return 229
        case (.uae, .standard): return 257
        case (.southAfrica, .standard): return 282
        case (.mexico, .airstrip): return 17
        case (.caymanIslands, .airstrip): return 23
        case (.canada, .airstrip): return 27
        case (.hawaii, .airstrip): return 89
        case (.unitedKingdom, .airstrip): return 106
        case (.argentina, .airstrip): return 111
        case (.switzerland, .airstrip): return 116
        case (.japan, .airstrip): return 149
        case (.china, .airstrip): return 160
        case (.uae, .airstrip): return 180
        case (.southAfrica, .airstrip): return 197
        }
    }

    func flightTimeFormatted(method: FlightMethod = .standard) -> String {
        let duration = flightTimeMinutes(method: method)
        let hours = duration / 60
        let minutes = duration % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    /// Look up flag emoji for a destination string, including non-enum values like "Torn"
    static func flag(for destination: String, hasPrivateIsland: Bool) -> String {
        if let known = TornDestination(rawValue: destination) {
            return known.flag
        }
        if destination.lowercased() == "torn" {
            return hasPrivateIsland ? "🏝️" : "🏠"
        }
        return "🌍"
    }
}
