import SwiftUI

struct CreditsView: View {
    @Binding var showCredits: Bool

    // MARK: - Developer
    private let developer = TornContributor(name: "bombel", tornID: 2362436)

    // MARK: - Special Thanks
    private let specialThanks: [TornContributor] = [
        TornContributor(name: "kaszmir", tornID: 3913934),
        TornContributor(name: "dylanwishop", tornID: 3918903),
        TornContributor(name: "constanziagatta", tornID: 3961012),
    ]

    // MARK: - Faction
    private let factionName = "The Masters"
    private let factionID = 11559

    // MARK: - Company
    private let companyName = "Glory Holes Productions"
    private let companyOwnerID = 2362436

    var body: some View {
        VStack(spacing: 16) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 36))
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

                    // Company Section
                    companySection
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
                Text("Created by")
                    .font(.subheadline.bold())
            }

            Button {
                openTornProfile(developer.tornID!)
            } label: {
                HStack {
                    Text(developer.name)
                        .font(.caption.bold())
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(8)
        }
    }

    // MARK: - Faction Section
    private var factionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "shield.fill")
                    .foregroundColor(.blue)
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
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
        }
    }

    // MARK: - Company Section
    private var companySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "building.2.fill")
                    .foregroundColor(.purple)
                Text("Company")
                    .font(.subheadline.bold())
            }

            Button {
                openCompany(companyOwnerID)
            } label: {
                HStack {
                    Text(companyName)
                        .font(.caption)
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
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
            .background(Color.secondary.opacity(0.1))
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
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
        } else {
            HStack {
                Text(contributor.name)
                    .font(.caption)
                    .foregroundColor(.primary)
                Spacer()
            }
        }
    }

    // MARK: - URL Helpers
    private func openTornProfile(_ tornID: Int) {
        let urlString = "https://www.torn.com/profiles.php?XID=\(tornID)"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    private func openFaction(_ factionID: Int) {
        let urlString = "https://www.torn.com/factions.php?step=profile&ID=\(factionID)"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    private func openCompany(_ ownerID: Int) {
        let urlString = "https://www.torn.com/joblist.php#/p=corpinfo&userID=\(ownerID)"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
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
