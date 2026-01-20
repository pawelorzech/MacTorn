import SwiftUI

struct MoneyView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.reduceTransparency) private var reduceTransparency
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Balance Section
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "dollarsign.circle.fill")
                            .foregroundColor(.green)
                        Text("Balance")
                            .font(.caption.bold())
                    }
                    
                    if let money = appState.moneyData {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Cash")
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
                            
                            VStack {
                                Text("\(money.cayman)")
                                    .font(.caption.bold().monospacedDigit())
                                Text("Cayman")
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

                // Actions
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
            NSWorkspace.shared.open(url)
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
