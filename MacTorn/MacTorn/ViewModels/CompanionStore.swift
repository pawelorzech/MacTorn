import Foundation
import Observation

/// Optional modules share the application's request gate and account boundary.
/// Only preferences persist; private responses and alert baselines are session scoped.
@MainActor @Observable
final class CompanionStore {
    enum Feature: String, CaseIterable {
        case recruiting, stocks, competition, trades, shops
        var title: String {
            switch self {
            case .recruiting: return "Find open OC slots"
            case .stocks: return "Stock bonuses"
            case .competition: return "Competition tracker"
            case .trades: return "Trade monitor"
            case .shops: return "Travel shop prices"
            }
        }
    }
    @ObservationIgnored private let defaults: UserDefaults
    var enabled: Set<Feature>
    var alerts: Set<Feature>
    var minimumCPR: Int { didSet { defaults.set(minimumCPR, forKey: "companion.minimumCPR") } }
    var recruiting: [RecruitingCrime] = []
    var stocks: [StockV2] = []
    var stockReferences: [StockReferenceV2] = []
    var competition: CompetitionV2?
    var teams: [EliminationTeam] = []
    var trades: [TradeV2] = []
    var shops: [ShopItem] = []
    var tradeDetails: [Int: [TradeDetailItem]] = [:]
    var warfare: [WarfareCategory: [WarfareEntry]] = [:]
    var nextWarPage: [WarfareCategory: Int] = [:]
    var errors: [String: String] = [:]
    var fetchedAt: [String: Date] = [:]
    var loading: Set<String> = []
    @ObservationIgnored var task: Task<Void, Never>?
    @ObservationIgnored private var generation: UInt = 0
    @ObservationIgnored private var lastAttempt: [String: Date] = [:]
    @ObservationIgnored private var fingerprints: [Feature: Set<String>] = [:]
    @ObservationIgnored private var previousTrades: [Int: String]?

    init(defaults: UserDefaults) {
        self.defaults = defaults
        enabled = Set((defaults.stringArray(forKey: "companion.enabled") ?? []).compactMap(Feature.init))
        alerts = Set((defaults.stringArray(forKey: "companion.alerts") ?? []).compactMap(Feature.init))
        minimumCPR = min(100, max(0, defaults.integer(forKey: "companion.minimumCPR")))
    }

    func setEnabled(_ feature: Feature, _ value: Bool) {
        if value { enabled.insert(feature) } else { enabled.remove(feature) }
        defaults.set(enabled.map(\.rawValue), forKey: "companion.enabled")
        // An in-flight response from before this preference change must not publish.
        invalidate()
        fingerprints[feature] = nil
        if feature == .trades { previousTrades = nil }
    }
    func setAlerts(_ feature: Feature, _ value: Bool) {
        if value { alerts.insert(feature) } else { alerts.remove(feature) }
        defaults.set(alerts.map(\.rawValue), forKey: "companion.alerts")
        fingerprints[feature] = nil
        if feature == .trades { previousTrades = nil }
    }
    private func invalidate() {
        generation &+= 1
        task?.cancel()
        task = nil
        loading = []
        lastAttempt = [:]
    }
    func reset() {
        invalidate()
        recruiting = []; stocks = []; stockReferences = []; competition = nil
        teams = []; trades = []; tradeDetails = [:]; shops = []; warfare = [:]; nextWarPage = [:]
        errors = [:]; fetchedAt = [:]; fingerprints = [:]; previousTrades = nil
    }
    func start(app: AppState) {
        guard task == nil, !enabled.isEmpty, !app.apiKey.isEmpty, !app.keyHalted,
              app.connectivity.isConnected else { return }
        let token = generation
        task = Task { [weak self, weak app] in
            guard let self, let app else { return }
            await self.refresh(app: app)
            if self.generation == token { self.task = nil }
        }
    }
    func due(_ id: String, seconds: TimeInterval, now: Date) -> Bool {
        guard !loading.contains(id) else { return false }
        return lastAttempt[id].map { now.timeIntervalSince($0) >= seconds } ?? true
    }

    /// Seeds without alerting; only edges since a successful prior read are announced.
    func newlyAvailable(_ values: Set<String>, feature: Feature) -> Set<String> {
        let old = fingerprints.updateValue(values, forKey: feature)
        guard let old else { return [] }
        return values.subtracting(old)
    }
    var eligibleSlots: [(crime: RecruitingCrime, slot: RecruitingCrime.Slot)] {
        recruiting.filter { $0.status == "Recruiting" }.flatMap { crime in
            crime.slots.filter { $0.user == nil && $0.checkpointPassRate >= minimumCPR }.map { (crime, $0) }
        }
    }

    func retry(_ feature: Feature, app: AppState) {
        guard task == nil else { return }
        let ids: [String]
        switch feature {
        case .recruiting: ids = ["user.recruiting"]
        case .stocks: ids = ["user.stocksv2", "torn.stocksv2"]
        case .competition: ids = ["user.competition", "torn.elimination"]
        case .trades: ids = ["user.trades"]
        case .shops: ids = ["torn.items"]
        }
        for id in ids where due(id, seconds: 30, now: app.time.now) { lastAttempt[id] = nil }
        start(app: app)
    }

    private func refresh(app: AppState) async {
        let token = generation
        func active(_ feature: Feature) -> Bool {
            token == generation && !Task.isCancelled && enabled.contains(feature)
        }
        if active(.recruiting), app.organizedCrime == nil,
           due("user.recruiting", seconds: 300, now: app.time.now) {
            if let value: RecruitingResponse = await request("user.recruiting", app: app) {
                recruiting = value.organizedcrimes
                let fresh = newlyAvailable(Set(eligibleSlots.map { "\($0.crime.id):\($0.slot.positionInfo.id)" }), feature: .recruiting)
                if alerts.contains(.recruiting), !fresh.isEmpty {
                    notify("Open OC slots", "\(fresh.count) new slots meet your CPR filter.", type: .ocOpportunity)
                }
            }
        }
        if active(.stocks) {
            if due("torn.stocksv2", seconds: 300, now: app.time.now),
               let value: StockReferencesResponse = await request("torn.stocksv2", app: app) {
                stockReferences = value.stocks
            }
            if active(.stocks), due("user.stocksv2", seconds: 300, now: app.time.now),
               let value: StocksV2Response = await request("user.stocksv2", app: app) {
                stocks = value.stocks
                let fresh = newlyAvailable(Set(stocks.filter { $0.bonus.available }.map { String($0.id) }), feature: .stocks)
                if alerts.contains(.stocks), !fresh.isEmpty {
                    notify("Stock bonus ready", "\(fresh.count) stock bonuses can be collected in Torn.", type: .stockBonus)
                }
            }
        }
        if active(.competition), due("user.competition", seconds: competition?.isElimination == true ? 60 : 3600, now: app.time.now) {
            if let value: CompetitionResponse = await request("user.competition", app: app) {
                competition = value.competition
                if competition?.isElimination != true { teams = [] }
            }
        }
        if active(.competition), competition?.isElimination == true,
           due("torn.elimination", seconds: 60, now: app.time.now),
           let value: EliminationResponse = await request("torn.elimination", app: app) {
            teams = value.elimination.sorted { $0.position < $1.position }
        }
        if active(.trades), due("user.trades", seconds: 120, now: app.time.now),
           let value: TradesResponse = await request("user.trades", app: app) {
            let current = Dictionary(value.trades.map { ($0.id, $0.signature) }, uniquingKeysWith: { _, new in new })
            if let previousTrades, alerts.contains(.trades), previousTrades != current {
                notify("Trades changed", "Your active trades have changed. Open Torn to review them.", type: .tradeChanged)
            }
            previousTrades = current
            trades = value.trades
            tradeDetails = [:] // Details are point-in-time; refetch after trade changes.
        }
        if active(.shops), due("torn.items", seconds: 604800, now: app.time.now) {
            let identity = app.accountSession.identity
            lastAttempt["torn.items"] = app.time.now
            loading.insert("torn.shops")
            let result = await app.shopCatalogRefreshingIfNeeded()
            guard active(.shops), app.accountSession.isCurrent(identity) else { return }
            switch result {
            case .success(let value):
                shops = value
                loading.remove("torn.shops")
                fetchedAt["torn.shops"] = app.time.now
                errors["torn.shops"] = nil
            case .pending(let value):
                shops = value
                // Keep the shared-catalog spinner truthful until a later tick observes
                // the coalesced request or retry as complete.
                lastAttempt["torn.items"] = nil
            case .denied(let message, let value):
                shops = value
                loading.remove("torn.shops")
                errors["torn.shops"] = message
                lastAttempt["torn.items"] = nil
            case .failed(let value):
                shops = value
                loading.remove("torn.shops")
                errors["torn.shops"] = "Could not refresh the item catalog. Previous shop data may be out of date."
                lastAttempt["torn.items"] = nil
            }
        }
    }

    private func notify(_ title: String, _ body: String, type: NotificationType) {
        NotificationManager.shared.send(title: title, body: body, type: type)
    }

    func request<Value: Decodable>(_ id: String, app: AppState) async -> Value? {
        await load(id, app: app) { data, _ in try? JSONDecoder().decode(Value.self, from: data) }
    }

    /// All optional reads use existing health/error handling and the global budget.
    private func load<Value>(_ id: String, app: AppState, to: Int? = nil,
                             parameter: Int? = nil, parse: @escaping @Sendable (Data, [String: Any]) -> Value?) async -> Value? {
        guard !Task.isCancelled, !app.apiKey.isEmpty, !app.keyHalted, app.connectivity.isConnected,
              !loading.contains(id), let base = app.endpointURL(id, parameter: parameter) else { return nil }
        if let denial = app.endpointGate.denial(for: id, keyInfo: app.keyInfo, coordinator: app.pollingCoordinator) {
            errors[id] = denial.userExplanation
            return nil
        }
        guard app.reserveRequest(id) else { return nil }
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        if let to { components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "to", value: String(to))] }
        guard let url = components.url else { return nil }
        let identity = app.accountSession.identity
        let token = generation
        let started = app.time.now
        loading.insert(id)
        lastAttempt[id] = started
        defer { if generation == token { loading.remove(id) } }
        do {
            let result = try await TornAPIClient.loadJSON(from: url, session: app.session, decode: parse)
            guard !Task.isCancelled, generation == token, app.accountSession.isCurrent(identity) else { return nil }
            switch result {
            case .success(let value, let bytes):
                fetchedAt[id] = app.time.now
                errors[id] = nil
                app.endpointGate.noteSuccess(for: id)
                app.recordHealth(id, outcome: .ok, since: started, bytes: bytes)
                return value
            case .apiError(let error, _): errors[id] = error.userMessage
            case .httpError(let code, _): errors[id] = "Server error (HTTP \(code)). Try again later."
            case .malformed: errors[id] = "Torn returned an unexpected response. Previous data may be out of date."
            }
            app.recordServiceFailure(result, for: id, since: started)
        } catch {
            guard !Task.isCancelled, generation == token, app.accountSession.isCurrent(identity) else { return nil }
            errors[id] = "Could not connect to Torn. Try again."
            app.recordHealth(id, outcome: .error, since: started, bytes: 0, errorClass: "transport")
        }
        // Long-lived lookups retry after a short delay on failure, not a whole week.
        lastAttempt[id] = app.time.now
        return nil
    }

    func loadTrade(_ tradeID: Int, app: AppState) async {
        guard enabled.contains(.trades), !loading.contains("user.trade") else { return }
        guard let detail: TradeDetailResponse = await load("user.trade", app: app, parameter: tradeID, parse: { data, _ in
            try? JSONDecoder().decode(TradeDetailResponse.self, from: data)
        }) else { return }
        guard detail.trade.id == tradeID else { errors["user.trade"] = "Unexpected trade returned by Torn."; return }
        tradeDetails[tradeID] = detail.trade.items
    }

    func loadWarfare(_ category: WarfareCategory, app: AppState, more: Bool = false) async {
        let id = "faction.\(category.rawValue)"
        let cursor = more ? nextWarPage[category] : nil
        if more && cursor == nil { return }
        guard let page: WarfarePage = await load(id, app: app, to: cursor, parse: { _, json in
            WarfarePage.parse(json, category: category)
        }) else { return }
        var seen = Set<Int>()
        let combined = (more ? warfare[category] ?? [] : []) + page.entries
        warfare[category] = combined.filter { seen.insert($0.id).inserted }
        // Stop broken or repeating pagination instead of issuing the same request forever.
        nextWarPage[category] = page.nextTo == cursor ? nil : page.nextTo
    }
}
