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
}
