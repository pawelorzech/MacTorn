import SwiftUI

struct MoneyView: View {
    @EnvironmentObject var appState: AppState
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
                    let totalPropertyVault = properties.reduce(0) { $0 + $1.vault }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "house.fill")
                                .foregroundColor(Color(red: 0.6, green: 0.4, blue: 0.2))
                            Text("Properties")
                                .font(.caption.bold())
                            Spacer()
                            Text("Vault Total: \(formatMoney(totalPropertyVault))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        ForEach(properties) { property in
                            HStack {
                                Text(property.propertyType)
                                    .font(.caption2)
                                    .foregroundColor(.primary)
                                Spacer()
                                Text(formatMoney(property.vault))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding()
                    .background(Color(red: 0.6, green: 0.4, blue: 0.2).opacity(reduceTransparency ? 0.25 : 0.08))
                    .cornerRadius(8)
                }

                // MARK: - Stocks Section
                if !appState.stocksData.isEmpty {
                    let totalCostBasis = appState.stocksData.reduce(0) { $0 + $1.totalCostBasis }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .foregroundColor(.blue)
                            Text("Stocks")
                                .font(.caption.bold())
                            Spacer()
                            Text("Cost Basis: \(formatMoney(totalCostBasis))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        ForEach(appState.stocksData) { stock in
                            HStack {
                                Text("Stock #\(stock.stockId)")
                                    .font(.caption2)
                                    .foregroundColor(.primary)
                                Spacer()
                                Text("\(stock.totalShares) shares")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundColor(.secondary)
                                Text(formatMoney(stock.totalCostBasis))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundColor(.secondary)
                            }
                        }

                        Text("Cost basis shown (market prices require separate API)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .italic()
                    }
                    .padding()
                    .background(Color.blue.opacity(reduceTransparency ? 0.25 : 0.08))
                    .cornerRadius(8)
                }

                // MARK: - Total Tracked
                if let money = appState.moneyData {
                    let propertyVaultTotal = appState.propertiesData?.reduce(0) { $0 + $1.vault } ?? 0
                    let stocksCostBasis = appState.stocksData.reduce(0) { $0 + $1.totalCostBasis }
                    let totalTracked = money.cash + money.vault + money.cayman + propertyVaultTotal + stocksCostBasis

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
