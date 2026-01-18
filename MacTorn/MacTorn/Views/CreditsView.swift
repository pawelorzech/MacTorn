import SwiftUI

struct CreditsView: View {
    @Binding var showCredits: Bool

    // MARK: - Contributors Data
    // Format: (name: "Username", tornID: 123456)
    // The tornID will automatically link to the Torn profile

    private let specialThanks: [TornContributor] = [
        // TODO: Add contributors here
        // Example: TornContributor(name: "bombel", tornID: 2362436),
        TornContributor(name: "Placeholder1", tornID: nil),
        TornContributor(name: "Placeholder2", tornID: nil),
        TornContributor(name: "Placeholder3", tornID: nil),
    ]

    private let testers: [TornContributor] = [
        // TODO: Add testers here
        TornContributor(name: "TesterPlaceholder1", tornID: nil),
        TornContributor(name: "TesterPlaceholder2", tornID: nil),
    ]

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

                Text("Thank you for your support!")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            ScrollView {
                VStack(spacing: 16) {
                    // Special Thanks Section
                    if !specialThanks.isEmpty {
                        contributorSection(
                            title: "Special Thanks",
                            icon: "star.fill",
                            iconColor: .yellow,
                            contributors: specialThanks
                        )
                    }

                    // Testers Section
                    if !testers.isEmpty {
                        contributorSection(
                            title: "Beta Testers",
                            icon: "checkmark.seal.fill",
                            iconColor: .green,
                            contributors: testers
                        )
                    }
                }
                .padding(.horizontal)
            }
            .frame(maxHeight: 200)

            Spacer()

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
        .frame(width: 320)
    }

    // MARK: - Section View
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

    // MARK: - Helper
    private func openTornProfile(_ tornID: Int) {
        let urlString = "https://www.torn.com/profiles.php?XID=\(tornID)"
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
