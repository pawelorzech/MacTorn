import SwiftUI

/// "Is anything at or under my price?" The watched items lead, each with Torn's lowest
/// price as its figure; adding and removing are kept quiet. Shop prices live in Travel.
struct WatchlistView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showAddItem = false
    @State private var itemIdInput = ""
    @State private var addItemError: String?
    @State private var undo = UndoController<PendingWatchlistUndo>()

    var body: some View {
        BoardPage {
            // With nothing watched there is nothing to fetch; the list's own empty
            // state explains that, so a "No data yet, Retry" strip would contradict it.
            if !appState.watchlist.items.isEmpty {
                ModuleStateView(state: moduleState) {
                    appState.refreshWatchlistPrices()
                }
            }

            BoardSection(title: "Watched items", trailing: {
                HStack(spacing: 0) {
                    IconButton(systemImage: "arrow.clockwise", label: "Refresh watched prices") {
                        appState.refreshWatchlistPrices()
                    }
                    IconButton(
                        systemImage: showAddItem ? "minus" : "plus",
                        label: showAddItem ? "Close add item panel" : "Add watched item"
                    ) {
                        withAnimation(reduceMotion ? nil : .default) {
                            showAddItem.toggle()
                        }
                    }
                }
            }) {
                if showAddItem {
                    addPanel
                }

                if appState.watchlist.items.isEmpty && !showAddItem {
                    BoardEmptyState(
                        title: "No items watched",
                        detail: "Use the plus button to add an item and follow its lowest Item Market price."
                    )
                } else {
                    ForEach(appState.watchlist.items) { item in
                        WatchlistPriceRow(item: item) {
                            openTorn(TornLink.itemMarket(itemID: item.id))
                        } onRemove: {
                            removeWithUndo(item)
                        } onSetThreshold: { threshold in
                            setThreshold(threshold, for: item)
                        }
                    }
                }
            }

            // Torn's item-market data is globally cached and published late on
            // purpose. Said once, so a price that is an hour old reads as Torn's
            // schedule rather than as MacTorn falling behind.
            if let lag = appState.watchlist.publishedPriceLag {
                Text("Torn's API publishes item-market prices at least \(TornFormatter.spelledDuration(Int(lag))) late. Alerts follow Torn's price, not the live market.")
                    .font(.boardDetail)
                    .foregroundStyle(Board.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            PendingUndoBanner(controller: undo, message: \.message) {
                undoPending()
            }

            BoardSection("Open in Torn") {
                TornLinks(links: [
                    TornLinks.Link(title: "Item market", url: TornLink.itemMarket),
                    TornLinks.Link(title: "Points market", url: TornLink.page("pmarket.php")),
                ], columns: 2)
                .padding(.top, Board.Space.s)
            }
        }
        .task {
            appState.refreshWatchlistPrices()
        }
        .onDisappear {
            undo.reset()
        }
    }

    // MARK: - Add item

    private var addPanel: some View {
        VStack(alignment: .leading, spacing: Board.Space.s) {
            HStack(spacing: 6) {
                TextField(searchFieldPrompt, text: $itemIdInput)
                    .accessibilityLabel("Item name or ID")
                    .textFieldStyle(.board)
                    .onChange(of: itemIdInput) { _, _ in
                        addItemError = nil
                    }
                    .onSubmit {
                        commitTypedEntry()
                    }

                Button("Add") {
                    commitTypedEntry()
                }
                .buttonStyle(.boardPrimary)
                .disabled(itemIdInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let addItemError {
                BoardNotice(tone: .alert, message: addItemError)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Add item error: \(addItemError)")
            }

            // Search results when there are any, a "no match" line when a typed
            // name finds nothing, and otherwise the shortlist. The shortlist is
            // the fallback for every remaining state, not just an unloaded
            // catalog, so opening the panel cold never shows a blank field.
            if !searchResults.isEmpty {
                VStack(spacing: 0) {
                    ForEach(searchResults) { item in
                        suggestionRow(name: item.name, id: item.id)
                    }
                }
            } else if isSearchingByName {
                Text("No item matches \u{201C}\(itemIdInput.trimmingCharacters(in: .whitespacesAndNewlines))\u{201D}.")
                    .font(.boardCaption)
                    .foregroundStyle(Board.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                    ForEach(popularItems, id: \.1) { item in
                        Button(item.0) {
                            add(name: item.0, id: item.1)
                        }
                        .buttonStyle(.boardFill)
                    }
                }
            }
        }
        .padding(.top, Board.Space.s)
        .padding(.bottom, Board.Space.m)
        .overlay(alignment: .bottom) {
            Board.hairline.frame(height: 1)
        }
    }

    /// True when the field holds something that should be looked up by name rather than
    /// treated as an item id.
    private var isSearchingByName: Bool {
        let typed = itemIdInput.trimmingCharacters(in: .whitespacesAndNewlines)
        return !typed.isEmpty && Int(typed) == nil && !appState.itemCatalog.isEmpty
    }

    /// Commits whatever is in the field. It accepts a name or an id, and Return honours both.
    private func commitTypedEntry() {
        if isSearchingByName {
            guard let best = searchResults.first else {
                // Deliberately silent. The inline row below the field already says "No item
                // matches “xanx”." and names the actual query; setting an error here put a
                // second wording of the same fact above the field, in a different colour,
                // at exactly the moment the user is reading.
                return
            }
            add(name: best.name, id: best.id)
            return
        }
        addItemByID()
    }

    /// Catalog matches for whatever is in the field. Typing digits still means "this
    /// item id", so a numeric entry searches nothing and goes straight through Add.
    private var searchResults: [TornItemSummary] {
        let typed = itemIdInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty, Int(typed) == nil else { return [] }
        // Six rows, not the search default of twelve: this list renders inside the add
        // panel inside the fixed-size panel, and twelve suggestions push the rest of the
        // watchlist off the visible area entirely.
        return appState.searchItems(typed, limit: 6)
    }

    /// The field accepts a name only once the catalog is there to resolve it.
    private var searchFieldPrompt: String {
        appState.itemCatalog.isEmpty ? "Item ID" : "Item name or ID"
    }

    private func suggestionRow(name: String, id: Int) -> some View {
        Button {
            add(name: name, id: id)
        } label: {
            BoardRow(verticalPadding: 6) {
                HStack {
                    Text(name)
                        .font(.boardBody)
                        .foregroundStyle(Board.ink)
                        .lineLimit(1)
                    Spacer(minLength: Board.Space.s)
                    Text("#\(id)")
                        .font(.boardDetail)
                        .foregroundStyle(Board.inkSecondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add \(name) to the watchlist")
    }

    /// Keep the panel open and say why when the add is refused — closing it looked
    /// identical to success.
    private func add(name: String, id: Int) {
        if appState.addToWatchlist(itemId: id, name: name) {
            addItemError = nil
            itemIdInput = ""
            withAnimation(reduceMotion ? nil : .default) {
                showAddItem = false
            }
        } else {
            addItemError = "\(name) is already on your watchlist."
        }
    }

    /// The fallback shortlist, shown only until Torn's item catalog arrives.
    private let popularItems = [
        ("Xanax", 206),
        ("FHC", 367),
        ("Donator Pack", 617),
        ("Drug Pack", 370),
        ("Energy Drink", 261),
        ("First Aid Kit", 68)
    ]

    private var moduleState: ModulePresentationState {
        appState.watchlistPresentationState
    }

    private func addItemByID() {
        switch appState.addToWatchlist(input: itemIdInput) {
        case .notANumber:
            addItemError = "Enter a positive item ID."
            return
        case .outOfRange(let maximum):
            addItemError = "Item IDs go up to \(maximum - 1)."
            return
        case .alreadyWatched:
            addItemError = "This item is already on your watchlist."
            return
        case .added:
            break
        }
        itemIdInput = ""
        addItemError = nil
        withAnimation(reduceMotion ? nil : .default) {
            showAddItem = false
        }
    }

    private func removeWithUndo(_ item: WatchlistItem) {
        guard let index = appState.watchlist.items.firstIndex(where: { $0.id == item.id }) else {
            return
        }
        let removedItem = appState.watchlist.items[index]

        scheduleUndo(.itemRemoved(item: removedItem, index: index)) {
            appState.watchlist.remove(itemID: item.id)
        }
    }

    /// Clearing a price-alert threshold offers Undo like item removal; setting one
    /// (a non-nil value) skips it, since that isn't destructive.
    private func setThreshold(_ threshold: Int?, for item: WatchlistItem) {
        guard let index = appState.watchlist.items.firstIndex(where: { $0.id == item.id }) else {
            return
        }

        guard threshold == nil else {
            appState.setWatchlistThreshold(threshold, for: item.id)
            return
        }

        let previousThreshold = appState.watchlist.items[index].priceThreshold
        let previousAlertedPrice = appState.watchlist.items[index].lastAlertedPrice
        scheduleUndo(.thresholdCleared(
            itemId: item.id,
            name: item.name,
            threshold: previousThreshold,
            lastAlertedPrice: previousAlertedPrice
        )) {
            appState.setWatchlistThreshold(nil, for: item.id)
        }
    }

    private func scheduleUndo(_ pending: PendingWatchlistUndo, action: () -> Void) {
        undo.schedule(pending, reduceMotion: reduceMotion, action: action)
    }

    private func undoPending() {
        undo.undo(reduceMotion: reduceMotion) { pending in
            switch pending {
            case .itemRemoved(let item, let index):
                appState.watchlist.restore(item, at: index)
            case .thresholdCleared(let itemId, _, let threshold, let lastAlertedPrice):
                appState.restoreWatchlistThreshold(itemId: itemId, threshold: threshold, lastAlertedPrice: lastAlertedPrice)
            }
        }
    }
}

/// The two destructive watchlist actions that can be undone.
private enum PendingWatchlistUndo {
    case itemRemoved(item: WatchlistItem, index: Int)
    case thresholdCleared(itemId: Int, name: String, threshold: Int?, lastAlertedPrice: Int?)

    var message: String {
        switch self {
        case .itemRemoved(let item, _):
            return "\(item.name) removed"
        case .thresholdCleared(_, let name, _, _):
            return "\(name) price alert cleared"
        }
    }
}

// MARK: - Watchlist Price Row

/// One watched item: its name and lowest price up front, what sits behind that price and
/// whether it is under the player's alert as detail, and the alert and remove controls
/// last and quiet.
struct WatchlistPriceRow: View {
    let item: WatchlistItem
    let onOpen: () -> Void
    let onRemove: () -> Void
    let onSetThreshold: (Int?) -> Void

    @State private var showThresholdPopover = false
    @State private var thresholdText = ""
    @State private var thresholdError: String?

    private var thresholdValue: Int? {
        PositiveIntegerInput.value(from: thresholdText)
    }

    /// The lowest price is at or under the alert the player set.
    private var thresholdMet: Bool {
        guard let threshold = item.priceThreshold, item.lowestPrice > 0 else { return false }
        return item.lowestPrice <= threshold
    }

    var body: some View {
        BoardRow {
            VStack(alignment: .leading, spacing: 6) {
                // What it is and what is known about it on the left; the price and the two
                // things you can do to the row on the right, so a row is two lines, not four.
                HStack(alignment: .top, spacing: Board.Space.s) {
                    VStack(alignment: .leading, spacing: 2) {
                        nameButton
                        if item.lastUpdated != nil, !item.isLoading {
                            stockDetail
                        }
                        alertLine
                    }
                    Spacer(minLength: Board.Space.s)
                    VStack(alignment: .trailing, spacing: 0) {
                        price
                        buttons
                    }
                }
                if let error = item.error {
                    BoardNotice(tone: .alert, message: error)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Price update error: \(error)")
                }
            }
        }
    }

    // MARK: Parts

    private var nameButton: some View {
        Button(action: onOpen) {
            Text(item.name)
                .font(.boardStrong)
                .foregroundStyle(Board.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(item.name) in Item Market")
    }

    @ViewBuilder
    private var price: some View {
        if item.isLoading && item.error == nil {
            ProgressView()
                .controlSize(.small)
                .frame(height: 26)
        } else if item.lastUpdated != nil {
            Text(formatPrice(item.lowestPrice))
                .font(.figure(22))
                .foregroundStyle(thresholdMet ? Board.Tone.ready.ink : Board.ink)
                .lineLimit(1)
                .fixedSize()
        }
    }

    private var stockParts: [String] {
        var parts: [String] = []
        if item.lowestPriceQuantity > 0 {
            parts.append("\(TornFormatter.formatNumber(item.lowestPriceQuantity)) at this price")
        }
        if item.priceDifference > 0 {
            parts.append("next \(formatPrice(item.secondLowestPrice))")
        }
        return parts
    }

    /// Quantity at the lowest price, the next price up, and how old the data is.
    private var stockDetail: some View {
        VStack(alignment: .leading, spacing: 1) {
            if !stockParts.isEmpty {
                Text(stockParts.joined(separator: ", "))
                    .font(.boardDetail)
                    .foregroundStyle(Board.inkSecondary)
            }

            if let dataTimestamp = item.dataTimestamp ?? item.lastUpdated {
                let prefix = item.error == nil ? "Price from " : "Last known price, from "
                Text(prefix + TornFormatter.relativeDate(dataTimestamp, abbreviated: true))
                    .font(.boardDetail)
                    .foregroundStyle(Board.inkSecondary)
            }
        }
    }

    @ViewBuilder
    private var alertLine: some View {
        if let threshold = item.priceThreshold {
            if thresholdMet {
                Text("At or under your alert of \(formatPrice(threshold))")
                    .font(.boardDetail.weight(.medium))
                    .foregroundStyle(Board.Tone.ready.ink)
            } else {
                Text("Alert at or under \(formatPrice(threshold))")
                    .font(.boardDetail)
                    .foregroundStyle(Board.inkSecondary)
            }
        }
    }

    private var buttons: some View {
        HStack(spacing: 0) {
            IconButton(
                systemImage: item.priceThreshold != nil ? "bell.fill" : "bell",
                label: item.priceThreshold != nil
                    ? "Edit price alert for \(item.name)"
                    : "Set price alert for \(item.name)"
            ) {
                thresholdText = item.priceThreshold.map { String($0) } ?? ""
                thresholdError = nil
                showThresholdPopover = true
            }
            .popover(isPresented: $showThresholdPopover) {
                thresholdPopover
            }

            IconButton(
                systemImage: "xmark",
                label: "Remove \(item.name) from price watch",
                action: onRemove
            )
        }
    }

    private var thresholdPopover: some View {
        VStack(alignment: .leading, spacing: Board.Space.s) {
            Text("Alert when at or under")
                .font(.boardStrong)
                .foregroundStyle(Board.ink)

            TextField("Price", text: $thresholdText)
                .accessibilityLabel("Price alert threshold")
                .textFieldStyle(.board)
                .frame(width: 140)
                .onChange(of: thresholdText) { _, newValue in
                    thresholdError = PositiveIntegerInput.errorMessage(for: newValue)
                }
                .onSubmit {
                    submitThreshold()
                }

            if let thresholdError {
                Text(thresholdError)
                    .font(.boardDetail)
                    .foregroundStyle(Board.Tone.alert.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 140, alignment: .leading)
                    .accessibilityLabel("Price threshold error: \(thresholdError)")
            }

            HStack(spacing: 6) {
                Button("Clear") {
                    onSetThreshold(nil)
                    showThresholdPopover = false
                }
                .buttonStyle(.boardFill)

                Button("Set") {
                    submitThreshold()
                }
                .buttonStyle(.boardPrimary)
                .disabled(thresholdValue == nil)
            }
            .frame(width: 140)
        }
        .padding(Board.Space.m)
    }

    private func formatPrice(_ price: Int) -> String {
        if price >= 1_000_000 {
            return String(format: "$%.1fM", Double(price) / 1_000_000)
        } else if price >= 1_000 {
            return String(format: "$%.0fK", Double(price) / 1_000)
        }
        return "$\(price)"
    }

    private func submitThreshold() {
        guard let thresholdValue else {
            thresholdError = PositiveIntegerInput.errorMessage(for: thresholdText)
            return
        }

        onSetThreshold(thresholdValue)
        thresholdError = nil
        showThresholdPopover = false
    }
}
