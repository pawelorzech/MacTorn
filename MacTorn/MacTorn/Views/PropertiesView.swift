import SwiftUI

/// "What do I own and what is it worth": the combined market value, then one row per
/// property with the one thing that needs watching, the rent running out.
struct PropertiesView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        BoardPage {
            ModuleStateView(
                state: appState.presentationState(for: .properties, hasContent: appState.player.propertiesData != nil),
                onRetry: appState.refreshNow
            )

            if let properties = appState.player.propertiesData, !properties.isEmpty {
                totalHero(properties)
                BoardSection("Your properties", note: properties.count == 1 ? "1 property" : "\(properties.count) properties") {
                    ForEach(properties) { property in
                        PropertyCard(property: property)
                    }
                }
            } else if appState.player.propertiesData == nil {
                BoardSection("Your properties") {
                    BoardEmptyState(
                        title: "Property data unavailable",
                        detail: "Check the status line above, or whether your API key can read properties."
                    )
                }
            } else {
                BoardSection("Your properties") {
                    BoardEmptyState(
                        title: "No properties found",
                        detail: "Properties you buy in Torn appear here after the next refresh."
                    )
                }
            }

            BoardSection("Open in Torn") {
                TornLinks(
                    links: [
                        TornLinks.Link(title: "Properties", url: TornLink.page("properties.php")),
                        TornLinks.Link(title: "Estate agents", url: TornLink.page("estateagents.php")),
                    ],
                    columns: 2
                )
                .padding(.top, Board.Space.s)
            }
        }
        .accessibilityIdentifier("account.properties")
    }

    private func totalHero(_ properties: [PropertyInfo]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Market value")
                .font(.boardCaption)
                .foregroundStyle(Board.inkSecondary)
            Text(TornFormatter.formatMoney(NumericSafety.total(properties.map(\.marketprice))))
                .font(.figure(34))
                .foregroundStyle(Board.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Property row

/// One property: what it is and what it is worth, then a line of facts. Keeps its old name
/// because the UI tests and fixtures refer to it.
struct PropertyCard: View {
    let property: PropertyInfo

    var body: some View {
        BoardRow(verticalPadding: 9) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: Board.Space.m) {
                    Text(property.propertyType)
                        .font(.boardStrong)
                        .foregroundStyle(Board.ink)
                        .lineLimit(1)
                    Spacer(minLength: Board.Space.s)
                    Text(TornFormatter.formatMoney(property.marketprice))
                        .font(.figureValue)
                        .foregroundStyle(Board.ink)
                        .lineLimit(1)
                }

                if !property.status.isEmpty {
                    Text(property.status)
                        .font(.boardDetail)
                        .foregroundStyle(Board.inkSecondary)
                }

                if !facts.isEmpty {
                    Text(facts.joined(separator: ", "))
                        .font(.boardDetail)
                        .foregroundStyle(Board.inkSecondary)
                }

                if let days = property.rentDaysLeft, days > 0 {
                    Text("Rent ends in \(days) \(days == 1 ? "day" : "days")")
                        .font(.boardDetail.weight(.medium))
                        .foregroundStyle(rentTone(days: days).ink)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .uiTestID("uitest.property.\(property.id)")
    }

    private var facts: [String] {
        var parts: [String] = []
        if property.rented { parts.append("Rented out") }
        if property.happy > 0 { parts.append("\(TornFormatter.formatNumber(property.happy)) happy") }
        if property.cost > 0 { parts.append("cost \(TornFormatter.formatMoney(property.cost))") }
        return parts
    }

    /// Rent running out is the one thing here that is time-critical.
    private func rentTone(days: Int) -> Board.Tone {
        if days <= 1 { return .alert }
        if days <= 3 { return .counting }
        return .idle
    }

    /// Colour-only meaning (the "rented out" fact, the <=3-day rent-countdown
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
