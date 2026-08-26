import XCTest
@testable import MacTorn

/// Etap F — the health tracker and the PII-safety of the sanitized report.
@MainActor
final class DiagnosticsTests: XCTestCase {

    // MARK: EndpointHealthTracker

    func testTrackerRecordsAndReturnsLatest() {
        let clock = MutableTimeSource()
        let tracker = EndpointHealthTracker(time: clock)
        tracker.record(endpointID: "user.fast", outcome: .ok, latencyMs: 120, responseBytes: 8000)
        let h = tracker.latest(for: "user.fast")
        XCTAssertEqual(h?.outcome, .ok)
        XCTAssertEqual(h?.latencyMs, 120)
        XCTAssertEqual(h?.responseBytes, 8000)
    }

    func testTrackerOverwritesWithMostRecent() {
        let tracker = EndpointHealthTracker(time: MutableTimeSource())
        tracker.record(endpointID: "user.fast", outcome: .ok, latencyMs: 100, responseBytes: 1000)
        tracker.record(endpointID: "user.fast", outcome: .error, latencyMs: 50, responseBytes: 0, errorClass: "rateLimit")
        XCTAssertEqual(tracker.latest(for: "user.fast")?.outcome, .error)
        XCTAssertEqual(tracker.latest(for: "user.fast")?.errorClass, "rateLimit")
    }

    func testTrackerAllIsRegistryOrdered() {
        let tracker = EndpointHealthTracker(time: MutableTimeSource())
        // Record out of registry order.
        tracker.record(endpointID: "faction.basic", outcome: .ok, latencyMs: 1, responseBytes: 1)
        tracker.record(endpointID: "user.fast", outcome: .ok, latencyMs: 1, responseBytes: 1)
        XCTAssertEqual(tracker.all.map(\.endpointID), ["user.fast", "faction.basic"])
    }

    // MARK: Report sanitization (the security-critical part)

    private func sampleReport() -> DiagnosticsReport {
        DiagnosticsReport(
            appVersion: "1.9.2", build: "1", osVersion: "Version 14.5", architecture: "arm64",
            isOnline: true, notificationPermission: "authorized",
            lastSuccessfulRefresh: Date(timeIntervalSince1970: 1_700_000_000),
            lastErrorSummary: "rateLimit",
            keyPresent: true, requiredAccessLevel: "Limited Access",
            requestsLastMinute: 3, requestsLastDay: 200,
            recordsPerDayByCategory: ["activity": 300, "faction": 150],
            endpoints: [
                EndpointHealth(endpointID: "user.fast", outcome: .ok, latencyMs: 120, responseBytes: 8000, at: Date(), errorClass: nil)
            ],
            suppressedEndpoints: ["faction.basic": "notInFaction"],
            suppressionExplanations: ["faction.basic": "You are not in a faction"]
        )
    }

    /// The report answers "why is my faction tab empty?" without anyone reading a log.
    func testSanitizedTextNamesSuppressedEndpointsAndTheirReason() {
        let text = sampleReport().sanitizedText()
        XCTAssertTrue(text.contains("faction.basic: notInFaction"))
    }

    /// The copied report carries the machine labels only. The plain-words version is for
    /// the screen; duplicating it would make an issue paste longer without adding anything.
    func testSanitizedTextCarriesTheMachineLabelNotThePlainWordsVersion() {
        let text = sampleReport().sanitizedText()
        XCTAssertTrue(text.contains("notInFaction"))
        XCTAssertFalse(text.contains("You are not in a faction"))
    }

    func testSanitizedTextSaysSoWhenNothingIsSuppressed() {
        let report = DiagnosticsReport(
            appVersion: "1.9.2", build: "1", osVersion: "Version 14.5", architecture: "arm64",
            isOnline: true, notificationPermission: "authorized",
            lastSuccessfulRefresh: nil, lastErrorSummary: nil,
            keyPresent: true, requiredAccessLevel: "Limited Access",
            requestsLastMinute: 0, requestsLastDay: 0,
            recordsPerDayByCategory: [:], endpoints: [], suppressedEndpoints: [:],
            suppressionExplanations: [:]
        )
        XCTAssertTrue(report.sanitizedText().contains("Suppressed endpoints: none"))
    }

    /// The report must never contain the API key, a player name/ID, money, or a raw URL —
    /// even when those exist in the app. It only carries the safe fields it was built from.
    func testSanitizedTextExcludesSecretsAndPII() {
        let secretKey = "exampleKey123456"
        let playerName = "SomePlayer"
        let text = sampleReport().sanitizedText()
        XCTAssertFalse(text.contains(secretKey), "must not leak the API key")
        XCTAssertFalse(text.contains(playerName), "must not leak player name")
        XCTAssertFalse(text.contains("api.torn.com"), "must not include full URLs / host with key")
        XCTAssertFalse(text.lowercased().contains("key="), "must not include a key query param")
    }

    func testSanitizedTextIncludesTheExpectedSafeFields() {
        let text = sampleReport().sanitizedText()
        XCTAssertTrue(text.contains("App: 1.9.2 (1)"))
        XCTAssertTrue(text.contains("Arch: arm64"))
        XCTAssertTrue(text.contains("Notifications: authorized"))
        XCTAssertTrue(text.contains("API key configured: yes"))
        XCTAssertTrue(text.contains("3/min"))
        XCTAssertTrue(text.contains("activity: 300"))
        XCTAssertTrue(text.contains("user.fast: ok 120ms 8000B"))
    }

    func testKeyNeverAppearsEvenWhenPresent() {
        // keyPresent is a Bool — the report has no field that could hold the key value.
        let text = sampleReport().sanitizedText()
        XCTAssertTrue(text.contains("API key configured: yes"))
        // The word "key" appears only in the label, never followed by an actual secret.
        XCTAssertFalse(text.contains("exampleKey"))
    }

    func testEnvironmentProbesAreNonEmpty() {
        XCTAssertFalse(DiagnosticsEnvironment.appVersion.isEmpty)
        XCTAssertFalse(DiagnosticsEnvironment.osVersion.isEmpty)
        XCTAssertTrue(["arm64", "x86_64", "unknown"].contains(DiagnosticsEnvironment.architecture))
    }

    // MARK: Module presentation state

    func testModuleStateKeepsCachedContentVisibleOnError() {
        let now = Date(timeIntervalSince1970: 2_000)
        let state = ModulePresentationState.resolve(
            health: [
                EndpointHealth(endpointID: "user.fast", outcome: .error, latencyMs: 10,
                               responseBytes: 0, at: now, errorClass: "temporaryBackend")
            ],
            hasContent: true, isLoading: false, fallbackError: nil,
            now: now, staleAfter: 120
        )

        XCTAssertEqual(state.kind, .stale)
        XCTAssertTrue(state.hasContent)
        XCTAssertEqual(state.recovery, .retry)
    }

    func testModuleStateRoutesPermissionFailureToSettings() {
        let now = Date(timeIntervalSince1970: 2_000)
        let state = ModulePresentationState.resolve(
            health: [
                EndpointHealth(endpointID: "faction.basic", outcome: .error, latencyMs: 10,
                               responseBytes: 0, at: now, errorClass: "insufficientPermissions")
            ],
            hasContent: false, isLoading: false, fallbackError: nil,
            now: now, staleAfter: 120
        )

        XCTAssertEqual(state.kind, .permission)
        XCTAssertEqual(state.recovery, .settings)
    }

    func testModuleStateMarksOldSuccessfulDataStale() {
        let now = Date(timeIntervalSince1970: 2_000)
        let state = ModulePresentationState.resolve(
            health: [
                EndpointHealth(endpointID: "user.fast", outcome: .ok, latencyMs: 10,
                               responseBytes: 100, at: now.addingTimeInterval(-121), errorClass: nil)
            ],
            hasContent: true, isLoading: false, fallbackError: nil,
            now: now, staleAfter: 120
        )

        XCTAssertEqual(state.kind, .stale)
        XCTAssertEqual(state.updatedAt, now.addingTimeInterval(-121))
    }

    func testModuleStateDistinguishesLoadingEmptyAndFresh() {
        let now = Date(timeIntervalSince1970: 2_000)
        let loading = ModulePresentationState.resolve(
            health: [], hasContent: false, isLoading: true, fallbackError: nil,
            now: now, staleAfter: 120
        )
        let empty = ModulePresentationState.resolve(
            health: [], hasContent: false, isLoading: false, fallbackError: nil,
            now: now, staleAfter: 120
        )
        let fresh = ModulePresentationState.resolve(
            health: [
                EndpointHealth(endpointID: "user.fast", outcome: .ok, latencyMs: 10,
                               responseBytes: 100, at: now, errorClass: nil)
            ],
            hasContent: true, isLoading: false, fallbackError: nil,
            now: now, staleAfter: 120
        )

        XCTAssertEqual(loading.kind, .loading)
        XCTAssertEqual(empty.kind, .empty)
        XCTAssertEqual(fresh.kind, .fresh)
    }

    // MARK: - lastErrorSummary must never leak the raw Torn server string (issue #58)

    /// `DiagnosticsReport.lastErrorSummary`'s own doc comment promises "a `TornAPIError`
    /// classification or a short fixed message, never a raw server string." Today
    /// `AppState.makeDiagnosticsReport()` fills it straight from `errorMsg`, which for
    /// `.permanentKey` / `.insufficientPermissions` / `.temporaryBackend` is
    /// `TornAPIError.userMessage` — the TORN SERVER's own message, merely
    /// control-character-stripped and length-capped. That report text is copied to the
    /// clipboard and pasted into public GitHub issues, so a server string ends up in the
    /// egress channel the doc comment says it never will.
    func testLastErrorSummaryNeverLeaksRawServerMessage() async {
        let appState = AppState(session: MockNetworkSession(), defaults: .createMockDefaults())
        defer { appState.stopPolling() }

        // A distinctive "server" message that would never appear in one of the app's
        // own fixed classification strings by coincidence.
        let rawServerText = "unique_marker_torn_server_says_key_paused_by_owner_9f3a"
        appState.errorMsg = TornAPIError.permanentKey(code: 18, message: rawServerText).userMessage

        let report = await appState.makeDiagnosticsReport()

        XCTAssertNotEqual(
            report.lastErrorSummary, rawServerText,
            "lastErrorSummary must never carry the raw Torn server string verbatim"
        )

        let allowedSummaries: Set<String> = [
            TornErrorClass.permanentKey.rawValue,
            TornErrorClass.insufficientPermissions.rawValue,
            TornErrorClass.rateLimit.rawValue,
            TornErrorClass.dailyRowLimit.rawValue,
            TornErrorClass.temporaryBackend.rawValue,
            TornErrorClass.offline.rawValue,
            TornErrorClass.transport.rawValue,
            TornErrorClass.malformedResponse.rawValue,
            TornErrorClass.cancelled.rawValue,
        ]
        if let summary = report.lastErrorSummary {
            XCTAssertTrue(
                allowedSummaries.contains(summary),
                "lastErrorSummary must be one of the app's own fixed classifications, got: \(summary)"
            )
        }
    }
}
