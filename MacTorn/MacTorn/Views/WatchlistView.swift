import SwiftUI

struct WatchlistView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.reduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showAddItem = false
    @State private var itemIdInput = ""
    @State private var addItemError: String?
    @State private var pendingUndo: PendingWatchlistUndo?
    @State private var undoDismissTask: Task<Void, Never>?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ModuleStateView(state: moduleState) {
                    appState.refreshWatchlistPrices()
                }

                // Watchlist Header
                HStack {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .foregroundColor(.green)
                    Text("Price Watch")
                        .font(.caption.bold())
                    
                    Spacer()
                    
                    // Refresh button
                    Button {
                        appState.refreshWatchlistPrices()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Refresh watched prices")
                    
                    Button {
                        withAnimation(reduceMotion ? nil : .default) {
                            showAddItem.toggle()
                        }
                    } label: {
                        Image(systemName: showAddItem ? "minus.circle.fill" : "plus.circle.fill")
                            .foregroundColor(showAddItem ? .red : .green)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(showAddItem ? "Close add item panel" : "Add watched item")
                }
                
                // Add Item Section (inline)
                if showAddItem {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Add item:")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        if let addItemError {
                            Text(addItemError)
                                .font(.caption2)
                                .foregroundColor(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityLabel("Add item error: \(addItemError)")
                        }

                        HStack {
                            TextField("Item ID", text: $itemIdInput)
                                .textFieldStyle(.roundedBorder)
                                .font(.caption)
                                .onChange(of: itemIdInput) { _, _ in
                                    addItemError = nil
                                }
                                .onSubmit {
                                    addItemByID()
                                }

                            Button("Add") {
                                addItemByID()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(itemIdInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                            ForEach(popularItems, id: \.1) { item in
                                Button {
                                    // Keep the panel open and say why when the add is
                                    // refused — closing it looked identical to success.
                                    if appState.addToWatchlist(itemId: item.1, name: item.0) {
                                        addItemError = nil
                                        withAnimation(reduceMotion ? nil : .default) {
                                            showAddItem = false
                                        }
                                    } else {
                                        addItemError = "\(item.0) is already on your watchlist."
                                    }
                                } label: {
                                    Text(item.0)
                                        .font(.caption2)
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 6)
                                        .background(Color.green.opacity(reduceTransparency ? 0.4 : 0.1))
                                        .cornerRadius(4)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(8)
                    .background(Color.secondary.opacity(reduceTransparency ? 0.4 : 0.1))
                    .cornerRadius(6)
                }

                // Watchlist Items with Prices
                if appState.watchlistItems.isEmpty && !showAddItem {
                    VStack(spacing: 8) {
                        Image(systemName: "tag")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text("No items watched")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Track Item Market prices")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                } else if !appState.watchlistItems.isEmpty {
                    ForEach(appState.watchlistItems) { item in
                        WatchlistPriceRow(item: item) {
                            openURL("https://www.torn.com/page.php?sid=ItemMarket#/market/view=item&itemID=\(item.id)")
                        } onRemove: {
                            removeWithUndo(item)
                        } onSetThreshold: { threshold in
                            setThreshold(threshold, for: item)
                        }
                    }
                }

                if let pendingUndo {
                    UndoBanner(message: pendingUndo.message) {
                        undoPending()
                    }
                    .transition(reduceMotion
                                ? .opacity
                                : .move(edge: .top).combined(with: .opacity))
                }
                
                Divider()
                
                // Quick Market Links
                HStack(spacing: 8) {
                    ActionButton(title: "Item Market", icon: "bag.fill", color: .blue) {
                        openURL("https://www.torn.com/page.php?sid=ItemMarket")
                    }
                    
                    ActionButton(title: "Points", icon: "star.fill", color: .orange) {
                        openURL("https://www.torn.com/pmarket.php")
                    }
                }
            }
            .padding()
        }
        .task {
            appState.refreshWatchlistPrices()
        }
        .onDisappear {
            undoDismissTask?.cancel()
            pendingUndo = nil
        }
    }

    private let popularItems = [
        ("Xanax", 206),
        ("FHC", 367),
        ("Donator Pack", 617),
        ("Drug Pack", 370),
        ("Energy Drink", 261),
        ("First Aid Kit", 68)
    ]

    private var moduleState: ModulePresentationState {
        appState.presentationState(
            endpointIDs: ["market.item"],
            hasContent: !appState.watchlistItems.isEmpty,
            staleAfter: 180
        )
    }
    
    private func openURL(_ urlString: String) {
        if let url = URL(string: urlString) {
            BrowserManager.shared.open(url)
        }
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
        guard let index = appState.watchlistItems.firstIndex(where: { $0.id == item.id }) else {
            return
        }
        let removedItem = appState.watchlistItems[index]

        scheduleUndo(.itemRemoved(item: removedItem, index: index)) {
            appState.removeFromWatchlist(item.id)
        }
    }

    /// Clearing a price-alert threshold reuses the exact same Undo banner and
    /// six-second timer as item removal (GitHub #54) — only setting a threshold
    /// (a non-nil value) skips Undo, since that isn't a destructive action.
    private func setThreshold(_ threshold: Int?, for item: WatchlistItem) {
        guard let index = appState.watchlistItems.firstIndex(where: { $0.id == item.id }) else {
            return
        }

        guard threshold == nil else {
            appState.watchlistItems[index].priceThreshold = threshold
            appState.watchlistItems[index].lastAlertedPrice = nil
            appState.saveWatchlist()
            return
        }

        let previousThreshold = appState.watchlistItems[index].priceThreshold
        let previousAlertedPrice = appState.watchlistItems[index].lastAlertedPrice
        scheduleUndo(.thresholdCleared(
            itemId: item.id,
            name: item.name,
            threshold: previousThreshold,
            lastAlertedPrice: previousAlertedPrice
        )) {
            appState.watchlistItems[index].priceThreshold = nil
            appState.watchlistItems[index].lastAlertedPrice = nil
            appState.saveWatchlist()
        }
    }

    /// Shared Undo primitive: performs `action`, shows the banner for `pending`,
    /// and schedules its six-second dismissal. Both item removal and threshold
    /// clearing route through this so there is exactly one Undo mechanism.
    private func scheduleUndo(_ pending: PendingWatchlistUndo, action: () -> Void) {
        undoDismissTask?.cancel()
        action()
        withAnimation(reduceMotion ? nil : .default) {
            pendingUndo = pending
        }
        undoDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .default) {
                pendingUndo = nil
            }
        }
    }

    private func undoPending() {
        guard let pendingUndo else { return }

        undoDismissTask?.cancel()
        switch pendingUndo {
        case .itemRemoved(let item, let index):
            appState.restoreWatchlistItem(item, at: index)
        case .thresholdCleared(let itemId, _, let threshold, let lastAlertedPrice):
            appState.restoreWatchlistThreshold(itemId: itemId, threshold: threshold, lastAlertedPrice: lastAlertedPrice)
        }
        withAnimation(reduceMotion ? nil : .default) {
            self.pendingUndo = nil
        }
    }
}

/// The two destructive watchlist actions that can be undone via the shared
/// six-second Undo banner (GitHub #49 item removal, GitHub #54 threshold clear).
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
struct WatchlistPriceRow: View {
    @Environment(\.reduceTransparency) private var reduceTransparency
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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                // Item name & open button
                Button(action: onOpen) {
                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.blue)
                            .font(.caption2)
                        Text(item.name)
                            .font(.caption.bold())
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(item.name) in Item Market")

                Spacer()

                // Price info
                if let error = item.error {
                     HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                            .font(.caption2)
                        Text(error)
                            .font(.caption2)
                            .foregroundColor(.red)
                    }
                } else if item.isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                } else {
                    VStack(alignment: .trailing, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(formatPrice(item.lowestPrice))
                                .font(.caption.monospacedDigit().bold())
                                .foregroundColor(.green)

                            if item.lowestPriceQuantity > 1 {
                                Text("x\(item.lowestPriceQuantity)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }

                        if item.priceDifference > 0 {
                            HStack(spacing: 2) {
                                Image(systemName: "arrow.up")
                                    .font(.caption2)
                                Text("+\(formatPrice(item.priceDifference))")
                                    .font(.caption2.monospacedDigit())
                            }
                            .foregroundColor(.orange)
                        }
                    }
                }

                // Bell button for price threshold
                Button {
                    thresholdText = item.priceThreshold.map { String($0) } ?? ""
                    thresholdError = nil
                    showThresholdPopover = true
                } label: {
                    Image(systemName: item.priceThreshold != nil ? "bell.fill" : "bell")
                        .foregroundColor(item.priceThreshold != nil ? .yellow : .secondary)
                        .font(.caption)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.priceThreshold != nil
                                    ? "Edit price alert for \(item.name)"
                                    : "Set price alert for \(item.name)")
                .popover(isPresented: $showThresholdPopover) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Alert when below:")
                            .font(.caption.bold())

                        TextField("Price", text: $thresholdText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                            .onChange(of: thresholdText) { _, newValue in
                                thresholdError = PositiveIntegerInput.errorMessage(for: newValue)
                            }
                            .onSubmit {
                                submitThreshold()
                            }

                        if let thresholdError {
                            Text(thresholdError)
                                .font(.caption2)
                                .foregroundStyle(.red)
                                .accessibilityLabel("Price threshold error: \(thresholdError)")
                        }

                        HStack(spacing: 8) {
                            Button("Clear") {
                                onSetThreshold(nil)
                                showThresholdPopover = false
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.secondary)

                            Button("Set") {
                                submitThreshold()
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.blue)
                            .disabled(thresholdValue == nil)
                        }
                    }
                    .padding(12)
                }

                // Remove button
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.caption)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(item.name) from price watch")
            }

            // Threshold indicator
            if let threshold = item.priceThreshold {
                HStack(spacing: 4) {
                    Image(systemName: "bell.fill")
                        .font(.caption2)
                        .foregroundColor(.yellow)
                    Text("Alert below \(formatPrice(threshold))")
                        .font(.caption2)
                        .foregroundColor(.yellow)
                }
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(reduceTransparency ? 0.4 : 0.1))
        .cornerRadius(6)
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

enum PositiveIntegerInput {
    static func value(from input: String) -> Int? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(trimmed), value > 0 else { return nil }
        return value
    }

    static func errorMessage(for input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value(from: input) == nil else { return nil }
        if trimmed.isEmpty {
            return "Enter a price."
        }
        if let value = Int(trimmed), value <= 0 {
            return "Price must be greater than zero."
        }
        return "Enter a whole number."
    }
}

struct UndoBanner: View {
    let message: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(message)
                .font(.caption)
                .lineLimit(1)

            Spacer()

            Button("Undo", action: onUndo)
                .buttonStyle(.borderless)
                .font(.caption.bold())
                .accessibilityLabel("Undo \(message)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.14))
        .cornerRadius(6)
    }
}

extension AppState {
    @discardableResult
    func restoreWatchlistItem(_ item: WatchlistItem, at originalIndex: Int) -> Bool {
        guard !watchlistItems.contains(where: { $0.id == item.id }) else {
            return false
        }

        let insertionIndex = min(max(originalIndex, 0), watchlistItems.count)
        watchlistItems.insert(item, at: insertionIndex)
        saveWatchlist()
        return true
    }

    /// Restores a previously-captured price-alert threshold, mirroring
    /// `restoreWatchlistItem` so the price-alert Clear button can share the same
    /// Undo mechanism as item removal (GitHub #54).
    @discardableResult
    func restoreWatchlistThreshold(itemId: Int, threshold: Int?, lastAlertedPrice: Int?) -> Bool {
        guard let index = watchlistItems.firstIndex(where: { $0.id == itemId }) else {
            return false
        }

        watchlistItems[index].priceThreshold = threshold
        watchlistItems[index].lastAlertedPrice = lastAlertedPrice
        saveWatchlist()
        return true
    }
}
