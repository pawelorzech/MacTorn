import XCTest
@testable import MacTorn

/// `UpdateManager` goes through an injectable `NetworkSession`, compares versions correctly
/// (only a leading "v" is stripped) and its in-flight check dies with polling teardown.
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

    // MARK: - Leading-"v"-only stripping

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

    // MARK: - Teardown

    @MainActor
    func testANewerReleaseIsPublishedToTheApp() async throws {
        let appState = AppState(session: try SlowReleaseSession(), defaults: .createMockDefaults())
        defer { appState.stopPolling() }

        appState.checkForAppUpdates()

        let published = await eventually { appState.updateAvailable?.tagName == "v9.9.9" }
        XCTAssertTrue(published)
    }

    @MainActor
    func testStoppingPollingDiscardsAnInFlightUpdateCheck() async throws {
        let appState = AppState(session: try SlowReleaseSession(), defaults: .createMockDefaults())

        appState.checkForAppUpdates()
        appState.stopPolling()
        try await Task.sleep(nanoseconds: 600_000_000)

        XCTAssertNil(appState.updateAvailable, "a check cancelled by teardown must not publish a result")
    }
}

/// Answers with a newer release after a short delay, and honours cancellation while waiting.
private struct SlowReleaseSession: NetworkSession {
    let body: Data

    init() throws {
        body = try JSONSerialization.data(withJSONObject: [
            "tag_name": "v9.9.9",
            "html_url": "https://github.com/pawelorzech/MacTorn/releases/tag/v9.9.9",
            "body": "notes",
        ])
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await Task.sleep(nanoseconds: 300_000_000)
        return (body, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
