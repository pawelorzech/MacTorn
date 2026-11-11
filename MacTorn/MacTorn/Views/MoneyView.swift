import SwiftUI

/// "What am I worth right now": the total across everything MacTorn can see, then the cash
/// and vault it is made of.
struct MoneyView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        BoardPage {
            ModuleStateView(
                state: appState.presentationState(for: .money, hasContent: appState.player.moneyData != nil),
                onRetry: appState.refreshNow
            )

            if let money = appState.player.moneyData {
                totalHero(money)
                moneySection(money)
            } else if appState.isLoading {
                Text("Loading money")
                    .font(.boardCaption)
                    .foregroundStyle(Board.inkSecondary)
            } else {
                // A completed refresh with no money data means the key can't read it, so
                // say so instead of spinning "Loading" forever.
                BoardEmptyState(
                    title: "No money data",
                    detail: "Your API key may not have access. Check its permissions in Settings."
                )
            }

            // Renders nothing unless the trades module is on.
            TradesPanel()

            BoardSection("Open in Torn") {
                TornLinks(links: [
                    TornLinks.Link(title: "Send money", url: TornLink.page("sendcash.php")),
                    TornLinks.Link(title: "Bazaar", url: TornLink.page("bazaar.php")),
                    TornLinks.Link(title: "Bank", url: TornLink.page("bank.php")),
                ])
                .padding(.top, Board.Space.s)
            }
        }
        .accessibilityIdentifier("account.money")
    }

    // MARK: - Total

    private func totalHero(_ money: MoneyData) -> some View {
        let propertyMarketTotal = NumericSafety.total((appState.player.propertiesData ?? []).map(\.marketprice))
        let stocksMarketTotal = NumericSafety.optionalTotal(appState.player.stocksData.map {
            $0.marketValue(using: appState.stocksMetadata)
        })
        let totalTracked = NumericSafety.optionalTotal([money.cash, money.vault, money.cayman, propertyMarketTotal, stocksMarketTotal])
        let amount = TornFormatter.formatMoney(totalTracked)

        return VStack(alignment: .leading, spacing: 2) {
            Text("Total tracked")
                .font(.boardCaption)
                .foregroundStyle(Board.inkSecondary)
            Text(amount)
                .font(.figure(34))
                .foregroundStyle(Board.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("Cash, vault, Cayman, properties and stocks")
                .font(.boardDetail)
                .foregroundStyle(Board.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Total Tracked: \(amount)")
        .uiTestID("uitest.money.totalTracked")
    }

    // MARK: - Rows

    private func moneySection(_ money: MoneyData) -> some View {
        BoardSection("Money") {
            MoneyLine(
                label: "On hand",
                value: TornFormatter.formatMoney(money.cash),
                spoken: "On Hand: \(TornFormatter.formatMoney(money.cash))"
            )
            .uiTestID("uitest.money.cash")

            MoneyLine(
                label: "Vault",
                value: TornFormatter.formatMoney(money.vault),
                spoken: "Vault: \(TornFormatter.formatMoney(money.vault))"
            )
            .uiTestID("uitest.money.vault")

            if money.cayman > 0 {
                MoneyLine(
                    label: "Cayman",
                    value: TornFormatter.formatMoney(money.cayman),
                    spoken: "Cayman: \(TornFormatter.formatMoney(money.cayman))"
                )
                .uiTestID("uitest.money.cayman")
            }

            MoneyLine(
                label: "Points",
                value: TornFormatter.formatNumber(money.points),
                spoken: "Points: \(money.points)"
            )
            .uiTestID("uitest.money.points")

            MoneyLine(
                label: "Tokens",
                value: TornFormatter.formatNumber(money.tokens),
                spoken: "Tokens: \(money.tokens)"
            )
            .uiTestID("uitest.money.tokens")
        }
    }
}

/// A `ValueRow` whose spoken label is fixed by the caller: VoiceOver and the UI tests read
/// "On Hand: $1,000,000" while the screen shows "On hand".
private struct MoneyLine: View {
    let label: String
    let value: String
    let spoken: String

    var body: some View {
        BoardRow {
            HStack(alignment: .firstTextBaseline, spacing: Board.Space.m) {
                Text(label)
                    .font(.boardBody)
                    .foregroundStyle(Board.ink)
                Spacer(minLength: Board.Space.s)
                Text(value)
                    .font(.figureValue)
                    .foregroundStyle(Board.ink)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }
}
