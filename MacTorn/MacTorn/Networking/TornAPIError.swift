import Foundation

// MARK: - Torn API Error Taxonomy (Etap B)
//
// Torn returns application errors with HTTP 200 and a code/message envelope. This
// type classifies both those Torn codes and transport-level failures into a small,
// actionable set so callers can react correctly instead of treating every failure
// the same:
//
//   • permanentKey / insufficientPermissions → STOP the affected requests. Retrying
//     an incorrect/paused key or an under-privileged selection forever is pointless
//     and looks like a hang. (Etap C: codes 2, 16, 18.)
//   • dailyRowLimit → pause ONLY the row-based category that tripped it (error 14),
//     while bars/cooldowns/countdowns keep running.
//   • rateLimit / temporaryBackend / offline / transport → surfaced to the UI; no
//     built-in retry layer. At the app's 15-120s poll cadence the next timer tick
//     recovers on its own, and a second retry layer would double traffic in an app
//     that guards its Torn API budget.
//   • malformed / cancelled → non-retryable, not the server's fault.
//
// Reference: Torn API error codes (https://www.torn.com/swagger — "Common errors").

/// Coarse classification used for UI copy and retry decisions.
enum TornErrorClass: String, Equatable, Sendable {
    case permanentKey
    case insufficientPermissions
    case rateLimit
    case dailyRowLimit
    case temporaryBackend
    case offline
    case transport
    case malformedResponse
    case cancelled
}

enum TornAPIError: Error, Equatable, Sendable {
    /// Key will not work until the user changes it: incorrect key, empty key, key
    /// paused/disabled by the owner. Torn codes 1, 2, 10, 11, 12, 13, 18.
    case permanentKey(code: Int, message: String)
    /// The key is valid but its access level is too low for a requested selection.
    /// Torn code 16.
    case insufficientPermissions(code: Int, message: String)
    /// Too many requests per minute. Torn code 5.
    case rateLimit(code: Int, message: String)
    /// The per-category 50,000-rows/day cloud-data cap. Torn code 14. Pause only the
    /// offending category, not the whole app.
    case dailyRowLimit(code: Int, message: String)
    /// Transient server-side failure — retry with backoff. Torn codes 0, 8, 9, 15, 17, 24.
    case temporaryBackend(code: Int, message: String)
    /// Device is offline (no path to the network).
    case offline
    /// Other transport failure (timeout, DNS, TLS…). `detail` is a non-PII summary.
    case transport(detail: String)
    /// Response could not be decoded into the expected shape.
    case malformedResponse(detail: String)
    /// Request was cancelled (superseded poll, app teardown).
    case cancelled

    var classification: TornErrorClass {
        switch self {
        case .permanentKey: return .permanentKey
        case .insufficientPermissions: return .insufficientPermissions
        case .rateLimit: return .rateLimit
        case .dailyRowLimit: return .dailyRowLimit
        case .temporaryBackend: return .temporaryBackend
        case .offline: return .offline
        case .transport: return .transport
        case .malformedResponse: return .malformedResponse
        case .cancelled: return .cancelled
        }
    }

    /// The Torn application error code, when this originated from an API envelope.
    var tornCode: Int? {
        switch self {
        case let .permanentKey(code, _),
             let .insufficientPermissions(code, _),
             let .rateLimit(code, _),
             let .dailyRowLimit(code, _),
             let .temporaryBackend(code, _):
            return code
        case .offline, .transport, .malformedResponse, .cancelled:
            return nil
        }
    }

    /// A key/permission problem that should halt *all* affected requests until the
    /// user fixes their key (Etap C: codes 2, 16, 18). Prevents an infinite loop of
    /// doomed requests.
    var haltsAllRequests: Bool {
        classification == .permanentKey || classification == .insufficientPermissions
    }

    /// A daily-row-limit hit (error 14) halts only the row-based category that tripped
    /// it, leaving point-in-time polling (bars, countdowns) alive.
    var haltsCategoryOnly: Bool {
        classification == .dailyRowLimit
    }

    /// Short, PII-safe message for the UI. The underlying Torn message is a fixed
    /// server string, but it is still sanitized (control chars stripped, length
    /// capped) so a MITM'd/compromised response cannot inject multi-line UI.
    ///
    /// NOTE on "sanitized": `sanitized(_:)` below only means *string-hygiene* — no
    /// control characters, capped at 120 chars — as a defence against UI spoofing.
    /// It says nothing about the *content* of the string: for `.permanentKey`,
    /// `.insufficientPermissions` and `.temporaryBackend` this can still be the raw
    /// Torn server message verbatim (hygiene-cleaned, not classification-only). That
    /// is a different, stricter guarantee from `DiagnosticsReport`'s use of
    /// "sanitized" (see `Diagnostics.swift`), which means "built only from fields
    /// that are safe by construction" — free-text `userMessage` values are exactly
    /// what `DiagnosticsReport.lastErrorSummary` must NOT carry (issue #58).
    var userMessage: String {
        switch self {
        case let .permanentKey(_, message):
            return sanitized(message.isEmpty ? "Your API key is invalid or paused. Update it in Settings." : message)
        case let .insufficientPermissions(_, message):
            return sanitized(message.isEmpty ? "Your API key's access level is too low for this data." : message)
        case .rateLimit:
            return "Too many requests — backing off."
        case .dailyRowLimit:
            return "Daily read limit reached for this category — it will resume tomorrow."
        case let .temporaryBackend(_, message):
            return sanitized(message.isEmpty ? "Torn API is temporarily unavailable — retrying." : message)
        case .offline:
            return "You're offline — waiting for a connection."
        case .transport:
            return "Network error — retrying."
        case .malformedResponse:
            return "Unexpected response from Torn."
        case .cancelled:
            return "Request cancelled."
        }
    }

    private func sanitized(_ text: String) -> String {
        let stripped = text.unicodeScalars
            .filter { !CharacterSet.controlCharacters.contains($0) }
            .map(Character.init)
        return String(String(stripped).prefix(120))
    }

    // MARK: - Classification

    /// Maps a Torn application error code + message to a typed error.
    static func classify(code: Int, message: String) -> TornAPIError {
        switch code {
        case 1, 2, 10, 11, 12, 13, 18:
            return .permanentKey(code: code, message: message)
        case 16:
            return .insufficientPermissions(code: code, message: message)
        case 5:
            return .rateLimit(code: code, message: message)
        case 14:
            return .dailyRowLimit(code: code, message: message)
        default:
            // 0 (unknown), 8 (IP block), 9 (API disabled), 15 (temporary), 17 (backend),
            // 24 (closed temporarily) and any other/new code default to transient so the
            // client retries rather than silently giving up.
            return .temporaryBackend(code: code, message: message)
        }
    }

    /// Maps a URLSession transport error to a typed error.
    static func from(urlError: URLError) -> TornAPIError {
        switch urlError.code {
        case .cancelled:
            return .cancelled
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            return .offline
        default:
            return .transport(detail: urlError.code.rawValue.description)
        }
    }
}
