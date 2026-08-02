import SwiftUI

struct CreditsView: View {
    @Environment(\.reduceTransparency) private var reduceTransparency
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
        VStack(spacing: 16) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "heart.fill")
                    .font(.largeTitle)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.pink, .red],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Text("Credits")
                    .font(.title2.bold())
            }

            Divider()

            ScrollView {
                VStack(spacing: 14) {
                    // Developer Section
                    developerSection

                    // Special Thanks Section
                    contributorSection(
                        title: "Special Thanks",
                        icon: "star.fill",
                        iconColor: .yellow,
                        contributors: specialThanks
                    )

                    // Faction Section
                    factionSection
                }
                .padding(.horizontal)
            }

            // Back Button
            Button {
                showCredits = false
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Back to Settings")
                }
                .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
        }
        .padding()
        .frame(width: 320, height: 480)
    }

    // MARK: - Developer Section
    private var developerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "hammer.fill")
                    .foregroundColor(.orange)
                    .accessibilityHidden(true)
                Text("Created by")
                    .font(.subheadline.bold())
            }

            Button {
                if let tornID = developer.tornID {
                    openTornProfile(tornID)
                }
            } label: {
                HStack {
                    Text(developer.name)
                        .font(.caption.bold())
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(Color.orange.opacity(reduceTransparency ? 0.4 : 0.1))
            .cornerRadius(8)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Created by \(developer.name)")
            .uiTestID("uitest.credits.developer")
        }
    }

    // MARK: - Faction Section
    private var factionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "shield.fill")
                    .foregroundColor(.blue)
                    .accessibilityHidden(true)
                Text("Faction")
                    .font(.subheadline.bold())
            }

            Button {
                openFaction(factionID)
            } label: {
                HStack {
                    Text(factionName)
                        .font(.caption)
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(Color.secondary.opacity(reduceTransparency ? 0.4 : 0.1))
            .cornerRadius(8)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Faction: \(factionName)")
            .uiTestID("uitest.credits.faction")
        }
    }

    // MARK: - Contributors Section
    @ViewBuilder
    private func contributorSection(
        title: String,
        icon: String,
        iconColor: Color,
        contributors: [TornContributor]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.subheadline.bold())
            }

            VStack(spacing: 4) {
                ForEach(contributors) { contributor in
                    contributorRow(contributor)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(Color.secondary.opacity(reduceTransparency ? 0.4 : 0.1))
            .cornerRadius(8)
        }
    }

    // MARK: - Contributor Row
    @ViewBuilder
    private func contributorRow(_ contributor: TornContributor) -> some View {
        if let tornID = contributor.tornID {
            Button {
                openTornProfile(tornID)
            } label: {
                HStack {
                    Text(contributor.name)
                        .font(.caption)
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Contributor: \(contributor.name)")
            .uiTestID("uitest.credits.contributor.\(contributor.name)")
        } else {
            HStack {
                Text(contributor.name)
                    .font(.caption)
                    .foregroundColor(.primary)
                Spacer()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Contributor: \(contributor.name)")
            .uiTestID("uitest.credits.contributor.\(contributor.name)")
        }
    }

    // MARK: - URL Helpers
    private func openTornProfile(_ tornID: Int) {
        let urlString = "https://www.torn.com/profiles.php?XID=\(tornID)"
        if let url = URL(string: urlString) {
            BrowserManager.shared.open(url)
        }
    }

    private func openFaction(_ factionID: Int) {
        let urlString = "https://www.torn.com/factions.php?step=profile&ID=\(factionID)"
        if let url = URL(string: urlString) {
            BrowserManager.shared.open(url)
        }
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
