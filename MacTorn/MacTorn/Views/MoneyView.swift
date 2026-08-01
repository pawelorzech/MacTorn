import SwiftUI

struct MoneyView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.reduceTransparency) private var reduceTransparency

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ModuleStateView(
                    state: appState.presentationState(
                        endpointIDs: ["user.fast"],
                        hasContent: appState.moneyData != nil,
                        staleAfter: 120
                    ),
                    onRetry: appState.refreshNow
                )

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
                    } else if appState.lastUpdated == nil {
                        Text("Loading...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        // A completed refresh with no money data means the key can't
                        // read it — say so instead of spinning "Loading…" forever.
                        Text("No money data. Your API key may not have access.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding()
                .background(Color.green.opacity(reduceTransparency ? 0.25 : 0.05))
                .cornerRadius(8)

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
        .accessibilityIdentifier("account.money")
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
                    .font(.body)
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
