import SwiftUI

struct PropertiesView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.reduceTransparency) private var reduceTransparency
    
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
            BrowserManager.shared.open(url)
        }
    }
}

// MARK: - Property Card
struct PropertyCard: View {
    @Environment(\.reduceTransparency) private var reduceTransparency
    let property: PropertyInfo
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(property.propertyType)
                    .font(.caption.bold())
                Spacer()
                if property.rented {
                    Text("Rented out")
                        .font(.caption2)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(reduceTransparency ? 0.5 : 0.2))
                        .cornerRadius(4)
                }
            }

            if !property.status.isEmpty {
                Text(property.status)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Market")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(formatMoney(property.marketprice))
                        .font(.caption.bold().monospacedDigit())
                        .foregroundColor(.green)
                }

                Spacer()

                if property.cost > 0 {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Cost")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(formatMoney(property.cost))
                            .font(.caption.bold().monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                }
            }

            if property.happy > 0 {
                HStack {
                    Image(systemName: "face.smiling")
                        .font(.caption2)
                    Text("\(property.happy) happy")
                        .font(.caption2)
                    Spacer()
                }
                .foregroundColor(.secondary)
            }

            if let days = property.rentDaysLeft, days > 0 {
                HStack {
                    Image(systemName: "clock")
                        .font(.caption2)
                    Text("Rent ends in \(days) days")
                        .font(.caption2)
                }
                .foregroundColor(days <= 3 ? .orange : .secondary)
            }
        }
        .padding()
        .background(Color.brown.opacity(reduceTransparency ? 0.25 : 0.05))
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
