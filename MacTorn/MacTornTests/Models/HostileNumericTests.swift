import XCTest
import SwiftUI
import AppKit
import os.log
@testable import MacTorn

/// Exercise the reported API values through parsing, model calculations and native
/// view evaluation. Ordinary controls retain their values; invalid results are nil.
final class HostileNumericTests: XCTestCase {
    private let logger = Logger(subsystem: "com.mactorn.tests", category: "HostileNumeric")

    func testBattleStatsOverflowThroughSnapshotParser() async throws {
        let service = UserSnapshotService(session: MockNetworkSession())
        for values in [[Int.max, 1], [Int.min, -1], [40, 2]] {
            let data = try JSONSerialization.data(withJSONObject: [
                "name": "Numeric fixture", "strength": values[0], "defense": values[1]
            ])
            let result = await service.parseSnapshot(data: data, requestedSelections: ["basic"], grantedSelections: nil)
            guard case .success(let payload, _) = result else { return XCTFail("Expected snapshot") }
            XCTAssertEqual(payload.battleStats.total, values[0] == 40 ? 42 : nil)
        }
    }

    func testBattleStatsDecoderFallbackAndExplicitTotal() throws {
        for total in [nil, "invalid"] as [String?] {
            var json: [String: Any] = ["strength": Int.max, "defense": 1]
            if let total { json["total"] = total }
            let data = try JSONSerialization.data(withJSONObject: json)
            XCTAssertNil(try JSONDecoder().decode(BattleStats.self, from: data).total)
        }
        let valid = Data(#"{"strength":40,"defense":2,"total":100}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(BattleStats.self, from: valid).total, 100)
        XCTAssertEqual(BattleStats(strength: 40, defense: 2).total, 42)
    }

    func testOverflowingDurationsAndOrdinaryDeadline() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let clock = ServerClock.synchronized
        XCTAssertNil(clock.serverTimestamp(fetchedAt: now, plus: Int.max))
        XCTAssertNil(clock.serverTimestamp(fetchedAt: now, plus: Int.min))
        XCTAssertEqual(clock.serverTimestamp(fetchedAt: now, plus: 300), 1_700_000_300)
        let data = try JSONSerialization.data(withJSONObject: ["current": 1, "timeout": Int.max])
        let chain = try JSONDecoder().decode(FactionChain.self, from: data)
        XCTAssertEqual(chain.resolvingExpiry(fetchedAt: now, clock: clock).timeout, 0)
        XCTAssertEqual(FactionChain(current: 1, timeout: 300).resolvingExpiry(fetchedAt: now, clock: clock).timeout, 1_700_000_300)
    }

    func testStockPriceRepresentationsAreRejected() throws {
        for price: Any in ["NaN", "inf", "-inf", "1e300", 1e300, -1, Double(Int.max)] {
            let data = try JSONSerialization.data(withJSONObject: ["stocks": ["1": ["current_price": price]]])
            XCTAssertTrue(AppState.parseStocksMetadata(from: data, logger: logger).isEmpty)
        }
        for price: Any in ["123.5", 123.5, 123] {
            let data = try JSONSerialization.data(withJSONObject: ["stocks": ["1": ["current_price": price]]])
            XCTAssertNotNil(AppState.parseStocksMetadata(from: data, logger: logger)[1])
        }
    }

    func testStockProductsAndAggregateCannotOverflow() {
        let stock = StockHolding(stockId: 1, totalShares: 2, transactions: nil)
        for price in [Double.nan, .infinity, 1e300, Double(Int.max).nextDown] {
            let metadata = [1: StockMetadata(id: 1, name: "Fixture", acronym: "F", currentPrice: price)]
            XCTAssertNil(stock.marketValue(using: metadata))
        }
        let valid = [1: StockMetadata(id: 1, name: "Fixture", acronym: "F", currentPrice: 12.75)]
        XCTAssertEqual(stock.marketValue(using: valid), 25)
        XCTAssertNil(NumericSafety.optionalTotal([Int.max, 1]))
        XCTAssertNil(NumericSafety.optionalTotal([10, nil]))
        XCTAssertEqual(NumericSafety.optionalTotal([10, 20]), 30)
        let tx = StockTransaction(shares: Int.max, boughtPrice: 2, timeBought: 1)
        XCTAssertNil(StockHolding(stockId: 1, totalShares: 1, transactions: [tx]).totalCostBasis)
    }

    @MainActor
    func testInvalidStockCacheIsRemovedAndCanRefresh() async throws {
        let defaults = UserDefaults.createMockDefaults()
        let bad = [1: StockMetadata(id: 1, name: "Fixture", acronym: "F", currentPrice: 1e300)]
        defaults.set(try JSONEncoder().encode(bad), forKey: "stocksMetadataCache")
        let session = MockNetworkSession()
        let state = AppState(session: session, defaults: defaults)
        defer { state.stopPolling() }
        XCTAssertTrue(state.stocksMetadata.isEmpty)
        XCTAssertNil(defaults.data(forKey: "stocksMetadataCache"))
        state.apiKey = "numeric-fixture"
        try session.setSuccessResponse(json: ["stocks": ["1": ["current_price": "12.75"]]])
        await state.fetchStocksMetadata()
        XCTAssertEqual(state.stocksMetadata[1]?.currentPrice, 12.75)
    }

    @MainActor
    func testBarClampAndAllDurationCallers() {
        XCTAssertEqual(NumericSafety.progress(current: Int.min, maximum: 1), 0)
        XCTAssertEqual(NumericSafety.progress(current: Int.max, maximum: 1), 1)
        XCTAssertEqual(NumericSafety.progress(current: 1, maximum: 4), 0.25)
        // This evaluates the accessibility percentage even with VoiceOver disabled.
        _ = ProgressBarView(label: "Energy", current: Int.min, maximum: 1, color: .green, icon: "bolt").body
        let state = AppState(session: MockNetworkSession(), defaults: .createMockDefaults())
        defer { state.stopPolling() }
        let json: [String: Any] = ["energy": ["current": 0, "maximum": 1, "fulltime": Int.max],
            "nerve": ["current": 0, "maximum": 1], "life": ["current": 0, "maximum": 1],
            "happy": ["current": 0, "maximum": 1],
            "travel": ["destination": "Mexico", "time_left": Int.max]]
        state.data = try! JSONDecoder().decode(TornResponse.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(state.makeNextActionSnapshot().energyFullAt)
        XCTAssertNil(state.makeNextActionSnapshot().travelArrivalAt)
    }

    func testDecodedBountyAndPropertyTotals() throws {
        let bounties = try JSONDecoder().decode([Bounty].self, from: JSONSerialization.data(withJSONObject: [
            ["target_id": 1, "reward": Int.max], ["target_id": 1, "reward": 1]]))
        XCTAssertNil(NumericSafety.total(bounties.map(\.reward)))
        let properties = [PropertyInfo(marketprice: Int.max), PropertyInfo(marketprice: 1)]
        XCTAssertNil(NumericSafety.total(properties.map(\.marketprice)))
        XCTAssertEqual(NumericSafety.total([40, 2]), 42)
        XCTAssertNil(NumericSafety.total([Int.min]))
    }

    func testWarDifferenceAndMagnitudeDomain() {
        XCTAssertNil(NumericSafety.scoreLead(mine: 0, opponent: Int.min))
        XCTAssertNil(NumericSafety.scoreLead(mine: Int.min, opponent: 0))
        XCTAssertEqual(NumericSafety.scoreLead(mine: 0, opponent: Int.max), -Int.max)
        XCTAssertEqual(NumericSafety.scoreLead(mine: 50, opponent: 20), 30)
        XCTAssertEqual(NumericSafety.scoreLead(mine: 20, opponent: 50), -30)
    }

    func testOCAndActivityTimesRejectInvalidDomains() throws {
        let now = 1_700_000_000
        let oc = try JSONDecoder().decode(OrganizedCrime2.self, from: JSONSerialization.data(withJSONObject: [
            "id": 1, "name": "Fixture", "ready_at": Int.min]))
        XCTAssertNil(NumericSafety.remaining(until: oc.readyAt, now: now))
        XCTAssertNil(NumericSafety.elapsed(since: Int.min, now: now))
        XCTAssertEqual(NumericSafety.remaining(until: now + 300, now: now), 300)
        XCTAssertEqual(NumericSafety.remaining(until: now - 1, now: now), 0)
        XCTAssertEqual(NumericSafety.elapsed(since: now - 60, now: now), 60)
        XCTAssertEqual(NumericSafety.elapsed(since: now + 60, now: now), 0)
        let attack = try JSONDecoder().decode(AttackResult.self, from: JSONSerialization.data(withJSONObject: [
            "code": "fixture", "timestamp_ended": Int.min]))
        XCTAssertEqual(attack.timeAgo(at: Date(timeIntervalSince1970: Double(now))), "")
    }

    @MainActor
    func testHostileValuesRenderWithoutTrapping() throws {
        let state = AppState(session: MockNetworkSession(), defaults: .createMockDefaults())
        defer { state.stopPolling() }
        state.moneyData = MoneyData(cash: Int.max, vault: 1)
        state.propertiesData = [PropertyInfo(id: 1, marketprice: Int.max), PropertyInfo(id: 2, marketprice: 1)]
        state.bountiesOnMe = try JSONDecoder().decode([Bounty].self, from: JSONSerialization.data(withJSONObject: [
            ["target_id": 1, "reward": Int.max], ["target_id": 1, "reward": 1]]))
        state.stocksData = [StockHolding(stockId: 1, totalShares: 2, transactions: nil)]
        state.stocksMetadata = [1: StockMetadata(id: 1, name: "Fixture", acronym: "F", currentPrice: 1e300)]
        render(MoneyView().environment(state))
        render(PropertiesView().environment(state))
        render(StocksView().environment(state))
        render(StatusView().environment(state))
        let oc = OrganizedCrime2(id: 1, name: "Fixture", readyAt: Int.min)
        render(OC2StatusView(oc: oc, playerId: 1))
        let war = try JSONDecoder().decode(RankedWar.self, from: JSONSerialization.data(withJSONObject: [
            "id": 1, "start": 1, "end": 0, "target": 1, "factions": [
                ["id": 1, "name": "A", "score": 0], ["id": 2, "name": "B", "score": Int.min]]]))
        render(RankedWarView(war: war, myFactionId: 1))
        let event = try JSONDecoder().decode(TornEvent.self, from: JSONSerialization.data(withJSONObject: [
            "timestamp": Int.min, "event": "fixture"]))
        render(EventsView(events: [event]))
    }


    @MainActor
    func testNegativeChainDurationIsDiscardedAndSafeToRender() throws {
        let state = AppState(session: MockNetworkSession(), defaults: .createMockDefaults())
        defer { state.stopPolling() }
        let data = try JSONSerialization.data(withJSONObject: ["name": "Fixture", "chain": ["current": 1, "timeout": Int.min]])
        let faction = try JSONDecoder().decode(FactionData.self, from: data)
        let resolved = faction.resolvingChainExpiry(fetchedAt: Date(), clock: .synchronized)
        XCTAssertEqual(resolved.chain.timeout, 0)
        XCTAssertNil(resolved.chain.end)
        state.factionService.publishBasic(faction)
        render(FactionView().environment(state))
        state.factionService.publishBasic(resolved)
        render(FactionView().environment(state))
    }

    @MainActor
    private func render<V: View>(_ view: V) {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 360, height: 640)
        host.layoutSubtreeIfNeeded()
        XCTAssertTrue(host.fittingSize.width.isFinite)
    }
}
