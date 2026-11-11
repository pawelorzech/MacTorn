import SwiftUI

// The optional modules, as they appear inside the tabs. Each renders nothing until it has
// been switched on in Settings › Modules; see `ModuleSwitches.swift` for the switches, the
// freshness button in each heading and the shared "why is this empty" notices.

// MARK: - Competition and calendar (Status)

struct CompetitionPanel: View {
    @Environment(AppState.self) private var app

    var body: some View {
        if app.companion.enabled.contains(.competition) {
            let now = app.time.now
            let (active, upcoming) = CalendarEntry.select(app.companion.calendarEntries, now: now)
            let hasCalendar = !active.isEmpty || !upcoming.isEmpty

            if let competition = app.companion.competition {
                BoardSection(title: competition.name, trailing: { ModuleFreshness(feature: .competition) }) {
                    ModuleIssues(feature: .competition)
                    competitionRows(competition)
                }
            } else if !hasCalendar {
                BoardSection(title: "Competition", trailing: { ModuleFreshness(feature: .competition) }) {
                    ModuleIssues(feature: .competition)
                    BoardEmptyState(title: "No active competition")
                }
            }

            if hasCalendar {
                BoardSection("Torn calendar") {
                    ForEach(Array(active.enumerated()), id: \.offset) { _, entry in
                        ValueRow(label: entry.title,
                                 value: "ends in \(TornFormatter.coarseDuration(Int(entry.end.timeIntervalSince(now))))",
                                 tone: .counting, isFigure: false)
                    }
                    ForEach(Array(upcoming.enumerated()), id: \.offset) { _, entry in
                        ValueRow(label: entry.title,
                                 value: TornFormatter.relativeDate(entry.start, relativeTo: now),
                                 tone: .idle, isFigure: false)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func competitionRows(_ competition: CompetitionV2) -> some View {
        if let team = competition.team { ValueRow(label: "Your team", value: team, isFigure: false) }
        if competition.name != "Easter Egg Hunt", let score = competition.score {
            ValueRow(label: "Your score", value: TornFormatter.formatNumber(score))
        }
        if let attacks = competition.attacks { ValueRow(label: "Your attacks", value: TornFormatter.formatNumber(attacks)) }
        if let status = competition.status { ValueRow(label: "Your side", value: status.capitalized, isFigure: false) }
        if let hp = competition.hp {
            ValueRow(label: "HP", value: "\(TornFormatter.formatNumber(hp.current)) / \(TornFormatter.formatNumber(hp.maximum))")
        }
        if let treats = competition.treatsCollected { ValueRow(label: "Treats collected", value: TornFormatter.formatNumber(treats)) }
        if let basket = competition.basket { ValueRow(label: "Basket", value: basket.name, isFigure: false) }
        if competition.name == "Easter Egg Hunt", let eggs = competition.score, let total = competition.total {
            ValueRow(label: "Eggs found", value: "\(TornFormatter.formatNumber(eggs)) / \(TornFormatter.formatNumber(total))")
        }
        if competition.isElimination {
            ForEach(app.companion.teams) { team in
                BoardRow {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(team.position). \(team.name)\(team.id == competition.teamId ? " (your team)" : "")")
                                .font(.boardStrong)
                                .foregroundStyle(team.eliminated ? Board.inkSecondary : Board.ink)
                            Spacer(minLength: Board.Space.s)
                            Text(TornFormatter.formatNumber(team.score))
                                .font(.figureValue)
                                .foregroundStyle(Board.ink)
                        }
                        Text("\(team.participantsLeft) players, \(team.lives) lives\(team.eliminated ? ", eliminated" : "")")
                            .font(.boardDetail)
                            .foregroundStyle(Board.inkSecondary)
                        ForEach(Array(team.attackingSummary.enumerated()), id: \.offset) { _, attack in
                            let opponent = app.companion.teams.first { $0.id == attack.teamId }?.name ?? "Team \(attack.teamId)"
                            Text("Attacking \(opponent): \(attack.attacks)")
                                .font(.boardDetail)
                                .foregroundStyle(Board.inkSecondary)
                        }
                    }
                }
            }
            Text("Team attacks cover the last completed minute.")
                .font(.boardDetail)
                .foregroundStyle(Board.inkSecondary)
                .padding(.top, 6)
        }
        if app.companion.notAvailable["torn.elimination"] == 32 {
            Text("Elimination attacks are closed until the next attacking period.")
                .font(.boardDetail)
                .foregroundStyle(Board.inkSecondary)
                .padding(.top, 6)
        }
    }
}

// MARK: - Shop prices (Travel)

/// A lookup, not a list: Torn sells hundreds of items, so nothing is shown until the player
/// says what they are after — an item name, a country, or both.
struct ShopPricesPanel: View {
    @Environment(AppState.self) private var app
    @State private var country = ShopPricesPanel.anyCountry
    @State private var search = ""

    private static let anyCountry = "All countries"
    private static let rowCap = 12

    private var countries: [String] {
        [Self.anyCountry] + Set(app.companion.shops.flatMap { $0.value.shops.map(\.country) }).sorted()
    }

    private func shops(for item: ShopItem) -> [ShopItem.Shop] {
        item.value.shops.filter { country == Self.anyCountry || $0.country == country }
    }

    private var hasFilter: Bool {
        country != Self.anyCountry || !search.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var matches: [ShopItem] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return app.companion.shops.filter {
            (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)) && !shops(for: $0).isEmpty
        }
    }

    var body: some View {
        if app.companion.enabled.contains(.shops) {
            BoardSection(title: "Shop prices", trailing: { ModuleFreshness(feature: .shops) }) {
                ModuleIssues(feature: .shops)

                HStack(spacing: 6) {
                    TextField("Find an item", text: $search)
                        .textFieldStyle(.board)
                        .accessibilityLabel("Find an item")
                    Picker("Country", selection: $country) {
                        ForEach(countries, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(width: 118)
                    .accessibilityLabel("Country")
                }
                .padding(.top, 10)
                .padding(.bottom, Board.Space.s)

                if app.companion.shops.isEmpty {
                    BoardEmptyState(title: "No shop data yet",
                                    detail: "It loads the next time this module refreshes.")
                } else if !hasFilter {
                    BoardEmptyState(title: "\(TornFormatter.formatNumber(app.companion.shops.count)) items in Torn's shops",
                                    detail: "Type a name or pick a country to see what is sold there and for how much.")
                } else if matches.isEmpty {
                    BoardEmptyState(title: "Nothing sold matches that")
                } else {
                    results
                }
            }
            .onAppear(perform: preselectDestination)
        }
    }

    /// Flying to or standing in a country: open on that country's shops, since that is the
    /// question the trip raises.
    private func preselectDestination() {
        guard country == Self.anyCountry, let travel = app.player.data?.travel,
              travel.isTraveling || travel.isAbroad, let destination = travel.destination,
              countries.contains(destination) else { return }
        country = destination
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text("Item")
                Spacer(minLength: 0)
                Text("Buy").frame(width: 62, alignment: .trailing)
                Text("Market").frame(width: 70, alignment: .trailing)
            }
            .font(.boardDetail)
            .foregroundStyle(Board.inkSecondary)
            .padding(.bottom, 4)
            .accessibilityHidden(true)

            Board.hairline.frame(height: 1)

            ForEach(matches.prefix(Self.rowCap)) { item in
                row(item)
            }

            Text(footnote)
                .font(.boardDetail)
                .foregroundStyle(Board.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Board.Space.s)
        }
    }

    private var footnote: String {
        let shown = min(matches.count, Self.rowCap)
        let count = matches.count > shown ? "Showing \(shown) of \(matches.count); narrow the search to see the rest. " : ""
        return count + "Catalog prices. Shop stock and live profit aren't guaranteed."
    }

    private func row(_ item: ShopItem) -> some View {
        let offers = shops(for: item)
        // The cheapest place to buy it among the shops in view; a shop with no buy price
        // only takes the item, it does not sell it.
        let cheapest = offers.filter { $0.buyPrice != nil }.min { ($0.buyPrice ?? 0) < ($1.buyPrice ?? 0) }
        let shown = cheapest ?? offers[0]
        let watched = app.watchlist.items.first { $0.id == item.id && $0.lowestPrice > 0 }
        let market = watched?.lowestPrice ?? item.value.marketPrice
        let buy = cheapest?.buyPrice
        let more = offers.count - 1

        return BoardRow(verticalPadding: 7) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name)
                        .font(.boardStrong)
                        .foregroundStyle(Board.ink)
                        .lineLimit(1)
                    Text("\(shown.shop), \(shown.country)" + (more > 0 ? " +\(more) more" : ""))
                        .font(.boardDetail)
                        .foregroundStyle(Board.inkSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(buy.map { "$\(TornFormatter.formatNumber($0))" } ?? "—")
                    .font(.figureValue)
                    .foregroundStyle(buy == nil ? Board.inkSecondary : Board.ink)
                    .frame(width: 62, alignment: .trailing)
                Text("$\(TornFormatter.formatNumber(market))")
                    .font(.figureValue)
                    .foregroundStyle(buy.map { market > $0 } == true ? Board.Tone.ready.ink : Board.ink)
                    .frame(width: 70, alignment: .trailing)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(item.name), \(shown.shop), \(shown.country). "
            + (buy.map { "Buy $\(TornFormatter.formatNumber($0))" } ?? "Not sold here")
            + ", \(watched == nil ? "catalog market value" : "last known market price") $\(TornFormatter.formatNumber(market))"
        )
    }
}

// MARK: - Trades (Money)

struct TradesPanel: View {
    @Environment(AppState.self) private var app

    var body: some View {
        if app.companion.enabled.contains(.trades) {
            BoardSection(title: "Open trades", trailing: { ModuleFreshness(feature: .trades) }) {
                ModuleIssues(feature: .trades)
                if app.companion.trades.isEmpty {
                    BoardEmptyState(title: "No open trades")
                }
                ForEach(app.companion.trades) { trade in
                    BoardRow {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(trade.trader.name ?? "Player \(trade.trader.id)")
                                    .font(.boardStrong)
                                    .foregroundStyle(Board.ink)
                                Spacer(minLength: Board.Space.s)
                                if let expires = trade.expiresAt {
                                    (Text("expires in ") + Text(Date(timeIntervalSince1970: Double(expires)), style: .relative))
                                        .font(.boardDetail)
                                        .foregroundStyle(Board.inkSecondary)
                                }
                            }
                            let description = trade.description.strippedHTMLAndDecodedEntities
                            if !description.isEmpty {
                                Text(description)
                                    .font(.boardCaption)
                                    .foregroundStyle(Board.inkSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if let details = app.companion.tradeDetails[trade.id] {
                                if details.isEmpty {
                                    Text("No items offered.")
                                        .font(.boardDetail)
                                        .foregroundStyle(Board.inkSecondary)
                                }
                                ForEach(Array(details.enumerated()), id: \.offset) { _, item in
                                    Text(item.summary)
                                        .font(.boardDetail)
                                        .foregroundStyle(Board.ink)
                                }
                            }
                            HStack(spacing: 6) {
                                Button("Show offered items") {
                                    Task { await app.companion.loadTrade(trade.id, app: app) }
                                }
                                .buttonStyle(.boardFill)
                                .disabled(app.requester.isInFlight("user.trade"))
                                Button("Review in Torn") { BrowserManager.shared.open(TornLink.trade(trade.id)) }
                                    .buttonStyle(.boardFill)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Stock bonuses (Stocks)

struct StockBonusPanel: View {
    @Environment(AppState.self) private var app

    private func money(_ value: Double) -> String {
        guard let amount = NumericSafety.integerAmount(value) else { return "Unavailable" }
        return TornFormatter.formatMoney(amount)
    }

    var body: some View {
        if app.companion.enabled.contains(.stocks) {
            BoardSection(title: "Stock bonuses", trailing: { ModuleFreshness(feature: .stocks) }) {
                ModuleIssues(feature: .stocks)
                if app.companion.stocks.isEmpty {
                    BoardEmptyState(title: "No share blocks loaded")
                }
                ForEach(app.companion.stocks) { stock in
                    let reference = app.companion.stockReferences.first { $0.id == stock.id }
                    BoardRow {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(reference?.name ?? "Stock \(stock.id)")
                                    .font(.boardStrong)
                                    .foregroundStyle(Board.ink)
                                    .lineLimit(1)
                                Spacer(minLength: Board.Space.s)
                                bonusState(stock, reference: reference)
                            }
                            Text("\(TornFormatter.formatNumber(stock.shares)) shares, cost \(money(stock.costBasis))"
                                 + (reference.map { ", value \(money(Double(stock.shares) * $0.market.price))" } ?? ""))
                                .font(.boardDetail)
                                .foregroundStyle(Board.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if let reference {
                                Text("Bonus: \(reference.bonus.description)")
                                    .font(.boardDetail)
                                    .foregroundStyle(Board.inkSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                if app.companion.stocks.contains(where: { $0.bonus.available }) {
                    Button("Collect in Torn") { BrowserManager.shared.open(TornLink.stocks) }
                        .buttonStyle(.board(.ready, fillsWidth: false))
                        .padding(.top, Board.Space.s)
                }
            }
        }
    }

    @ViewBuilder
    private func bonusState(_ stock: StockV2, reference: StockReferenceV2?) -> some View {
        if reference?.bonus.passive == true {
            Text(stock.bonus.increment > 0 ? "Passive, active" : "Needs more shares")
                .font(.boardCaption)
                .foregroundStyle(stock.bonus.increment > 0 ? Board.Tone.ready.ink : Board.inkSecondary)
        } else if stock.bonus.available {
            Text("Ready")
                .font(.figureValue)
                .foregroundStyle(Board.Tone.ready.ink)
        } else {
            Text("\(stock.bonus.progress) / \(stock.bonus.frequency) d")
                .font(.figureValue)
                .foregroundStyle(Board.ink)
                .accessibilityLabel("Bonus progress \(stock.bonus.progress) of \(stock.bonus.frequency) days, \(stock.bonus.increment) blocks")
        }
    }
}

// MARK: - Open OC slots (Faction)

struct RecruitingPanel: View {
    @Environment(AppState.self) private var app

    var body: some View {
        if app.companion.enabled.contains(.recruiting) {
            BoardSection(title: "Open OC slots", trailing: { ModuleFreshness(feature: .recruiting) }) {
                ModuleIssues(feature: .recruiting)
                if app.player.organizedCrime != nil {
                    BoardEmptyState(title: "You're already in an OC",
                                    detail: "Recruiting checks resume when you leave it.")
                } else if app.companion.eligibleSlots.isEmpty {
                    BoardEmptyState(
                        title: app.requester.isInFlight("user.recruiting") ? "Checking open slots"
                            : app.companion.fetchedAt["user.recruiting"] == nil ? "No recruiting data yet"
                            : "No open slot at \(app.companion.minimumCPR)% pass rate or better",
                        detail: "The minimum pass rate is set in Settings › Modules."
                    )
                } else {
                    ForEach(app.companion.recruiting.filter { $0.status == "Recruiting" }) { crime in
                        let slots = crime.slots.filter { $0.user == nil && $0.checkpointPassRate >= app.companion.minimumCPR }
                        ForEach(Array(slots.enumerated()), id: \.offset) { _, slot in
                            ValueRow(label: slot.positionInfo.label, value: "\(slot.checkpointPassRate)%", detail: crime.name)
                                .accessibilityLabel("\(crime.name), \(slot.positionInfo.label), \(slot.checkpointPassRate) percent pass rate")
                        }
                    }
                    Button("Open organized crimes") { BrowserManager.shared.open(TornLink.factionCrimes) }
                        .buttonStyle(.board)
                        .padding(.top, Board.Space.s)
                }
            }
        }
    }
}

// MARK: - Conflict history (Faction)

/// Torn-wide war records, loaded on request: they are large and nobody needs them polled.
struct WarfarePanel: View {
    @Environment(AppState.self) private var app
    @State private var category = WarfareCategory.ranked
    private var endpoint: String { "faction.\(category.rawValue)" }

    var body: some View {
        BoardSection("Conflict history") {
            HStack(spacing: 6) {
                Picker("Category", selection: $category) {
                    ForEach(WarfareCategory.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .controlSize(.small)
                .accessibilityLabel("Category")

                if app.requester.isInFlight(endpoint) {
                    ProgressView().controlSize(.small).frame(width: 28)
                }
                Button("Load") { Task { await app.companion.loadWarfare(category, app: app) } }
                    .buttonStyle(.board)
                    .disabled(app.requester.isInFlight(endpoint))
            }
            .padding(.top, 10)
            .padding(.bottom, Board.Space.s)

            if let error = app.companion.errors[endpoint] {
                BoardNotice(tone: .counting, message: error)
            }
            if let rows = app.companion.warfare[category] {
                if rows.isEmpty { BoardEmptyState(title: "No records") }
                ForEach(rows) { row in
                    BoardRow(verticalPadding: 7) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(row.title)
                                    .font(.boardStrong)
                                    .foregroundStyle(Board.ink)
                                Spacer(minLength: Board.Space.s)
                                if row.timestamp > 0 {
                                    Text(Date(timeIntervalSince1970: Double(row.timestamp)), style: .date)
                                        .font(.boardDetail)
                                        .foregroundStyle(Board.inkSecondary)
                                }
                            }
                            Text(row.detail)
                                .font(.boardCaption)
                                .foregroundStyle(Board.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if app.companion.nextWarPage[category] != nil {
                    Button("Load older") { Task { await app.companion.loadWarfare(category, app: app, more: true) } }
                        .buttonStyle(.board)
                        .disabled(app.requester.isInFlight(endpoint))
                        .padding(.top, Board.Space.s)
                }
            }
        }
    }
}
