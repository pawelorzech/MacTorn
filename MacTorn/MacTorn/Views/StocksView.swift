import SwiftUI

/// "What are my shares worth": market value and cost basis first, then each holding.
struct StocksView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        BoardPage {
            ModuleStateView(
                state: appState.presentationState(for: .stocks, hasContent: !appState.player.stocksData.isEmpty),
                onRetry: appState.refreshNow
            )

            // With the stocks module on, the bonus panel replaces the plain holdings list.
            if !appState.companion.enabled.contains(.stocks) {
                holdings
            }

            StockBonusPanel()

            BoardSection("Open in Torn") {
                TornLinks(links: [TornLinks.Link(title: "Stock market", url: TornLink.stocks)], columns: 2)
                    .padding(.top, Board.Space.s)
            }
        }
        .accessibilityIdentifier("account.stocks")
    }

    // MARK: - Holdings

    @ViewBuilder
    private var holdings: some View {
        if appState.player.stocksData.isEmpty {
            BoardSection("Stocks") {
                BoardEmptyState(
                    title: "No stocks found",
                    detail: "Shares you buy on the Torn stock market appear here after the next refresh."
                )
            }
        } else {
            BoardSection("Portfolio") {
                ValueRow(label: "Market value", value: TornFormatter.formatMoney(totalMarketValue))
                if totalCostBasis == nil || (totalCostBasis ?? 0) > 0 {
                    ValueRow(label: "Cost basis", value: TornFormatter.formatMoney(totalCostBasis))
                }
            }

            let stocks = appState.player.stocksData
            BoardSection("Holdings", note: stocks.count == 1 ? "1 stock" : "\(stocks.count) stocks") {
                ForEach(stocks) { stock in
                    holdingRow(stock)
                }
            }
        }
    }

    private func holdingRow(_ stock: StockHolding) -> some View {
        let metadata = appState.stocksMetadata[stock.stockId]
        let value = TornFormatter.formatMoney(stock.marketValue(using: appState.stocksMetadata))
        let shares = "\(TornFormatter.formatNumber(stock.totalShares)) \(stock.totalShares == 1 ? "share" : "shares")"
        return BoardRow {
            HStack(alignment: .firstTextBaseline, spacing: Board.Space.m) {
                VStack(alignment: .leading, spacing: 1) {
                    if let metadata {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(metadata.acronym)
                                .font(.boardStrong)
                                .foregroundStyle(Board.ink)
                            Text(metadata.name)
                                .font(.boardCaption)
                                .foregroundStyle(Board.inkSecondary)
                                .lineLimit(1)
                        }
                    } else {
                        Text("Stock details unavailable")
                            .font(.boardStrong)
                            .foregroundStyle(Board.ink)
                            .lineLimit(1)
                    }
                    Text(shares)
                        .font(.boardDetail)
                        .foregroundStyle(Board.inkSecondary)
                }
                Spacer(minLength: Board.Space.s)
                Text(value)
                    .font(.figureValue)
                    .foregroundStyle(Board.ink)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(metadata?.name ?? "Stock details unavailable"), \(shares), market value \(value)")
    }

    private var totalMarketValue: Int? {
        NumericSafety.optionalTotal(appState.player.stocksData.map { $0.marketValue(using: appState.stocksMetadata) })
    }

    private var totalCostBasis: Int? {
        NumericSafety.optionalTotal(appState.player.stocksData.map(\.totalCostBasis))
    }

}
