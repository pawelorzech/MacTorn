import Foundation
import Observation

/// Optional modules share the application's request pipeline and account boundary.
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

        /// What the module reads; its errors, spinners and "last checked" are keyed by these.
        var endpointIDs: [String] {
            switch self {
            case .recruiting: return ["user.recruiting"]
            case .stocks: return ["user.stocksv2", "torn.stocksv2"]
            case .competition: return ["user.competition", "torn.elimination", "torn.calendar", "user.calendar"]
            case .trades: return ["user.trades"]
            case .shops: return ["torn.items"]
            }
        }

        var canAlert: Bool { [.recruiting, .stocks, .trades].contains(self) }
    }

    /// Torn's answer when a competition or elimination round is not running (code 33).
    private static let noCompetitionCode = 33
    private static let shopCatalogCadence: TimeInterval = 604_800

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let notifier: Notifying
    var enabled: Set<Feature>
    var alerts: Set<Feature>
    var minimumCPR: Int { didSet { defaults.set(minimumCPR, forKey: "companion.minimumCPR") } }
    var recruiting: [RecruitingCrime] = []
    var stocks: [StockV2] = []
    var stockReferences: [StockReferenceV2] = []
    var competition: CompetitionV2?
    var teams: [EliminationTeam] = []
    var calendarActivities: [(activity: CalendarActivity, isCompetition: Bool)] = []
    var calendarStartTime: String?
    /// Torn code 32/33 per endpoint: healthy but nothing to serve right now. Not an error.
    var notAvailable: [String: Int] = [:]
    var trades: [TradeV2] = []
    var shops: [ShopItem] = []
    var tradeDetails: [Int: [TradeDetailItem]] = [:]
    var warfare: [WarfareCategory: [WarfareEntry]] = [:]
    var nextWarPage: [WarfareCategory: Int] = [:]
    var errors: [String: String] = [:]
    var fetchedAt: [String: Date] = [:]
    private(set) var isRefreshing = false
    @ObservationIgnored private(set) var task: Task<Void, Never>?
    @ObservationIgnored private var generation: UInt = 0
    @ObservationIgnored private var shopsLoadedAt: Date?
    @ObservationIgnored private var fingerprints: [Feature: Set<String>] = [:]
    @ObservationIgnored private var previousTrades: [Int: String]?

    init(defaults: UserDefaults, notifier: Notifying) {
        self.defaults = defaults
        self.notifier = notifier
        enabled = Set((defaults.stringArray(forKey: "companion.enabled") ?? []).compactMap(Feature.init))
        alerts = Set((defaults.stringArray(forKey: "companion.alerts") ?? []).compactMap(Feature.init))
        minimumCPR = min(100, max(0, defaults.integer(forKey: "companion.minimumCPR")))
    }

    func setEnabled(_ feature: Feature, _ value: Bool, app: AppState) {
        if value { enabled.insert(feature) } else { enabled.remove(feature) }
        defaults.set(enabled.map(\.rawValue), forKey: "companion.enabled")
        // An in-flight response from before this preference change must not publish.
        invalidate(app: app)
        forgetAlertBaseline(feature)
    }

    func setAlerts(_ feature: Feature, _ value: Bool) {
        if value { alerts.insert(feature) } else { alerts.remove(feature) }
        defaults.set(alerts.map(\.rawValue), forKey: "companion.alerts")
        forgetAlertBaseline(feature)
    }

    private func forgetAlertBaseline(_ feature: Feature) {
        fingerprints[feature] = nil
        if feature == .trades { previousTrades = nil }
    }

    private func invalidate(app: AppState) {
        generation &+= 1
        task?.cancel()
        task = nil
        isRefreshing = false
        shopsLoadedAt = nil
        app.requester.makeDue(Feature.allCases.flatMap(\.endpointIDs))
    }

    func reset() {
        generation &+= 1
        task?.cancel()
        task = nil
        isRefreshing = false
        shopsLoadedAt = nil
        recruiting = []; stocks = []; stockReferences = []; competition = nil
        calendarActivities = []; calendarStartTime = nil; notAvailable = [:]
        teams = []; trades = []; tradeDetails = [:]; shops = []; warfare = [:]; nextWarPage = [:]
        errors = [:]; fetchedAt = [:]; fingerprints = [:]; previousTrades = nil
    }

    func start(app: AppState) {
        guard task == nil, !enabled.isEmpty, !app.apiKey.isEmpty, !app.keyHalted,
              app.connectivity.isConnected else { return }
        let token = generation
        isRefreshing = true
        task = Task { [weak self, weak app] in
            guard let self, let app else { return }
            await self.refresh(app: app)
            if self.generation == token {
                self.task = nil
                self.isRefreshing = false
            }
        }
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

    func isLoading(_ feature: Feature, app: AppState) -> Bool {
        feature.endpointIDs.contains(where: app.requester.isInFlight)
    }

    func retry(_ feature: Feature, app: AppState) {
        guard task == nil else { return }
        // A refresh within thirty seconds of the last read just waits for that read.
        app.requester.makeDue(feature.endpointIDs.filter { app.requester.isDue($0, every: 30) })
        if feature == .shops { shopsLoadedAt = nil }
        start(app: app)
    }

    private func refresh(app: AppState) async {
        let token = generation
        let requester = app.requester
        func active(_ feature: Feature) -> Bool {
            token == generation && !Task.isCancelled && enabled.contains(feature)
        }
        if active(.recruiting), app.player.organizedCrime == nil, requester.isDue("user.recruiting"),
           let value: RecruitingResponse = await request("user.recruiting", app: app) {
            recruiting = value.organizedcrimes
            let fresh = newlyAvailable(Set(eligibleSlots.map { "\($0.crime.id):\($0.slot.positionInfo.id)" }), feature: .recruiting)
            if alerts.contains(.recruiting), !fresh.isEmpty {
                notifier.send(title: "Open OC slots", body: "\(fresh.count) new slots meet your CPR filter.", type: .ocOpportunity)
            }
        }
        if active(.stocks) {
            if requester.isDue("torn.stocksv2"),
               let value: StockReferencesResponse = await request("torn.stocksv2", app: app) {
                stockReferences = value.stocks
            }
            if active(.stocks), requester.isDue("user.stocksv2"),
               let value: StocksV2Response = await request("user.stocksv2", app: app) {
                stocks = value.stocks
                let fresh = newlyAvailable(Set(stocks.filter { $0.bonus.available }.map { String($0.id) }), feature: .stocks)
                if alerts.contains(.stocks), !fresh.isEmpty {
                    notifier.send(title: "Stock bonus ready", body: "\(fresh.count) stock bonuses can be collected in Torn.", type: .stockBonus)
                }
            }
        }
        if active(.competition) {
            // Elimination changes by the minute; other competitions slowly; none rarely.
            let cadence: TimeInterval = competition.map { $0.isElimination ? 60 : 300 } ?? 3600
            if requester.isDue("user.competition", every: cadence) {
                if let value: CompetitionResponse = await request("user.competition", app: app) {
                    competition = value.competition
                    if competition?.isElimination != true { teams = [] }
                } else if notAvailable["user.competition"] == Self.noCompetitionCode {
                    competition = nil; teams = []
                }
            }
        }
        if active(.competition), competition?.isElimination == true, requester.isDue("torn.elimination") {
            if let value: EliminationResponse = await request("torn.elimination", app: app) {
                teams = value.elimination.sorted { $0.position < $1.position }
            } else if notAvailable["torn.elimination"] == Self.noCompetitionCode {
                competition = nil; teams = []
            }
        }
        if active(.competition), requester.isDue("torn.calendar"),
           let value: TornCalendarResponse = await request("torn.calendar", app: app) {
            calendarActivities = value.calendar.competitions.map { ($0, true) } + value.calendar.events.map { ($0, false) }
        }
        // Optional: without it non-fixed events just keep the 00:00 TCT start.
        if active(.competition), requester.isDue("user.calendar"),
           let value: UserCalendarResponse = await request("user.calendar", app: app) {
            calendarStartTime = value.calendar.startTime
        }
        if active(.trades), requester.isDue("user.trades"),
           let value: TradesResponse = await request("user.trades", app: app) {
            let current = Dictionary(value.trades.map { ($0.id, $0.signature) }, uniquingKeysWith: { _, new in new })
            if let previousTrades, alerts.contains(.trades), previousTrades != current {
                notifier.send(title: "Trades changed", body: "Your active trades have changed. Open Torn to review them.", type: .tradeChanged)
            }
            previousTrades = current
            trades = value.trades
            tradeDetails = [:] // Details are point-in-time; refetch after trade changes.
        }
        if active(.shops), shopsLoadedAt.map({ app.time.now.timeIntervalSince($0) >= Self.shopCatalogCadence }) ?? true {
            await refreshShops(app: app, isActive: { active(.shops) })
        }
    }

    /// The shop module reads the same public catalogue (and cache) as item-name search,
    /// so a fresh catalogue never costs a second full download.
    private func refreshShops(app: AppState, isActive: () -> Bool) async {
        let identity = app.accountSession.identity
        shopsLoadedAt = app.time.now
        let result = await app.shopCatalogRefreshingIfNeeded()
        guard isActive(), app.accountSession.isCurrent(identity) else { return }
        switch result {
        case .success(let value):
            shops = value
            fetchedAt["torn.items"] = app.time.now
            errors["torn.items"] = nil
        case .pending(let value):
            shops = value
            // Ask again next tick, so the module notices when the shared request lands.
            shopsLoadedAt = nil
        case .denied(let message, let value):
            shops = value
            errors["torn.items"] = message
            shopsLoadedAt = nil
        case .failed(let value):
            shops = value
            errors["torn.items"] = "Could not refresh the item catalog. Previous shop data may be out of date."
            shopsLoadedAt = nil
        }
    }

    /// Calendar activities with trustworthy dates and the user's personal start applied.
    var calendarEntries: [CalendarEntry] {
        let offset = CalendarEntry.offset(from: calendarStartTime)
        return calendarActivities.map { CalendarEntry($0.activity, isCompetition: $0.isCompetition, personalOffset: offset) }
    }

    func request<Value: Decodable>(_ id: String, app: AppState) async -> Value? {
        await load(id, app: app) { data, _ in try? JSONDecoder().decode(Value.self, from: data) }
    }

    private func load<Value>(_ id: String, app: AppState, to: Int? = nil, parameter: Int? = nil,
                             parse: @escaping @Sendable (Data, [String: Any]) -> Value?) async -> Value? {
        let requester = app.requester
        guard !Task.isCancelled, !requester.isInFlight(id) else { return nil }
        guard !app.apiKey.isEmpty, !app.keyHalted else {
            errors[id] = "Connect a valid API key in Settings to load this data."
            return nil
        }
        guard app.connectivity.isConnected else {
            errors[id] = "No internet connection. Reconnect and try again."
            return nil
        }
        if let denial = requester.denial(id) {
            errors[id] = denial.userExplanation
            return nil
        }
        guard requester.url(id, parameter: parameter) != nil else {
            errors[id] = "This data is unavailable with your current API key. Check Settings."
            return nil
        }
        let token = generation
        let query = to.map { [URLQueryItem(name: "to", value: String($0))] } ?? []
        let result = await requester.fetch(id, parameter: parameter, query: query, decode: parse)
        guard generation == token else { return nil }
        switch result {
        case .loaded(let value):
            fetchedAt[id] = app.time.now
            errors[id] = nil
            notAvailable[id] = nil
            return value
        case .nothingToServe(let code):
            errors[id] = nil
            notAvailable[id] = code
            fetchedAt[id] = app.time.now
            return nil
        case .failed(let failure):
            errors[id] = failure.userMessage
            return nil
        case .skipped, .superseded:
            return nil
        }
    }

    func loadTrade(_ tradeID: Int, app: AppState) async {
        guard enabled.contains(.trades) else { return }
        guard let detail: TradeDetailResponse = await load("user.trade", app: app, parameter: tradeID, parse: { data, _ in
            try? JSONDecoder().decode(TradeDetailResponse.self, from: data)
        }) else { return }
        guard detail.trade.id == tradeID else { errors["user.trade"] = "Unexpected trade returned by Torn."; return }
        tradeDetails[tradeID] = detail.trade.items
    }

    func loadWarfare(_ category: WarfareCategory, app: AppState, more: Bool = false) async {
        let id = category.endpointID
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
