import SwiftUI

struct WatchlistView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.reduceTransparency) private var reduceTransparency
    @State private var showAddItem = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
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
                    
                    Button {
                        withAnimation {
                            showAddItem.toggle()
                        }
                    } label: {
                        Image(systemName: showAddItem ? "minus.circle.fill" : "plus.circle.fill")
                            .foregroundColor(showAddItem ? .red : .green)
                    }
                    .buttonStyle(.plain)
                }
                
                // Add Item Section (inline)
                if showAddItem {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Add item:")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                            ForEach(popularItems, id: \.1) { item in
                                Button {
                                    appState.addToWatchlist(itemId: item.1, name: item.0)
                                    withAnimation {
                                        showAddItem = false
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
                    .background(Color.gray.opacity(reduceTransparency ? 0.4 : 0.1))
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
                            appState.removeFromWatchlist(item.id)
                        } onSetThreshold: { threshold in
                            if let index = appState.watchlistItems.firstIndex(where: { $0.id == item.id }) {
                                appState.watchlistItems[index].priceThreshold = threshold
                                appState.watchlistItems[index].lastAlertedPrice = nil
                                appState.saveWatchlist()
                            }
                        }
                    }
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
        .fixedSize(horizontal: false, vertical: true)
        .task {
            appState.refreshWatchlistPrices()
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
    
    private func openURL(_ urlString: String) {
        if let url = URL(string: urlString) {
            BrowserManager.shared.open(url)
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
                                    .font(.system(size: 8))
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
                    showThresholdPopover = true
                } label: {
                    Image(systemName: item.priceThreshold != nil ? "bell.fill" : "bell")
                        .foregroundColor(item.priceThreshold != nil ? .yellow : .gray)
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showThresholdPopover) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Alert when below:")
                            .font(.caption.bold())

                        TextField("Price", text: $thresholdText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                            .onSubmit {
                                let value = Int(thresholdText)
                                onSetThreshold(value)
                                showThresholdPopover = false
                            }

                        HStack(spacing: 8) {
                            Button("Clear") {
                                onSetThreshold(nil)
                                showThresholdPopover = false
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.secondary)

                            Button("Set") {
                                let value = Int(thresholdText)
                                onSetThreshold(value)
                                showThresholdPopover = false
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.blue)
                        }
                    }
                    .padding(12)
                }

                // Remove button
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                        .font(.caption)
                }
                .buttonStyle(.plain)
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
        .background(Color.gray.opacity(reduceTransparency ? 0.4 : 0.1))
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
}
