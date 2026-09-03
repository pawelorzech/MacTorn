import SwiftUI

struct StocksView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.reduceTransparency) private var reduceTransparency

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ModuleStateView(
                    state: appState.presentationState(
                        endpointIDs: ["user.fast"],
                        hasContent: !appState.stocksData.isEmpty,
                        staleAfter: 120
                    ),
                    onRetry: appState.refreshNow
                )

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .foregroundColor(.blue)
                        Text("Stocks")
                            .font(.caption.bold())
                        Spacer()
                        if !appState.stocksData.isEmpty {
                            Text("Market: \(formatMoney(totalMarketValue))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    if appState.stocksData.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "chart.line.downtrend.xyaxis")
                                .font(.title2)
                                .foregroundColor(.secondary)
                            Text("No stocks found")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    } else {
                        ForEach(appState.stocksData) { stock in
                            let metadata = appState.stocksMetadata[stock.stockId]
                            HStack(spacing: 6) {
                                if let metadata {
                                    Text(metadata.acronym)
                                        .font(.caption2.bold())
                                    Text(metadata.name)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                } else {
                                    Text("Stock details unavailable")
                                        .font(.caption2)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 4)

                                Text(stock.totalShares.formatted())
                                    .font(.caption2.monospacedDigit())
                                    .foregroundColor(.secondary)
                                Text(formatMoney(stock.marketValue(using: appState.stocksMetadata)))
                                    .font(.caption2.monospacedDigit())
                            }
                        }

                        if totalCostBasis > 0 {
                            Divider()
                            HStack {
                                Text("Cost basis")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(formatMoney(totalCostBasis))
                                    .monospacedDigit()
                                    .foregroundColor(.secondary)
                            }
                            .font(.caption2)
                        }
                    }
                }
                .padding()
                .background(Color.blue.opacity(reduceTransparency ? 0.25 : 0.08))
                .cornerRadius(8)

                ActionButton(
                    title: "Stock Market",
                    icon: "chart.line.uptrend.xyaxis",
                    color: .blue
                ) {
                    openURL("https://www.torn.com/page.php?sid=stocks")
                }
            }
            .padding()
        }
        .accessibilityIdentifier("account.stocks")
    }

    private var totalMarketValue: Int {
        appState.stocksData.reduce(0) { sum, stock in
            sum + stock.marketValue(using: appState.stocksMetadata)
        }
    }

    private var totalCostBasis: Int {
        appState.stocksData.reduce(0) { $0 + $1.totalCostBasis }
    }

    private func formatMoney(_ amount: Int) -> String {
        TornFormatter.formatMoney(amount)
    }

    private func openURL(_ urlString: String) {
        if let url = URL(string: urlString) {
            BrowserManager.shared.open(url)
        }
    }
}
