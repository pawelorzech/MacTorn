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

                TradesPanel()

                // MARK: - Cash Section
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "dollarsign.circle.fill")
                            .foregroundColor(.green)
                            .accessibilityHidden(true)
                        Text("Cash")
                            .font(.caption.bold())
                    }

                    if let money = appState.moneyData {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("On Hand")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(TornFormatter.formatMoney(money.cash))
                                    .font(.headline.monospacedDigit())
                                    .foregroundColor(.green)
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("On Hand: \(TornFormatter.formatMoney(money.cash))")
                            .uiTestID("uitest.money.cash")

                            Spacer()

                            VStack(alignment: .trailing, spacing: 4) {
                                Text("Vault")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(TornFormatter.formatMoney(money.vault))
                                    .font(.headline.monospacedDigit())
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Vault: \(TornFormatter.formatMoney(money.vault))")
                            .uiTestID("uitest.money.vault")
                        }

                        if money.cayman > 0 {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Cayman")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Text(TornFormatter.formatMoney(money.cayman))
                                        .font(.headline.monospacedDigit())
                                }
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("Cayman: \(TornFormatter.formatMoney(money.cayman))")
                                .uiTestID("uitest.money.cayman")
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
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Points: \(money.points)")
                            .uiTestID("uitest.money.points")

                            VStack {
                                Text("\(money.tokens)")
                                    .font(.caption.bold().monospacedDigit())
                                Text("Tokens")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Tokens: \(money.tokens)")
                            .uiTestID("uitest.money.tokens")
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
                    let propertyMarketTotal = NumericSafety.total((appState.propertiesData ?? []).map(\.marketprice))
                    let stocksMarketTotal = NumericSafety.optionalTotal(appState.stocksData.map {
                        $0.marketValue(using: appState.stocksMetadata)
                    })
                    let totalTracked = NumericSafety.optionalTotal([money.cash, money.vault, money.cayman, propertyMarketTotal, stocksMarketTotal])

                    HStack {
                        Image(systemName: "sum")
                            .foregroundColor(.green)
                            .accessibilityHidden(true)
                        Text("Total Tracked")
                            .font(.caption.bold())
                        Spacer()
                        Text(TornFormatter.formatMoney(totalTracked))
                            .font(.headline.monospacedDigit())
                            .foregroundColor(.green)
                    }
                    .padding()
                    .background(Color.green.opacity(reduceTransparency ? 0.35 : 0.12))
                    .cornerRadius(8)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Total Tracked: \(TornFormatter.formatMoney(totalTracked))")
                    .uiTestID("uitest.money.totalTracked")
                }

                // MARK: - Action Buttons
                HStack(spacing: 8) {
                    ActionButton(title: "Send Money", icon: "paperplane.fill", color: .blue) {
                        openTorn("https://www.torn.com/sendcash.php")
                    }

                    ActionButton(title: "Bazaar", icon: "cart.fill", color: .orange) {
                        openTorn("https://www.torn.com/bazaar.php")
                    }

                    ActionButton(title: "Bank", icon: "building.columns.fill", color: .purple) {
                        openTorn("https://www.torn.com/bank.php")
                    }
                }
            }
            .padding()
        }
        .accessibilityIdentifier("account.money")
    }
}

// MARK: - Action Button Component
struct ActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        TileButton(title: title, icon: icon, color: color,
                   iconFont: .body, titleFont: .caption2,
                   spacing: 4, verticalPadding: 8, cornerRadius: 8, opacity: 0.1,
                   action: action)
    }
}
