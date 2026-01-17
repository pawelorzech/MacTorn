import SwiftUI

struct PropertiesView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Property Info
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "house.fill")
                            .foregroundColor(.brown)
                        Text("Properties")
                            .font(.caption.bold())
                    }
                    
                    if let properties = appState.propertiesData, !properties.isEmpty {
                        ForEach(Array(properties.enumerated()), id: \.offset) { index, property in
                            PropertyCard(property: property)
                        }
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "house.slash")
                                .font(.title2)
                                .foregroundColor(.secondary)
                            Text("No properties found")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    }
                }
                
                // Actions
                HStack(spacing: 8) {
                    ActionButton(title: "Properties", icon: "house.fill", color: .brown) {
                        openURL("https://www.torn.com/properties.php")
                    }
                    
                    ActionButton(title: "Estate Agents", icon: "building.2.fill", color: .blue) {
                        openURL("https://www.torn.com/estateagents.php")
                    }
                }
            }
            .padding()
        }
        .fixedSize(horizontal: false, vertical: true)
    }
    
    private func openURL(_ urlString: String) {
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Property Card
struct PropertyCard: View {
    let property: PropertyInfo
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(property.propertyType)
                    .font(.caption.bold())
                Spacer()
                if property.rented {
                    Text("Rented")
                        .font(.caption2)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.2))
                        .cornerRadius(4)
                }
            }
            
            Divider()
            
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Vault")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(formatMoney(property.vault))
                        .font(.caption.bold().monospacedDigit())
                        .foregroundColor(.green)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Upkeep")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(formatMoney(property.upkeep))
                        .font(.caption.bold().monospacedDigit())
                        .foregroundColor(.red)
                }
            }
            
            if property.daysUntilUpkeep > 0 {
                HStack {
                    Image(systemName: "clock")
                        .font(.caption2)
                    Text("Due in \(property.daysUntilUpkeep) days")
                        .font(.caption2)
                }
                .foregroundColor(property.daysUntilUpkeep <= 3 ? .orange : .secondary)
            }
        }
        .padding()
        .background(Color.brown.opacity(0.05))
        .cornerRadius(8)
    }
    
    private func formatMoney(_ amount: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "$"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(amount)"
    }
}
