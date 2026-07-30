import Foundation

// MARK: - Diagnostics (Etap F)
//
// A local, read-only health snapshot the user can inspect and copy when reporting an
// issue. Everything here is PII-safe *by construction*: it carries endpoint slugs,
// outcomes, latencies, byte counts, budget counters and OS/app versions — never the API
// key, full URLs, player name/ID, money, stats, faction/company names, or raw payloads.
// The "Copy sanitized diagnostic report" text is assembled only from these safe fields.

/// Outcome of the most recent call to an endpoint.
enum EndpointOutcome: String, Equatable, Hashable, Sendable {
    case ok
    case error
    case offline
    case cancelled
    case pending
}

/// The latest observed health of a single endpoint.
struct EndpointHealth: Equatable, Sendable {
    let endpointID: String
    var outcome: EndpointOutcome
    var latencyMs: Int
    var responseBytes: Int
    var at: Date
    /// A coarse `TornAPIError` classification string on failure (e.g. "rateLimit").
    /// Never the raw server message.
    var errorClass: String?
}

/// Records the most recent health of each endpoint. Time is injected so "age" is testable.
@MainActor
final class EndpointHealthTracker {
    private let time: TimeSource
    private(set) var health: [String: EndpointHealth] = [:]

    init(time: TimeSource = SystemTimeSource()) { self.time = time }

    func record(endpointID: String,
                outcome: EndpointOutcome,
                latencyMs: Int,
                responseBytes: Int,
                errorClass: String? = nil) {
        health[endpointID] = EndpointHealth(
            endpointID: endpointID,
            outcome: outcome,
            latencyMs: latencyMs,
            responseBytes: responseBytes,
            at: time.now,
            errorClass: errorClass
        )
    }

    func latest(for endpointID: String) -> EndpointHealth? { health[endpointID] }

    /// All tracked endpoints, ordered by the registry's display order.
    var all: [EndpointHealth] {
        TornEndpointRegistry.all.compactMap { health[$0.id] }
    }
}

// MARK: - Module presentation state

/// A compact, PII-free state shared by every feature screen. It deliberately keeps
/// "has cached content" separate from endpoint health so a transient failure can label
/// existing data as stale instead of replacing it with an empty error screen.
struct ModulePresentationState: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case loading
        case empty
        case fresh
        case stale
        case offline
        case permission
        case rateLimited
        case error
    }

    enum Recovery: Equatable, Sendable {
        case none
        case retry
        case settings
    }

    let kind: Kind
    let hasContent: Bool
    let updatedAt: Date?
    let recovery: Recovery

    static func resolve(health: [EndpointHealth],
                        hasContent: Bool,
                        isLoading: Bool,
                        fallbackError: String?,
                        now: Date = Date(),
                        staleAfter: TimeInterval) -> ModulePresentationState {
        if isLoading, !hasContent {
            return ModulePresentationState(kind: .loading, hasContent: false,
                                           updatedAt: newestDate(in: health), recovery: .none)
        }

        let updatedAt = newestDate(in: health)
        let errorClasses = Set(health.compactMap(\.errorClass))
        let outcomes = Set(health.map(\.outcome))

        if outcomes.contains(.offline) || fallbackError == "No internet connection" {
            return ModulePresentationState(kind: .offline, hasContent: hasContent,
                                           updatedAt: updatedAt, recovery: .retry)
        }
        if !errorClasses.isDisjoint(with: ["permanentKey", "insufficientPermissions"]) {
            return ModulePresentationState(kind: .permission, hasContent: hasContent,
                                           updatedAt: updatedAt, recovery: .settings)
        }
        if !errorClasses.isDisjoint(with: ["rateLimit", "dailyRowLimit"]) {
            return ModulePresentationState(kind: .rateLimited, hasContent: hasContent,
                                           updatedAt: updatedAt, recovery: .retry)
        }
        if outcomes.contains(.error) {
            return ModulePresentationState(kind: hasContent ? .stale : .error,
                                           hasContent: hasContent, updatedAt: updatedAt,
                                           recovery: .retry)
        }

        if let updatedAt, now.timeIntervalSince(updatedAt) > staleAfter {
            return ModulePresentationState(kind: .stale, hasContent: hasContent,
                                           updatedAt: updatedAt, recovery: .retry)
        }
        if hasContent {
            return ModulePresentationState(kind: .fresh, hasContent: true,
                                           updatedAt: updatedAt, recovery: .none)
        }
        if fallbackError != nil {
            return ModulePresentationState(kind: .error, hasContent: false,
                                           updatedAt: updatedAt, recovery: .retry)
        }
        return ModulePresentationState(kind: .empty, hasContent: false,
                                       updatedAt: updatedAt, recovery: .retry)
    }

    private static func newestDate(in health: [EndpointHealth]) -> Date? {
        health.map(\.at).max()
    }
}

extension AppState {
    /// Resolves a module's visible status from the same PII-safe endpoint health that
    /// powers Diagnostics. `staleAfter` is module-specific because activity/faction
    /// endpoints intentionally poll more slowly than live bars.
    func presentationState(endpointIDs: [String],
                           hasContent: Bool,
                           staleAfter: TimeInterval) -> ModulePresentationState {
        ModulePresentationState.resolve(
            health: endpointIDs.compactMap { endpointHealth.latest(for: $0) },
            hasContent: hasContent,
            isLoading: isLoading,
            fallbackError: errorMsg,
            staleAfter: staleAfter
        )
    }
}

// MARK: - Report

/// A point-in-time diagnostics snapshot. Constructed by `AppState.makeDiagnosticsReport()`;
/// rendered by `DiagnosticsView`; serialised by `sanitizedText()`.
struct DiagnosticsReport: Equatable {
    // Build / environment
    let appVersion: String
    let build: String
    let osVersion: String
    let architecture: String

    // Runtime
    let isOnline: Bool
    let notificationPermission: String
    let lastSuccessfulRefresh: Date?
    /// Coarse, non-PII summary of the last error (a `TornAPIError` classification or a
    /// short fixed message), never a raw server string.
    let lastErrorSummary: String?

    // Key (never the key itself)
    let keyPresent: Bool
    let requiredAccessLevel: String

    // Budget
    let requestsLastMinute: Int
    let requestsLastDay: Int
    let recordsPerDayByCategory: [String: Int]

    // Per-endpoint health
    let endpoints: [EndpointHealth]

    /// The "Copy sanitized diagnostic report" body. Contains only the safe fields above.
    func sanitizedText() -> String {
        var lines: [String] = []
        lines.append("MacTorn diagnostics")
        lines.append("===================")
        lines.append("App: \(appVersion) (\(build))")
        lines.append("macOS: \(osVersion)")
        lines.append("Arch: \(architecture)")
        lines.append("")
        lines.append("Network: \(isOnline ? "online" : "offline")")
        lines.append("Notifications: \(notificationPermission)")
        lines.append("API key configured: \(keyPresent ? "yes" : "no") (needs \(requiredAccessLevel))")
        lines.append("Last successful refresh: \(Self.format(lastSuccessfulRefresh))")
        if let lastErrorSummary { lines.append("Last error: \(lastErrorSummary)") }
        lines.append("")
        lines.append("Requests: \(requestsLastMinute)/min, \(requestsLastDay)/day")
        if recordsPerDayByCategory.isEmpty {
            lines.append("Records/day: none")
        } else {
            lines.append("Records/day per category:")
            for key in recordsPerDayByCategory.keys.sorted() {
                lines.append("  \(key): \(recordsPerDayByCategory[key]!)")
            }
        }
        lines.append("")
        lines.append("Endpoints:")
        if endpoints.isEmpty {
            lines.append("  (none called yet)")
        } else {
            for e in endpoints {
                let err = e.errorClass.map { " [\($0)]" } ?? ""
                lines.append("  \(e.endpointID): \(e.outcome.rawValue) \(e.latencyMs)ms \(e.responseBytes)B\(err)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func format(_ date: Date?) -> String {
        guard let date else { return "never" }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }
}

// MARK: - Environment probes (non-PII)

enum DiagnosticsEnvironment {
    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }
    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
    }
    static var osVersion: String {
        ProcessInfo.processInfo.operatingSystemVersionString
    }
    static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }
}
