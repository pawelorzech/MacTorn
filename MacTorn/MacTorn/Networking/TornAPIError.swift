import Foundation

// MARK: - Torn API Error Taxonomy (Etap B)
//
// Torn returns application errors with HTTP 200 and a code/message envelope. This
// type classifies both those Torn codes and transport-level failures into a small,
// actionable set so callers can react correctly instead of treating every failure
// the same:
//
//   • permanentKey → STOP every request until the user edits their key. Only the
//     three codes where that is literally true (1 empty, 2 incorrect, 18 paused by
//     the owner). Retrying those forever is pointless and looks like a hang.
//   • temporaryKey → the key is fine but Torn is refusing it *for now* (owner in
//     federal jail, key-change cooldown, read error, temporarily disabled). These
//     clear on their own, so polling pauses and resumes automatically instead of
//     sending the user off to regenerate a perfectly good key.
//   • insufficientPermissions → the key's access level cannot serve this selection.
//     Permanent for that endpoint, but the rest of the app keeps running.
//   • endpointUnavailable → the request as constructed can never succeed (wrong API
//     version, wrong category, a deleted thread/item id, an unmigrated crime
//     selection). Disable that one endpoint; retrying is a guaranteed 100% failure.
//   • ipBlocked → Torn blocked this IP for abuse. A normal poll-cadence retry makes
//     it worse, so this gets its own long cool-off.
//   • dailyRowLimit → pause ONLY the row-based category that tripped it (error 14),
//     while bars/cooldowns/countdowns keep running.
//   • rateLimit / temporaryBackend / offline / transport → surfaced to the UI; no
//     built-in retry layer. At the app's 15-120s poll cadence the next timer tick
//     recovers on its own, and a second retry layer would double traffic in an app
//     that guards its Torn API budget.
//   • malformed / cancelled → non-retryable, not the server's fault.
//
// Codes are the 0-31 set published in Torn's OpenAPI document
// (https://www.torn.com/swagger/openapi.json — `components.schemas.Error*`), verified
// against spec version 6.13.1 on 2026-08-26.

/// Coarse classification used for UI copy and retry decisions.
enum TornErrorClass: String, Equatable, Sendable {
    case permanentKey
    case temporaryKey
    case insufficientPermissions
    case endpointUnavailable
    case ipBlocked
    case rateLimit
    case dailyRowLimit
    case temporaryBackend
    case offline
    case transport
    case malformedResponse
    case cancelled
}

enum TornAPIError: Error, Equatable, Sendable {
    /// Key will not work until the user changes it: empty key, incorrect key, or a key
    /// the owner paused. Torn codes 1, 2, 18.
    case permanentKey(code: Int, message: String)
    /// Key is structurally fine but Torn is refusing it right now and will stop:
    /// 10 (owner in federal jail), 11 (key-change cooldown), 12 (key read error),
    /// 13 (temporarily disabled). Polling pauses and retries after `retryAfter`.
    case temporaryKey(code: Int, message: String)
    /// The key is valid but its access level is too low for a requested selection.
    /// Torn code 16.
    case insufficientPermissions(code: Int, message: String)
    /// This request can never succeed as constructed — wrong API version for the
    /// selection, wrong category, an id that does not exist, or a selection that has
    /// been migrated away. Torn codes 6, 7, 19, 21, 22, 23, 25, 26, 27, 28, 29, 30.
    case endpointUnavailable(code: Int, message: String)
    /// Torn blocked this IP address (code 8). Needs a long cool-off, not a poll retry.
    case ipBlocked(code: Int, message: String)
    /// Too many requests per minute. Torn code 5.
    case rateLimit(code: Int, message: String)
    /// The per-category 50,000-rows/day cloud-data cap. Torn code 14. Pause only the
    /// offending category, not the whole app.
    case dailyRowLimit(code: Int, message: String)
    /// Transient server-side failure — retry with backoff. Torn codes 0, 9, 15, 17, 24, 31.
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
        case .temporaryKey: return .temporaryKey
        case .insufficientPermissions: return .insufficientPermissions
        case .endpointUnavailable: return .endpointUnavailable
        case .ipBlocked: return .ipBlocked
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
             let .temporaryKey(code, _),
             let .insufficientPermissions(code, _),
             let .endpointUnavailable(code, _),
             let .ipBlocked(code, _),
             let .rateLimit(code, _),
             let .dailyRowLimit(code, _),
             let .temporaryBackend(code, _):
            return code
        case .offline, .transport, .malformedResponse, .cancelled:
            return nil
        }
    }

    /// A key/permission problem that should halt *all* affected requests until the
    /// user fixes their key. Only the three genuinely permanent key codes plus
    /// access-level-too-low qualify — everything self-healing goes through
    /// `pauseDuration` instead, so a spell in federal jail no longer looks to the
    /// user like a broken key.
    var haltsAllRequests: Bool {
        classification == .permanentKey || classification == .insufficientPermissions
    }

    /// A daily-row-limit hit (error 14) halts only the row-based category that tripped
    /// it, leaving point-in-time polling (bars, countdowns) alive.
    var haltsCategoryOnly: Bool {
        classification == .dailyRowLimit
    }

    /// Whether this error means the *specific endpoint* is unusable but the rest of the
    /// app is fine — so the caller should stop calling that one endpoint rather than
    /// stop the app or keep retrying a request that cannot ever succeed.
    var disablesEndpoint: Bool {
        classification == .endpointUnavailable || classification == .insufficientPermissions
    }

    /// How long to stay quiet before trying again, for the self-healing failures.
    /// `nil` means "no special pause — the normal poll cadence is the retry".
    ///
    /// The values are deliberately coarse. Torn does not publish a clear-at time for
    /// any of these, so each is set to the shortest interval that is unambiguously
    /// polite: long enough that a stuck condition is not hammered, short enough that
    /// the app recovers on its own well within one sitting.
    var pauseDuration: TimeInterval? {
        switch self {
        case .temporaryKey:
            return 600      // 10 min — federal jail / key cooldown outlive a poll tick.
        case .ipBlocked:
            return 3600     // 1 h — retrying an IP block is what caused it.
        case .dailyRowLimit:
            return 3600     // 1 h — the cap is daily; re-probe hourly, cheaply.
        case .rateLimit:
            return 60       // 1 min — the per-minute window has to roll over.
        case .permanentKey, .insufficientPermissions, .endpointUnavailable,
             .temporaryBackend, .offline, .transport, .malformedResponse, .cancelled:
            return nil
        }
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
        case let .temporaryKey(code, _):
            switch code {
            case 10: return "API access is paused while you're in federal jail — retrying later."
            case 11: return "Torn is holding your recently changed key — retrying later."
            default: return "Torn has temporarily disabled this key — retrying later."
            }
        case let .insufficientPermissions(_, message):
            return sanitized(message.isEmpty ? "Your API key's access level is too low for this data." : message)
        case .endpointUnavailable:
            return "Torn no longer serves this data the way MacTorn asked for it."
        case .ipBlocked:
            return "Torn has temporarily blocked this network — pausing for an hour."
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

    /// Same rule as `NotificationManager.sanitize`, and for the same reason: these
    /// messages can be Torn's own string verbatim, they render in the error bar of three
    /// views, and `CharacterSet.controlCharacters` alone lets U+2028/U+2029 through as
    /// hard line breaks. See the note on `NotificationManager.lineBreakingCharacters`.
    private func sanitized(_ text: String) -> String {
        let stripped = text.unicodeScalars
            .filter { !NotificationManager.lineBreakingCharacters.contains($0) }
            .map(Character.init)
        return String(String(stripped).prefix(120))
    }

    // MARK: - Classification

    /// Maps a Torn application error code + message to a typed error.
    ///
    /// Every code below is named in Torn's own OpenAPI document; an unknown/new code
    /// falls through to `.temporaryBackend` so a future Torn addition degrades into
    /// "retry later" rather than into a hard stop.
    static func classify(code: Int, message: String) -> TornAPIError {
        switch code {
        case 1, 2, 18:
            // 1 key empty, 2 incorrect key, 18 key paused by its owner.
            return .permanentKey(code: code, message: message)
        case 10, 11, 12, 13:
            // 10 owner in federal jail, 11 key-change cooldown, 12 key read error,
            // 13 key temporarily disabled. All clear without the user touching a thing.
            return .temporaryKey(code: code, message: message)
        case 16:
            return .insufficientPermissions(code: code, message: message)
        case 6, 7, 19, 21, 22, 23, 25, 26, 27, 28, 29, 30:
            // 6 incorrect id, 7 id/entity mismatch, 19 must migrate to Crimes v2,
            // 21 incorrect category, 22 v1-only selection, 23 v2-only selection,
            // 25 invalid stat, 26 category-or-stats only, 27 must migrate to OC v2,
            // 28 incorrect log id, 29 category unavailable for interaction logs,
            // 30 file does not exist. All are "this request is wrong", not "try again".
            return .endpointUnavailable(code: code, message: message)
        case 8:
            return .ipBlocked(code: code, message: message)
        case 5:
            return .rateLimit(code: code, message: message)
        case 14:
            return .dailyRowLimit(code: code, message: message)
        default:
            // 0 (unknown), 9 (API disabled), 15 (log unavailable), 17 (backend),
            // 24 (closed temporarily), 31 (city-stats cron) and any future code
            // default to transient so the client retries rather than giving up.
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
