import SwiftUI

struct CreditsView: View {
    @Binding var showCredits: Bool

    // MARK: - Developer
    private let developer = TornContributor(name: "bombel", tornID: TornConstants.developerID)

    // MARK: - Special Thanks
    private let specialThanks: [TornContributor] = [
        TornContributor(name: "Greeney", tornID: nil),
        TornContributor(name: "kaszmir", tornID: 3913934),
        TornContributor(name: "dylanwishop", tornID: 3918903),
        TornContributor(name: "constanziagatta", tornID: 3961012),
    ]

    // MARK: - Faction
    private let factionName = "The Masters"
    private let factionID = 11559

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Board.Space.s) {
                Text("Credits")
                    .font(.boardTitle)
                    .foregroundStyle(Board.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: Board.Space.s)
                Button("Back to Settings") {
                    showCredits = false
                }
                .buttonStyle(.board)
            }
            .padding(.horizontal, Board.gutter)
            .padding(.top, Board.Space.m)
            .padding(.bottom, Board.Space.m)

            BoardPage {
                developerSection
                contributorSection(title: "Special thanks", contributors: specialThanks)
                factionSection
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Board.surface)
    }

    // MARK: - Developer Section
    private var developerSection: some View {
        BoardSection("Created by") {
            Button {
                if let tornID = developer.tornID {
                    openTornProfile(tornID)
                }
            } label: {
                linkRow(developer.name, strong: true)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Created by \(developer.name)")
            .uiTestID("uitest.credits.developer")
        }
    }

    // MARK: - Faction Section
    private var factionSection: some View {
        BoardSection("Faction") {
            Button {
                openFaction(factionID)
            } label: {
                linkRow(factionName)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Faction: \(factionName)")
            .uiTestID("uitest.credits.faction")
        }
    }

    // MARK: - Contributors Section
    @ViewBuilder
    private func contributorSection(title: String, contributors: [TornContributor]) -> some View {
        BoardSection(title) {
            ForEach(contributors) { contributor in
                contributorRow(contributor)
            }
        }
    }

    // MARK: - Contributor Row
    @ViewBuilder
    private func contributorRow(_ contributor: TornContributor) -> some View {
        if let tornID = contributor.tornID {
            Button {
                openTornProfile(tornID)
            } label: {
                linkRow(contributor.name)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Contributor: \(contributor.name)")
            .uiTestID("uitest.credits.contributor.\(contributor.name)")
        } else {
            BoardRow {
                Text(contributor.name)
                    .font(.boardBody)
                    .foregroundStyle(Board.ink)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Contributor: \(contributor.name)")
            .uiTestID("uitest.credits.contributor.\(contributor.name)")
        }
    }

    /// A name that opens a Torn page: the name, and the arrow that says so.
    private func linkRow(_ name: String, strong: Bool = false) -> some View {
        BoardRow {
            HStack {
                Text(name)
                    .font(strong ? .boardStrong : .boardBody)
                    .foregroundStyle(Board.ink)
                Spacer()
                Image(systemName: "arrow.up.right.square")
                    .font(.boardDetail)
                    .foregroundStyle(Board.inkSecondary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
    }

    // MARK: - URL Helpers
    private func openTornProfile(_ tornID: Int) {
        BrowserManager.shared.open(TornLink.profile(tornID))
    }

    private func openFaction(_ factionID: Int) {
        BrowserManager.shared.open(TornLink.factionProfile(factionID))
    }

}

// MARK: - Contributor Model
struct TornContributor: Identifiable {
    let id = UUID()
    let name: String
    let tornID: Int?

    init(name: String, tornID: Int?) {
        self.name = name
        self.tornID = tornID
    }
}

#Preview {
    CreditsView(showCredits: .constant(true))
}
