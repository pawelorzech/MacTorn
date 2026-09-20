import SwiftUI

struct PropertiesView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.reduceTransparency) private var reduceTransparency
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ModuleStateView(
                    state: appState.presentationState(
                        endpointIDs: ["user.fast"],
                        hasContent: appState.propertiesData != nil,
                        staleAfter: 120
                    ),
                    onRetry: appState.refreshNow
                )

                // Property Info
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "house.fill")
                            .foregroundColor(.brown)
                            .accessibilityHidden(true)
                        Text("Properties")
                            .font(.caption.bold())
                        Spacer()
                        if let properties = appState.propertiesData, !properties.isEmpty {
                            Text("Market: \(TornFormatter.formatMoney(NumericSafety.total(properties.map(\.marketprice))))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if let properties = appState.propertiesData, !properties.isEmpty {
                        ForEach(properties) { property in
                            PropertyCard(property: property)
                        }
                    } else {
                        EmptyStateView(icon: "house.slash", title: "No properties found")
                    }
                }
                
                // Actions
                HStack(spacing: 8) {
                    ActionButton(title: "Properties", icon: "house.fill", color: .brown) {
                        openTorn("https://www.torn.com/properties.php")
                    }
                    
                    ActionButton(title: "Estate Agents", icon: "building.2.fill", color: .blue) {
                        openTorn("https://www.torn.com/estateagents.php")
                    }
                }
            }
            .padding()
        }
        .accessibilityIdentifier("account.properties")
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
                    Text(TornFormatter.formatMoney(property.marketprice))
                        .font(.caption.bold().monospacedDigit())
                        .foregroundColor(.green)
                }

                Spacer()

                if property.cost > 0 {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Cost")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(TornFormatter.formatMoney(property.cost))
                            .font(.caption.bold().monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                }
            }

            if property.happy > 0 {
                HStack {
                    Image(systemName: "face.smiling")
                        .font(.caption2)
                        .accessibilityHidden(true)
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
                        .accessibilityHidden(true)
                    Text("Rent ends in \(days) days")
                        .font(.caption2)
                }
                .foregroundColor(days <= 3 ? .orange : .secondary)
            }
        }
        .padding()
        .background(Color.brown.opacity(reduceTransparency ? 0.25 : 0.05))
        .cornerRadius(8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .uiTestID("uitest.property.\(property.id)")
    }

    /// Colour-only meaning (the "rented out" badge, the <=3-day rent-countdown
    /// urgency) folded into text so VoiceOver users get the same information
    /// sighted users read from colour alone.
    private var accessibilityDescription: String {
        var parts: [String] = [property.propertyType]

        if !property.status.isEmpty {
            parts.append(property.status)
        }
        if property.rented {
            parts.append("rented out")
        }

        parts.append("market value \(TornFormatter.formatMoney(property.marketprice))")
        if property.cost > 0 {
            parts.append("cost \(TornFormatter.formatMoney(property.cost))")
        }
        if property.happy > 0 {
            parts.append("\(property.happy) happy")
        }
        if let days = property.rentDaysLeft, days > 0 {
            parts.append(days <= 3
                ? "rent due in \(days) days, urgent"
                : "rent due in \(days) days")
        }

        return parts.joined(separator: ", ")
    }
}
