import XCTest
@testable import MacTorn

/// Etap J — the Next Action engine: correct ordering, future-only, hide config.
final class NextActionTests: XCTestCase {

    private let engine = NextActionEngine()
    private let now = 1_700_000_000

    private func snapshot(_ configure: (inout NextActionSnapshot) -> Void) -> NextActionSnapshot {
        var s = NextActionSnapshot(now: now)
        configure(&s)
        return s
    }

    func testEventsSortedSoonestFirst() {
        let s = snapshot {
            $0.energyFullAt = now + 300
            $0.chainTimeoutAt = now + 45
            $0.travelArrivalAt = now + 120
        }
        let events = engine.events(from: s)
        XCTAssertEqual(events.map(\.category), [.chain, .travel, .energy])
        XCTAssertEqual(events.first?.eta, 45)
    }

    func testNearestIsTheSoonest() {
        let s = snapshot {
            $0.energyFullAt = now + 300
            $0.drugReadyAt = now + 60
        }
        XCTAssertEqual(engine.nearest(from: s)?.category, .drug)
    }

    func testPastAndPresentTimedEventsAreDropped() {
        let s = snapshot {
            $0.drugReadyAt = now - 10   // cooldown already ended
            $0.energyFullAt = now       // exactly now
            $0.nerveFullAt = now + 30   // future
        }
        XCTAssertEqual(engine.events(from: s).map(\.category), [.nerve])
    }

    func testRefillsAppearAsReadyState() {
        let s = snapshot { $0.refillsAvailable = true }
        let events = engine.events(from: s)
        XCTAssertEqual(events.map(\.category), [.refills])
        XCTAssertTrue(events.first!.isReady)
        XCTAssertEqual(events.first!.eta, 0)
    }

    func testHiddenCategoriesAreExcluded() {
        let s = snapshot {
            $0.chainTimeoutAt = now + 45
            $0.energyFullAt = now + 300
        }
        let events = engine.events(from: s, hidden: [.chain])
        XCTAssertEqual(events.map(\.category), [.energy])
    }

    func testTieBreakUsesCategoryOrder() {
        // energy and nerve both fire at the same instant → energy (earlier in the enum) first.
        let s = snapshot {
            $0.nerveFullAt = now + 100
            $0.energyFullAt = now + 100
        }
        XCTAssertEqual(engine.events(from: s).map(\.category), [.energy, .nerve])
    }

    func testEmptySnapshotYieldsNoEvents() {
        XCTAssertTrue(engine.events(from: snapshot { _ in }).isEmpty)
        XCTAssertNil(engine.nearest(from: snapshot { _ in }))
    }

    func testEtaNeverNegative() {
        let s = snapshot { $0.hospitalReleaseAt = now + 10 }
        XCTAssertGreaterThanOrEqual(engine.events(from: s).first!.eta, 0)
    }

    func testAllCategoriesHaveLabelAndIcon() {
        for category in NextActionCategory.allCases {
            XCTAssertFalse(category.label.isEmpty)
            XCTAssertFalse(category.systemImage.isEmpty)
        }
    }

    @MainActor
    func testAppStateMakeNextActionSnapshot_barFulltimeCountsDownAsTimeAdvances() throws {
        let mockSession = MockNetworkSession()
        let appState = AppState(session: mockSession)
        
        let fetchTime = Date(timeIntervalSince1970: 1_700_000_000)
        appState.lastFetchTime = fetchTime
        let dict: [String: Any] = [
            "energy": ["current": 100, "maximum": 150, "fulltime": 600],
            "nerve": ["current": 50, "maximum": 50, "fulltime": 0],
            "life": ["current": 100, "maximum": 100, "fulltime": 0],
            "happy": ["current": 500, "maximum": 500, "fulltime": 0]
        ]
        let jsonData = try JSONSerialization.data(withJSONObject: dict)
        appState.data = try JSONDecoder().decode(TornResponse.self, from: jsonData)

        // At fetch time (t = 0), energy full ETA is 600s
        let eventsAtT0 = appState.nextEvents(now: fetchTime)
        XCTAssertEqual(eventsAtT0.count, 1)
        XCTAssertEqual(eventsAtT0.first?.category, .energy)
        XCTAssertEqual(eventsAtT0.first?.eta, 600)

        // 300s later (t = 300), without re-fetching, energy full ETA must count down to 300s
        let t300 = fetchTime.addingTimeInterval(300)
        let eventsAtT300 = appState.nextEvents(now: t300)
        XCTAssertEqual(eventsAtT300.count, 1)
        XCTAssertEqual(eventsAtT300.first?.category, .energy)
        XCTAssertEqual(eventsAtT300.first?.eta, 300)

        // 600s later (t = 600), energy is full, so event should be dropped
        let t600 = fetchTime.addingTimeInterval(600)
        let eventsAtT600 = appState.nextEvents(now: t600)
        XCTAssertTrue(eventsAtT600.isEmpty)
    }

    @MainActor
    func testAppStateMakeNextActionSnapshot_travelArrivalAnchoredToFetchTime() throws {
        let mockSession = MockNetworkSession()
        let appState = AppState(session: mockSession)

        let fetchTime = Date(timeIntervalSince1970: 1_700_000_000)
        appState.lastFetchTime = fetchTime
        let dict: [String: Any] = [
            "travel": [
                "destination": "Mexico",
                "timestamp": 1_700_000_120,
                "departed": 1_700_000_000,
                "time_left": 120
            ]
        ]
        let jsonData = try JSONSerialization.data(withJSONObject: dict)
        appState.data = try JSONDecoder().decode(TornResponse.self, from: jsonData)

        let eventsAtT0 = appState.nextEvents(now: fetchTime)
        XCTAssertEqual(eventsAtT0.first?.category, .travel)
        XCTAssertEqual(eventsAtT0.first?.eta, 120)

        let t50 = fetchTime.addingTimeInterval(50)
        let eventsAtT50 = appState.nextEvents(now: t50)
        XCTAssertEqual(eventsAtT50.first?.category, .travel)
        XCTAssertEqual(eventsAtT50.first?.eta, 70)
    }
}
