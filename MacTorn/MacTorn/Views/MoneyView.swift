import SwiftUI

struct MoneyView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.reduceTransparency) private var reduceTransparency

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {

                // MARK: - Cash Section
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "dollarsign.circle.fill")
                            .foregroundColor(.green)
                        Text("Cash")
                            .font(.caption.bold())
                    }

                    if let money = appState.moneyData {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("On Hand")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(formatMoney(money.cash))
                                    .font(.headline.monospacedDigit())
                                    .foregroundColor(.green)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 4) {
                                Text("Vault")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(formatMoney(money.vault))
                                    .font(.headline.monospacedDigit())
                            }
                        }

                        if money.cayman > 0 {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Cayman")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Text(formatMoney(money.cayman))
                                        .font(.headline.monospacedDigit())
                                }
                                Spacer()
                            }
                        }

                        Divider()

                        HStack(spacing: 16) {
                            VStack {
                                Text("\(money.points)")
                                    .font(.caption.bold().monospacedDigit())
                                Text("Points")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }

                            VStack {
                                Text("\(money.tokens)")
                                    .font(.caption.bold().monospacedDigit())
                                Text("Tokens")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        Text("Loading...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color.green.opacity(reduceTransparency ? 0.25 : 0.05))
                .cornerRadius(8)

                // MARK: - Properties Section
                if let properties = appState.propertiesData, !properties.isEmpty {
                    let totalMarketPrice = properties.reduce(0) { $0 + $1.marketprice }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "house.fill")
                                .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.2))
                            Text("Properties")
                                .font(.caption.bold())
                            Spacer()
                            Text("Market: \(formatMoney(totalMarketPrice))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        ForEach(properties) { property in
                            HStack(spacing: 6) {
                                Text(property.propertyType)
                                    .font(.caption2)
                                    .foregroundColor(.primary)
                                if property.rented {
                                    Text("Rented out" + (property.rentDaysLeft.map { " \($0)d" } ?? ""))
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.orange.opacity(reduceTransparency ? 0.5 : 0.2))
                                        .cornerRadius(3)
                                }
                                Spacer()
                                Text(formatMoney(property.marketprice))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundColor(.primary)
                            }
                        }
                    }
                    .padding()
                    .background(Color(red: 0.6, green: 0.4, blue: 0.2).opacity(reduceTransparency ? 0.25 : 0.08))
                    .cornerRadius(8)
                }

                // MARK: - Stocks Section
                if !appState.stocksData.isEmpty {
                    let totalMarketValue = appState.stocksData.reduce(0) { sum, stock in
                        sum + stock.marketValue(using: appState.stocksMetadata)
                    }
                    let totalCostBasis = appState.stocksData.reduce(0) { $0 + $1.totalCostBasis }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .foregroundColor(.blue)
                            Text("Stocks")
                                .font(.caption.bold())
                            Spacer()
                            Text("Market: \(formatMoney(totalMarketValue))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        ForEach(appState.stocksData) { stock in
                            let meta = appState.stocksMetadata[stock.stockId]
                            HStack(spacing: 6) {
                                if let meta = meta {
                                    Text(meta.acronym)
                                        .font(.caption2.bold())
                                        .foregroundColor(.primary)
                                    Text(meta.name)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                } else {
                                    Text("Stock #\(stock.stockId)")
                                        .font(.caption2)
                                        .foregroundColor(.primary)
                                }
                                Spacer()
                                Text("\(stock.totalShares.formatted())")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundColor(.secondary)
                                Text(formatMoney(stock.marketValue(using: appState.stocksMetadata)))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundColor(.primary)
                            }
                        }

                        if totalCostBasis > 0 {
                            HStack {
                                Text("Cost basis")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(formatMoney(totalCostBasis))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding()
                    .background(Color.blue.opacity(reduceTransparency ? 0.25 : 0.08))
                    .cornerRadius(8)
                }

                // MARK: - Total Tracked
                if let money = appState.moneyData {
                    let propertyMarketTotal = appState.propertiesData?.reduce(0) { $0 + $1.marketprice } ?? 0
                    let stocksMarketTotal = appState.stocksData.reduce(0) { sum, stock in
                        sum + stock.marketValue(using: appState.stocksMetadata)
                    }
                    let totalTracked = money.cash + money.vault + money.cayman + propertyMarketTotal + stocksMarketTotal

                    HStack {
                        Image(systemName: "sum")
                            .foregroundColor(.green)
                        Text("Total Tracked")
                            .font(.caption.bold())
                        Spacer()
                        Text(formatMoney(totalTracked))
                            .font(.headline.monospacedDigit())
                            .foregroundColor(.green)
                    }
                    .padding()
                    .background(Color.green.opacity(reduceTransparency ? 0.35 : 0.12))
                    .cornerRadius(8)
                }

                // MARK: - Action Buttons
                HStack(spacing: 8) {
                    ActionButton(title: "Send Money", icon: "paperplane.fill", color: .blue) {
                        openURL("https://www.torn.com/sendcash.php")
                    }

                    ActionButton(title: "Bazaar", icon: "cart.fill", color: .orange) {
                        openURL("https://www.torn.com/bazaar.php")
                    }

                    ActionButton(title: "Bank", icon: "building.columns.fill", color: .purple) {
                        openURL("https://www.torn.com/bank.php")
                    }
                }
            }
            .padding()
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func formatMoney(_ amount: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "$"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(amount)"
    }

    private func openURL(_ urlString: String) {
        if let url = URL(string: urlString) {
            BrowserManager.shared.open(url)
        }
    }
}

// MARK: - Action Button Component
struct ActionButton: View {
    @Environment(\.reduceTransparency) private var reduceTransparency
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                Text(title)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(color.opacity(reduceTransparency ? 0.4 : 0.1))
            .foregroundColor(color)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}
