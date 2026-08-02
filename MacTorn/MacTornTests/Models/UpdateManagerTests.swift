import XCTest
@testable import MacTorn

/// GitHub issue #56 — `UpdateManager` bypasses the injected `NetworkSession` (it hard-codes
/// `URLSession.shared`), so it has 0% test coverage today. These tests exercise the
/// intended fix: an injectable session (`UpdateManager(session:)`), correct newer/older
/// version comparison, a leading-"v"-only tag strip, and a stored+cancellable `Task`
/// handle on `AppState`.
///
/// NOTE TO IMPLEMENTER: this file will not compile until `UpdateManager` gains a
/// `session: NetworkSession` initializer (issue #56, part 1) and `AppState` gains a
/// stored update-check `Task` handle that `stopPolling()` cancels (issue #56, part 2).
/// That is expected — see the batch's redProof for the exact compiler diagnostics
/// confirming this file is the reason the target does not build today.
final class UpdateManagerTests: XCTestCase {

    private func makeRelease(tag: String) -> [String: Any] {
        ["tag_name": tag, "html_url": "https://github.com/pawelorzech/MacTorn/releases/tag/\(tag)", "body": "notes"]
    }

    // MARK: - Session injection (the actual bug: production hard-codes URLSession.shared)

    func testCheckForUpdatesUsesTheInjectedSessionNotURLSessionShared() async throws {
        let mock = MockNetworkSession()
        try mock.setSuccessResponse(json: makeRelease(tag: "v9.9.9"))
        let manager = UpdateManager(session: mock)

        _ = await manager.checkForUpdates(currentVersion: "1.0.0")

        XCTAssertFalse(mock.requestedURLs.isEmpty,
                        "UpdateManager must issue its GitHub request through the injected session")
        XCTAssertEqual(mock.requestedURLs.first?.host, "api.github.com")
    }

    // MARK: - Newer release detected

    func testNewerReleaseIsDetected() async throws {
        let mock = MockNetworkSession()
        try mock.setSuccessResponse(json: makeRelease(tag: "v2.0.0"))
        let manager = UpdateManager(session: mock)

        let release = await manager.checkForUpdates(currentVersion: "1.9.2")

        XCTAssertNotNil(release, "a strictly newer tag must be reported as an available update")
        XCTAssertEqual(release?.tagName, "v2.0.0")
    }

    // MARK: - Equal/older tag is not reported

    func testEqualTagIsNotReportedAsAnUpdate() async throws {
        let mock = MockNetworkSession()
        try mock.setSuccessResponse(json: makeRelease(tag: "v1.9.2"))
        let manager = UpdateManager(session: mock)

        let release = await manager.checkForUpdates(currentVersion: "1.9.2")

        XCTAssertNil(release, "an equal tag is not a newer release")
    }

    func testOlderTagIsNotReportedAsAnUpdate() async throws {
        let mock = MockNetworkSession()
        try mock.setSuccessResponse(json: makeRelease(tag: "v1.0.0"))
        let manager = UpdateManager(session: mock)

        let release = await manager.checkForUpdates(currentVersion: "1.9.2")

        XCTAssertNil(release, "an older tag is not a newer release")
    }

    // MARK: - Leading-"v"-only stripping (the reported bug: replacingOccurrences(of: "v")
    // strips EVERY "v" in the tag, not just the version prefix)

    func testLeadingVIsStrippedForComparison() async throws {
        let mock = MockNetworkSession()
        try mock.setSuccessResponse(json: makeRelease(tag: "v1.2.3"))
        let manager = UpdateManager(session: mock)

        // 1.2.2 -> 1.2.3 must be recognized as newer once the leading "v" is stripped.
        let release = await manager.checkForUpdates(currentVersion: "1.2.2")

        XCTAssertNotNil(release)
    }

    func testInnerVCharactersSurviveTheStrip() async throws {
        // A hypothetical tag with a "v" inside the version string itself (e.g. a named
        // release). Stripping every "v" (the current bug) mangles "1.2.3-victory" into
        // "1.2.3-ictory", which fails to parse past the patch component and makes the
        // comparison silently wrong. Only the leading "v" prefix may be removed.
        let mock = MockNetworkSession()
        try mock.setSuccessResponse(json: makeRelease(tag: "v1.2.3-victory"))
        let manager = UpdateManager(session: mock)

        let release = await manager.checkForUpdates(currentVersion: "1.2.2")

        XCTAssertNotNil(release, "1.2.3-victory must still compare as newer than 1.2.2 despite the inner \"v\"")
    }

    // MARK: - Task handle lifecycle (issue #56, part 2)

    @MainActor
    func testUpdateCheckTaskIsCancelledByPollingTeardown() async throws {
        let mock = MockNetworkSession()
        try mock.setSuccessResponse(json: makeRelease(tag: "v9.9.9"))
        let appState = AppState(session: mock, defaults: .createMockDefaults())

        appState.checkForAppUpdates()
        XCTAssertNotNil(appState.updateCheckTask, "AppState must retain the update-check Task handle")

        appState.stopPolling()

        XCTAssertTrue(
            appState.updateCheckTask?.isCancelled ?? true,
            "stopPolling() must cancel any in-flight update-check task"
        )
    }
}
