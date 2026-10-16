import Foundation
import Observation

// MARK: - Diagnostics (Etap F)
//
// A local, read-only health snapshot the user can inspect and copy when reporting an
// issue. Everything here is PII-safe *by construction*: it carries endpoint slugs,
// outcomes, latencies, byte counts, budget counters and OS/app versions — never the API
// key, full URLs, player name/ID, money, stats, faction/company names, or raw payloads.
// The "Copy sanitized diagnostic report" text is assembled only from these safe fields.
//
// NOTE on "sanitized" — this word is used with two different meanings in the codebase,
// which is exactly the confusion issue #58 was filed about:
//   • `TornAPIError.sanitized(_:)` (Networking/TornAPIError.swift) means *string hygiene*:
//     no control characters, capped at 120 chars. It says nothing about content — the
//     result can still be the Torn server's own message, verbatim.
//   • "Sanitized" here means *safe by construction*: every field on `DiagnosticsReport`
//     is either a closed-vocabulary classification, a count, a bool, or an app-owned
//     constant — never a hygiene-cleaned copy of free-text server output. In particular
//     `lastErrorSummary` is a `TornErrorClass` raw value (or `nil`), never `errorMsg`'s
//     free text, which for some error kinds carries the Torn server's own string.

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
    var lastSuccessfulAt: Date? = nil

    var dataUpdatedAt: Date? {
        lastSuccessfulAt ?? (outcome == .ok ? at : nil)
    }
}

/// Records the most recent health of each endpoint. Time is injected so "age" is testable.
@MainActor
@Observable
final class EndpointHealthTracker {
    @ObservationIgnored private let time: TimeSource
    private(set) var health: [String: EndpointHealth] = [:]

    init(time: TimeSource = SystemTimeSource()) { self.time = time }

    func record(endpointID: String,
                outcome: EndpointOutcome,
                latencyMs: Int,
                responseBytes: Int,
                errorClass: String? = nil) {
        let successfulAt = outcome == .ok ? time.now : health[endpointID]?.dataUpdatedAt
        health[endpointID] = EndpointHealth(
            endpointID: endpointID,
            outcome: outcome,
            latencyMs: latencyMs,
            responseBytes: responseBytes,
            at: time.now,
            errorClass: errorClass,
            lastSuccessfulAt: successfulAt
        )
    }

    func latest(for endpointID: String) -> EndpointHealth? { health[endpointID] }

    func reset() { health.removeAll(keepingCapacity: true) }

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
        if fallbackError == "No internet connection" {
            return ModulePresentationState(kind: .offline, hasContent: hasContent,
                                           updatedAt: newestDate(in: health), recovery: .retry)
        }
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
                                       updatedAt: updatedAt, recovery: outcomes.contains(.ok) ? .none : .retry)
    }

    private static func newestDate(in health: [EndpointHealth]) -> Date? {
        health.compactMap(\.dataUpdatedAt).max()
    }
}

extension AppState {
    /// Resolves a module's visible status from the same PII-safe endpoint health that
    /// powers Diagnostics. `staleAfter` is module-specific because activity/faction
    /// endpoints intentionally poll more slowly than live bars.
    func presentationState(endpointIDs: [String],
                           hasContent: Bool,
                           staleAfter: TimeInterval,
                           requiredUserSelections: [String] = [],
                           rowHealth: [EndpointHealth]? = nil) -> ModulePresentationState {
        let health = rowHealth ?? endpointIDs.compactMap { endpointHealth.latest(for: $0) }

        // A permanent key failure is account-wide. The failing request may be
        // `key.info`, while a feature screen observes only its own endpoint (for
        // example `user.fast`). Keep every module's recovery action honest: retrying
        // cannot help until the key is changed, so route the user to Settings.
        if keyHalted {
            return ModulePresentationState(
                kind: .permission,
                hasContent: hasContent,
                updatedAt: health.compactMap(\.dataUpdatedAt).max(),
                recovery: .settings
            )
        }

        if let keyInfo, !Set(requiredUserSelections).isSubset(of: Set(keyInfo.selections.user)) {
            return ModulePresentationState(kind: .permission, hasContent: hasContent,
                                           updatedAt: health.compactMap(\.dataUpdatedAt).max(), recovery: .settings)
        }

        // A suppressed endpoint has no failed response to put in health. Show known
        // permission denials on the module itself rather than an endless "No data yet".
        if !hasContent {
            for id in endpointIDs {
                let denial = endpointGate.denial(for: id, keyInfo: keyInfo, coordinator: pollingCoordinator)
                switch denial {
                case .keyLacksSelections, .keyAccessLevelTooLow, .factionAPIAccessDisabled:
                    return ModulePresentationState(kind: .permission, hasContent: false,
                                                   updatedAt: nil, recovery: .settings)
                default: break
                }
            }
        }

        return ModulePresentationState.resolve(
            health: health,
            hasContent: hasContent,
            isLoading: isLoading || awaitingFirstKeyInfo,
            fallbackError: connectivity.isConnected ? errorMsg : "No internet connection",
            now: time.now,
            staleAfter: staleAfter
        )
    }

    var watchlistPresentationState: ModulePresentationState {
        presentationState(endpointIDs: ["market.item"],
                          hasContent: watchlistItems.contains { $0.lastUpdated != nil }, staleAfter: 360,
                          rowHealth: watchlistItems.map {
            EndpointHealth(endpointID: "market.item", outcome: $0.error != nil ? .error : $0.lastUpdated == nil ? .pending : .ok,
                           latencyMs: 0, responseBytes: 0, at: $0.lastUpdated ?? time.now,
                           errorClass: nil, lastSuccessfulAt: $0.lastUpdated)
        })
    }

    var forumPresentationState: ModulePresentationState {
        presentationState(endpointIDs: ["forum.thread"],
                          hasContent: watchedThreads.contains { $0.lastChecked != nil },
                          staleAfter: TimeInterval(max(forumWatchConfig.pollingIntervalSeconds, 180)) + 30,
                          rowHealth: watchedThreads.map {
            EndpointHealth(endpointID: "forum.thread", outcome: $0.error != nil ? .error : $0.lastChecked == nil ? .pending : .ok,
                           latencyMs: 0, responseBytes: 0, at: $0.lastChecked ?? time.now,
                           errorClass: nil, lastSuccessfulAt: $0.lastChecked)
        })
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
    /// Coarse, non-PII summary of the last error: a `TornErrorClass` raw value (e.g.
    /// `"rateLimit"`), or `nil`. NEVER a raw server string, and never free text from
    /// `AppState.errorMsg` — see `AppState.lastErrorClassificationSummary()`, the only
    /// producer of this field, and the "sanitized" note at the top of this file
    /// (issue #58).
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

    /// Endpoints the gate is currently holding back, and why: endpoint id → the reason's
    /// `TornEndpointDenial.label`.
    ///
    /// Safe by construction, like every other field here. Denial labels come from a closed
    /// vocabulary of classifications and selection *names* — never a server message, never
    /// a key, never anything the user typed. This is the field that answers the support
    /// question "why is my faction tab empty?" without anyone having to read a log.
    let suppressedEndpoints: [String: String]

    /// The same suppressions in plain words, for the on-screen panel. Not included in the
    /// copied report: the machine labels above are the stable vocabulary worth pasting into
    /// an issue, and repeating each reason twice would only make the paste longer.
    let suppressionExplanations: [String: String]

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
        if suppressedEndpoints.isEmpty {
            lines.append("Suppressed endpoints: none")
        } else {
            lines.append("Suppressed endpoints:")
            for key in suppressedEndpoints.keys.sorted() {
                lines.append("  \(key): \(suppressedEndpoints[key]!)")
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
