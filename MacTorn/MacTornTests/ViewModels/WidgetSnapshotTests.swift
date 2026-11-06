import XCTest
@testable import MacTorn

@MainActor
final class WidgetSnapshotTests: XCTestCase {
    func testPublicationCoalescesBurstAndKeepsFreshness() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = AppState(defaults: .createMockDefaults())
        app.widgetStore = WidgetSnapshotStore(directory: directory)
        app.player.data = try JSONDecoder().decode(TornResponse.self, from: Data("{}".utf8))
        var reloads = 0
        app.reloadWidgetTimelines = { reloads += 1 }
        app.publishWidgets()
        app.publishWidgets()
        app.player.lastFetchTime = Date(timeIntervalSince1970: 1000)
        app.publishWidgets()
        await app.widgetPublicationTask?.value
        XCTAssertEqual(reloads, 1)
        XCTAssertEqual(app.widgetStore?.read()?.updatedAt, app.player.lastFetchTime)

        app.player.lastFetchTime = Date(timeIntervalSince1970: 1100)
        app.publishWidgets()
        await app.widgetPublicationTask?.value
        XCTAssertEqual(reloads, 2, "Unchanged values must still publish a fresh fetch timestamp")
        XCTAssertEqual(app.widgetStore?.read()?.updatedAt, app.player.lastFetchTime)
    }

    func testAccountResetCancelsQueuedWidgetWrite() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = AppState(defaults: .createMockDefaults())
        app.widgetStore = WidgetSnapshotStore(directory: directory)
        app.player.data = try JSONDecoder().decode(TornResponse.self, from: Data("{}".utf8))
        var reloads = 0
        app.reloadWidgetTimelines = { reloads += 1 }
        app.publishWidgets()
        let pending = app.widgetPublicationTask
        app.resetAccountScopedState()
        await pending?.value
        XCTAssertNil(app.widgetStore?.read())
        XCTAssertNil(app.widgetPublicationTask)
        XCTAssertEqual(reloads, 1, "Only the immediate reset should reload widgets")
    }

    func testTimersConvertServerClockToLocalDates() throws {
        let clock = MutableTimeSource(Date(timeIntervalSince1970: 1000))
        let app = AppState(defaults: .createMockDefaults(), time: clock)
        app.player.lastFetchTime = clock.now
        app.player.serverClock = ServerClock(offset: 90)
        app.player.data = try JSONDecoder().decode(TornResponse.self, from: Data("""
        {"travel":{"destination":"Japan","timestamp":1690,"departed":790,"time_left":600}}
        """.utf8))
        let snapshot = try XCTUnwrap(app.makeWidgetSnapshot())
        XCTAssertEqual(snapshot.arrival, Date(timeIntervalSince1970: 1600))
        XCTAssertEqual(snapshot.departure, Date(timeIntervalSince1970: 700))
        XCTAssertEqual(snapshot.events.first?.date, snapshot.arrival)
    }

    func testRelativeArrivalUsesFetchAnchorRatherThanPublishTime() throws {
        let clock = MutableTimeSource(Date(timeIntervalSince1970: 1000))
        let app = AppState(defaults: .createMockDefaults(), time: clock)
        app.player.lastFetchTime = clock.now
        app.player.serverClock = ServerClock(offset: -90)
        app.player.data = try JSONDecoder().decode(TornResponse.self, from: Data("""
        {"travel":{"destination":"Torn","time_left":600}}
        """.utf8))
        clock.advance(100)
        XCTAssertEqual(app.makeWidgetSnapshot()?.arrival, Date(timeIntervalSince1970: 1600))
        XCTAssertEqual(app.makeWidgetSnapshot()?.updatedAt, Date(timeIntervalSince1970: 1000))
    }

    func testStoreRoundTripCorruptionAndAccountReset() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WidgetSnapshotStore(directory: directory)
        XCTAssertNil(store.read())
        let sample = WidgetSnapshot.preview
        try store.write(sample)
        XCTAssertEqual(store.read(), sample)
        let app = AppState(defaults: .createMockDefaults())
        app.widgetStore = store
        app.resetAccountScopedState()
        XCTAssertNil(store.read())
        XCTAssertNil(app.makeWidgetSnapshot())
        try Data("broken".utf8).write(to: directory.appendingPathComponent("widget-snapshot.json"))
        XCTAssertNil(store.read())
        try store.write(sample)
        XCTAssertEqual(store.read(), sample)
        app.apiKey = "different-test-key"
        XCTAssertNil(store.read())
    }

    func testStalenessExpiredEventsAndClampedProgress() {
        let sample = WidgetSnapshot.preview
        XCTAssertFalse(sample.isStale(at: sample.updatedAt.addingTimeInterval(300)))
        XCTAssertTrue(sample.isStale(at: sample.updatedAt.addingTimeInterval(301)))
        XCTAssertTrue(sample.upcoming(at: sample.updatedAt.addingTimeInterval(10_000)).isEmpty)
        XCTAssertEqual(WidgetSnapshot.Meter(name: "Energy", current: 200, maximum: 150).fraction, 1)
        XCTAssertEqual(WidgetSnapshot.Meter(name: "Energy", current: -1, maximum: 0).fraction, 0)
    }

    func testSnapshotFromOlderBuildStillDecodes() throws {
        let json = """
        {"updatedAt":1000,"meters":[{"name":"Happy","current":1,"maximum":2}],"status":"Torn",
         "events":[{"id":"refills","title":"Refill","symbol":"drop.fill","date":900}]}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let snapshot = try decoder.decode(WidgetSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(snapshot.meters.first?.kind, .happy)
        XCTAssertEqual(snapshot.events.first?.persistsPastDate, false)
    }

    func testMissingContainerFailsExplicitly() {
        let store = WidgetSnapshotStore(directory: nil)
        XCTAssertThrowsError(try store.write(.preview))
        XCTAssertNil(store.read())
    }
}
