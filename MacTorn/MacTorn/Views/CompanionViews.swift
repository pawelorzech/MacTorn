import SwiftUI

struct CompanionControls: View {
    @Environment(AppState.self) private var app
    let feature: CompanionStore.Feature
    let endpoints: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(feature.title, isOn: Binding(get: { app.companion.enabled.contains(feature) }, set: {
                app.companion.setEnabled(feature, $0)
                app.companion.start(app: app)
            }))
            .font(.caption.bold())
            if app.companion.enabled.contains(feature) {
                if [.recruiting, .stocks, .trades].contains(feature) {
                    Toggle("Notify on changes", isOn: Binding(get: { app.companion.alerts.contains(feature) }, set: {
                        app.companion.setAlerts(feature, $0)
                    })).font(.caption)
                }
                ForEach(endpoints, id: \.self) { id in
                    if let error = app.companion.errors[id] {
                        Text(error).foregroundStyle(.orange).font(.caption).fixedSize(horizontal: false, vertical: true)
                    }
                    if app.companion.loading.contains(id) { ProgressView().controlSize(.small) }
                    if let fetched = app.companion.fetchedAt[id] {
                        (Text("Last checked ") + Text(fetched, style: .relative) + Text(" ago"))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Button("Refresh") { app.companion.retry(feature, app: app) }.font(.caption)
            }
        }
    }
}

struct RecruitingPanel: View {
    @Environment(AppState.self) private var app
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CompanionControls(feature: .recruiting, endpoints: ["user.recruiting"])
            if app.companion.enabled.contains(.recruiting) {
                Stepper("Minimum CPR: \(app.companion.minimumCPR)%", value: Binding(
                    get: { app.companion.minimumCPR }, set: { app.companion.minimumCPR = $0 }), in: 0...100, step: 5)
                    .font(.caption)
                if app.organizedCrime != nil {
                    Text("You already have an OC. Recruiting checks resume when you leave it.").font(.caption)
                } else if app.companion.eligibleSlots.isEmpty {
                    Text(app.companion.fetchedAt["user.recruiting"] == nil ? "Enable to check available slots." : "No open slots match your filter.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(app.companion.recruiting) { crime in
                        let slots = crime.slots.filter { $0.user == nil && $0.checkpointPassRate >= app.companion.minimumCPR }
                        if !slots.isEmpty {
                            Text(crime.name).font(.caption.bold())
                            ForEach(Array(slots.enumerated()), id: \.offset) { _, slot in
                                Text("\(slot.positionInfo.label) · \(slot.checkpointPassRate)% CPR").font(.caption)
                            }
                        }
                    }
                }
                Link("Open organized crimes", destination: URL(string: "https://www.torn.com/factions.php?step=your#/tab=crimes")!)
                    .font(.caption)
            }
        }.companionCard()
    }
}

struct StockBonusPanel: View {
    @Environment(AppState.self) private var app
    private func money(_ value: Double) -> String {
        guard value.isFinite, value >= 0 else { return "Unavailable" }
        return value.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CompanionControls(feature: .stocks, endpoints: ["user.stocksv2", "torn.stocksv2"])
            if app.companion.enabled.contains(.stocks) {
                if app.companion.stocks.isEmpty { Text("No stock holdings loaded.").font(.caption).foregroundStyle(.secondary) }
                ForEach(app.companion.stocks) { stock in
                    let reference = app.companion.stockReferences.first { $0.id == stock.id }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(reference?.name ?? "Stock #\(stock.id)").font(.caption.bold())
                        Text("\(stock.shares.formatted()) shares · Cost \(money(stock.costBasis))").font(.caption2)
                        if let reference {
                            Text("Value \(money(Double(stock.shares) * reference.market.price))").font(.caption2)
                            Text(reference.bonus.description).font(.caption2).foregroundStyle(.secondary)
                        }
                        if reference?.bonus.passive == true {
                            Text(stock.bonus.increment > 0 ? "Passive benefit active" : "More shares needed for benefit").font(.caption)
                        } else if stock.bonus.available {
                            Label("Bonus ready to collect", systemImage: "gift.fill").foregroundStyle(.green).font(.caption)
                        } else {
                            Text("Bonus progress: \(stock.bonus.progress) / \(stock.bonus.frequency) days · \(stock.bonus.increment) blocks")
                                .font(.caption2)
                        }
                    }
                    Divider()
                }
                Link("Collect in Torn", destination: URL(string: "https://www.torn.com/page.php?sid=stocks")!).font(.caption)
            }
        }.companionCard()
    }
}

struct CompetitionPanel: View {
    @Environment(AppState.self) private var app
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CompanionControls(feature: .competition, endpoints: ["user.competition", "torn.elimination"])
            if app.companion.enabled.contains(.competition) {
                if let competition = app.companion.competition {
                    Text(competition.name).font(.caption.bold())
                    if let team = competition.team { Text("Your team: \(team)").font(.caption) }
                    if let score = competition.score { Text("Your score: \(score)").font(.caption) }
                    if let attacks = competition.attacks { Text("Your attacks: \(attacks)").font(.caption) }
                    if competition.isElimination {
                        Text("Team attacks cover the last completed minute.").font(.caption2).foregroundStyle(.secondary)
                        ForEach(app.companion.teams) { team in
                            VStack(alignment: .leading, spacing: 3) {
                                Text("#\(team.position) \(team.name)\(team.id == competition.teamId ? " (your team)" : "")").font(.caption.bold())
                                Text("\(team.score) points · \(team.participantsLeft) players · \(team.lives) lives\(team.eliminated ? " · Eliminated" : "")").font(.caption2)
                                ForEach(Array(team.attackingSummary.enumerated()), id: \.offset) { _, attack in
                                    let opponent = app.companion.teams.first { $0.id == attack.teamId }?.name ?? "Team \(attack.teamId)"
                                    Text("→ \(opponent): \(attack.attacks) attacks").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } else { Text("No active competition loaded.").font(.caption).foregroundStyle(.secondary) }
            }
        }.companionCard()
    }
}

struct TradesPanel: View {
    @Environment(AppState.self) private var app
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CompanionControls(feature: .trades, endpoints: ["user.trades", "user.trade"])
            if app.companion.enabled.contains(.trades) {
                if app.companion.trades.isEmpty { Text("No active trades loaded.").font(.caption).foregroundStyle(.secondary) }
                ForEach(app.companion.trades) { trade in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Trade #\(trade.id) · \(trade.trader.name ?? "Player #\(trade.trader.id)")").font(.caption.bold())
                        Text(trade.description.strippedHTMLAndDecodedEntities).font(.caption)
                        if let expires = trade.expiresAt {
                            (Text("Expires ") + Text(Date(timeIntervalSince1970: Double(expires)), style: .relative)).font(.caption2)
                        }
                        Button("Load offered items") { Task { await app.companion.loadTrade(trade.id, app: app) } }
                            .font(.caption).disabled(app.companion.loading.contains("user.trade"))
                        if let details = app.companion.tradeDetails[trade.id] {
                            if details.isEmpty { Text("No items offered.").font(.caption2) }
                            ForEach(Array(details.enumerated()), id: \.offset) { _, item in
                                Text(item.summary).font(.caption2)
                            }
                        }
                        Link("Review trade in Torn", destination: URL(string: "https://www.torn.com/trade.php#step=view&ID=\(trade.id)")!)
                            .font(.caption)
                    }
                }
            }
        }.companionCard()
    }
}

struct ShopPricesPanel: View {
    @Environment(AppState.self) private var app
    @State private var country = "All"
    @State private var search = ""
    let itemID: Int?
    init(itemID: Int? = nil) { self.itemID = itemID }
    private var countries: [String] {
        ["All"] + Set(app.companion.shops.flatMap { $0.value.shops.map(\.country) }).sorted()
    }
    private var matches: [ShopItem] {
        app.companion.shops.filter {
            (itemID == nil || $0.id == itemID) && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search))
                && $0.value.shops.contains { country == "All" || $0.country == country }
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CompanionControls(feature: .shops, endpoints: ["torn.shops"])
            if app.companion.enabled.contains(.shops) {
                if itemID == nil {
                    Picker("Country", selection: $country) { ForEach(countries, id: \.self) { Text($0).tag($0) } }.font(.caption)
                    TextField("Find an item", text: $search).textFieldStyle(.roundedBorder)
                }
                Text("Catalog prices; shop stock and live profit are not guaranteed.").font(.caption2).foregroundStyle(.secondary)
                if matches.isEmpty { Text("No matching shop items loaded.").font(.caption) }
                ForEach(matches.prefix(30)) { item in
                    Text(item.name).font(.caption.bold())
                    ForEach(Array(item.value.shops.filter { country == "All" || $0.country == country }.enumerated()), id: \.offset) { _, shop in
                        Text("\(shop.country) · \(shop.shop) · Buy \(shop.buyPrice.map { "$\($0.formatted())" } ?? "—")")
                            .font(.caption2)
                    }
                    if let watched = app.watchlistItems.first(where: { $0.id == item.id }), watched.lowestPrice > 0 {
                        Text("Last known market price: $\(watched.lowestPrice.formatted())").font(.caption2)
                    } else {
                        Text("Catalog market value: $\(item.value.marketPrice.formatted())").font(.caption2)
                    }
                }
                if matches.count > 30 { Text("Showing 30 of \(matches.count). Narrow your search.").font(.caption2) }
            }
        }.companionCard()
    }
}

struct WarfarePanel: View {
    @Environment(AppState.self) private var app
    @State private var category = WarfareCategory.ranked
    private var endpoint: String { "faction.\(category.rawValue)" }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Global conflict history").font(.caption.bold())
            Picker("Category", selection: $category) { ForEach(WarfareCategory.allCases) { Text($0.title).tag($0) } }
                .font(.caption)
            Button("Load history") { Task { await app.companion.loadWarfare(category, app: app) } }
                .disabled(app.companion.loading.contains(endpoint))
            if app.companion.loading.contains(endpoint) { ProgressView().controlSize(.small) }
            if let error = app.companion.errors[endpoint] { Text(error).foregroundStyle(.orange).font(.caption) }
            if let rows = app.companion.warfare[category] {
                if rows.isEmpty { Text("No records.").font(.caption) }
                ForEach(rows) { row in
                    VStack(alignment: .leading) {
                        Text(row.title).font(.caption.bold())
                        Text(row.detail).font(.caption)
                        if row.timestamp > 0 { Text(Date(timeIntervalSince1970: Double(row.timestamp)), style: .date).font(.caption2) }
                    }
                }
                if app.companion.nextWarPage[category] != nil {
                    Button("Load older") { Task { await app.companion.loadWarfare(category, app: app, more: true) } }
                        .disabled(app.companion.loading.contains(endpoint))
                }
            }
        }.companionCard()
    }
}
private extension View {
    func companionCard() -> some View {
        self.frame(maxWidth: .infinity, alignment: .leading).padding(10)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}
