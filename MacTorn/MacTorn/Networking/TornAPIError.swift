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
//     Refresh `/key/info`, narrow the request and retry once; never invalidate the key.
//   • endpointUnavailable → the request as constructed can never succeed (wrong API
//     version, wrong category, a deleted thread/item id, an unmigrated crime
//     selection). Disable that one endpoint; retrying is a guaranteed 100% failure.
//   • ipBlocked → Torn blocked this IP for abuse. A normal poll-cadence retry makes
//     it worse, so this gets its own long cool-off.
//   • dailyRowLimit → pause ONLY the row-based category that tripped it (error 14),
//     while bars/cooldowns/countdowns keep running.
//   • rateLimit → a one-minute account-wide pause, because Torn applies code 5 per user
//     across every key and endpoint.
//   • temporaryBackend / offline / transport → surfaced to the UI; the normal poll
//     cadence is the retry, avoiding a second traffic-amplifying retry layer.
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
    /// This request can never succeed as constructed — wrong fields/type/API version,
    /// wrong category, an id that does not exist, or a migrated selection. Torn codes
    /// 3, 4, 6, 7, 19, 21, 22, 23, 25, 26, 27, 28, 29, 30.
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

    /// A key problem that should halt *all* requests until the user changes the key.
    /// Only the three genuinely permanent key codes qualify; code 16 refreshes
    /// capabilities and retries a narrowed request instead.
    var haltsAllRequests: Bool {
        classification == .permanentKey
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
        classification == .endpointUnavailable
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
        case .endpointUnavailable:
            // Not a retry interval so much as a re-probe. These cannot succeed as
            // constructed, so the cool-off exists to stop the request rather than to wait
            // out a condition: a deleted forum thread or a bad item id would otherwise be
            // re-requested every poll, indefinitely. Long enough to be effectively "off",
            // short enough that fixing the key or the id recovers within a sitting.
            return 3600
        case .temporaryKey:
            return 600      // 10 min — federal jail / key cooldown outlive a poll tick.
        case .ipBlocked:
            return 3600     // 1 h — retrying an IP block is what caused it.
        case .dailyRowLimit:
            return 3600     // 1 h — the cap is daily; re-probe hourly, cheaply.
        case .rateLimit:
            return 60       // 1 min — the per-minute window has to roll over.
        case .permanentKey, .insufficientPermissions, .temporaryBackend, .offline, .transport,
             .malformedResponse, .cancelled:
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
        text.sanitizedForDisplay()
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
        case 3, 4, 6, 7, 19, 21, 22, 23, 25, 26, 27, 28, 29, 30:
            // 3 wrong type, 4 wrong fields, 6 incorrect id, 7 id/entity mismatch,
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

// MARK: - Display sanitising

extension String {
    /// Strips Unicode control *and* format characters plus line breaks, and caps the length.
    ///
    /// `CharacterSet.controlCharacters` covers categories Cc and Cf, so this removes bidi
    /// overrides (U+202A–202E, U+2066–2069) and zero-width characters along with the usual
    /// C0/C1 controls — the pieces used to build text that reads as something other than
    /// what it is, on screen or through VoiceOver. It is *not* enough on its own: U+2028
    /// LINE SEPARATOR and U+2029 PARAGRAPH SEPARATOR are categories Zl/Zp and still render
    /// as hard line breaks, which is how a forum title can fake a second MacTorn-authored
    /// paragraph. `NotificationManager.lineBreakingCharacters` unions in `.newlines` to
    /// close that hole, and stays the single source of truth for both callers.
    ///
    /// Apply to every string reaching the UI from a source we do not control: Torn's own
    /// error messages, and event text that another player can influence.
    func sanitizedForDisplay(limit: Int = 120) -> String {
        let stripped = unicodeScalars
            .filter { !NotificationManager.lineBreakingCharacters.contains($0) || $0 == .emojiJoiner }
            .map(Character.init)
        // `prefix(_:)` has a precondition of maxLength >= 0 and traps below it. No caller
        // passes a negative today — the three are 80, 200 and the 120 default — but this is
        // a shared helper on String now, so a future caller computing a limit gets an empty
        // string rather than a crash.
        return String(String(stripped).prefix(max(0, limit)))
    }
}

extension Unicode.Scalar {
    /// U+200D ZERO WIDTH JOINER.
    ///
    /// It is category Cf, so `CharacterSet.controlCharacters` matches it — but it is also
    /// the glue in every emoji ZWJ sequence, and dropping it decomposes one grapheme into
    /// several: 👨‍👩‍👧 becomes three separate people, 🏳️‍🌈 becomes a white flag beside a
    /// rainbow. That is visible corruption of legitimate content.
    ///
    /// Keeping it is a deliberately narrow exception. ZWJ only asks that adjacent glyphs be
    /// joined: unlike the bidi overrides it cannot reorder text, and unlike U+200B ZERO
    /// WIDTH SPACE — which stays stripped — it is not the character used to split a word
    /// invisibly. Variation selectors (U+FE0F) and the keycap mark (U+20E3) need no
    /// exception; they are in neither Cc nor Cf and were never removed.
    static let emojiJoiner = Unicode.Scalar(0x200D)!
}
