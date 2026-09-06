import XCTest
@testable import MacTorn

@MainActor
final class WidgetSnapshotTests: XCTestCase {
    func testTimersConvertServerClockToLocalDates() throws {
        let clock = MutableTimeSource(Date(timeIntervalSince1970: 1000))
        let app = AppState(defaults: .createMockDefaults(), time: clock)
        app.lastFetchTime = clock.now
        app.serverClock = ServerClock(offset: 90)
        app.data = try JSONDecoder().decode(TornResponse.self, from: Data("""
        {"travel":{"destination":"Japan","timestamp":1690,"departed":790,"time_left":600}}
        """.utf8))
        let snapshot = try XCTUnwrap(app.makeWidgetSnapshot())
        XCTAssertEqual(snapshot.arrival, Date(timeIntervalSince1970: 1600))
        XCTAssertEqual(snapshot.departure, Date(timeIntervalSince1970: 700))
        XCTAssertEqual(snapshot.events.first?.date, snapshot.arrival)
        XCTAssertEqual(snapshot.flightProgress(at: clock.now)!, 1.0/3, accuracy: 0.001)
    }

    func testRelativeArrivalUsesFetchAnchorRatherThanPublishTime() throws {
        let clock = MutableTimeSource(Date(timeIntervalSince1970: 1000))
        let app = AppState(defaults: .createMockDefaults(), time: clock)
        app.lastFetchTime = clock.now
        app.serverClock = ServerClock(offset: -90)
        app.data = try JSONDecoder().decode(TornResponse.self, from: Data("""
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
        XCTAssertEqual(sample.flightProgress(at: .distantPast), 0)
        XCTAssertEqual(sample.flightProgress(at: .distantFuture), 1)
        XCTAssertEqual(WidgetSnapshot.Meter(name: "Energy", current: 200, maximum: 150).fraction, 1)
        XCTAssertEqual(WidgetSnapshot.Meter(name: "Energy", current: -1, maximum: 0).fraction, 0)
    }

    func testMissingContainerFailsExplicitly() {
        let store = WidgetSnapshotStore(directory: nil)
        XCTAssertThrowsError(try store.write(.preview))
        XCTAssertNil(store.read())
    }
}
