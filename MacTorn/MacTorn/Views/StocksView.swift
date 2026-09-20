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

                if !appState.companion.enabled.contains(.stocks) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .foregroundColor(.blue)
                        Text("Stocks")
                            .font(.caption.bold())
                        Spacer()
                        if !appState.stocksData.isEmpty {
                            Text("Market: \(TornFormatter.formatMoney(totalMarketValue))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    if appState.stocksData.isEmpty {
                        EmptyStateView(icon: "chart.line.downtrend.xyaxis", title: "No stocks found")
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
                                Text(TornFormatter.formatMoney(stock.marketValue(using: appState.stocksMetadata)))
                                    .font(.caption2.monospacedDigit())
                            }
                        }

                        if totalCostBasis == nil || (totalCostBasis ?? 0) > 0 {
                            Divider()
                            HStack {
                                Text("Cost basis")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(TornFormatter.formatMoney(totalCostBasis))
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

                }
                StockBonusPanel()

                ActionButton(
                    title: "Stock Market",
                    icon: "chart.line.uptrend.xyaxis",
                    color: .blue
                ) {
                    openTorn("https://www.torn.com/page.php?sid=stocks")
                }
            }
            .padding()
        }
        .accessibilityIdentifier("account.stocks")
    }

    private var totalMarketValue: Int? {
        NumericSafety.optionalTotal(appState.stocksData.map { $0.marketValue(using: appState.stocksMetadata) })
    }

    private var totalCostBasis: Int? {
        NumericSafety.optionalTotal(appState.stocksData.map(\.totalCostBasis))
    }

}
