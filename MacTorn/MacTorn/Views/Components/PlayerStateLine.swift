import SwiftUI

/// Where the player is and whether they can act, in one line under their name: "Okay, in
/// Torn", "Flying to Japan", "In hospital 2:05". The release countdown itself also appears
/// in "Next up"; this line is the standing answer to "what state am I in".
struct PlayerStateLine: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if let data = appState.player.data {
            let status = data.status
            if let status, status.isInHospital {
                confinement(status, word: "In hospital", spoken: "In hospital", id: "uitest.status.hospital",
                            place: data.travel)
            } else if let status, status.isInJail {
                confinement(status, word: "In jail", spoken: "In jail", id: "uitest.status.jail", place: nil)
            } else {
                line(tone: freeTone(data.travel), text: freeText(status: status, travel: data.travel))
            }
        }
    }

    /// Hospital and jail tick against Torn's clock (issue #46), like every other countdown.
    private func confinement(_ status: Status, word: String, spoken: String, id: String, place: Travel?) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = status.timeRemaining(at: appState.player.serverClock.serverNow(context.date))
            let clock = TornFormatter.clock(remaining, zeroText: "0:00")
            let abroad = place.flatMap { $0.isAbroad ? $0.destination : nil }
            HStack(spacing: 6) {
                StateDot(tone: .alert)
                Text(abroad.map { "\(word) in \($0)" } ?? word)
                    .font(.boardCaption)
                    .foregroundStyle(Board.Tone.alert.ink)
                Text(clock)
                    .font(.figure(13))
                    .foregroundStyle(Board.Tone.alert.ink)
            }
            .transaction { $0.animation = nil }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(spoken), \(clock) remaining")
            .uiTestID(id)
        }
    }

    private func line(tone: Board.Tone, text: String) -> some View {
        HStack(spacing: 6) {
            StateDot(tone: tone)
            Text(text)
                .font(.boardCaption)
                .foregroundStyle(Board.inkSecondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    private func freeTone(_ travel: Travel?) -> Board.Tone {
        guard let travel else { return .ready }
        if travel.isTraveling { return .counting }
        return travel.isAbroad ? .idle : .ready
    }

    private func freeText(status: Status?, travel: Travel?) -> String {
        // Torn can report a flight before it sends the destination, so the place is dropped
        // rather than named "Unknown".
        if let travel, travel.isTraveling {
            return travel.destination.map { "Flying to \($0)" } ?? "Flying"
        }
        if let travel, travel.isAbroad {
            return travel.destination.map { "In \($0)" } ?? "Abroad"
        }
        let state = status?.description ?? "Okay"
        return travel == nil ? state : "\(state), in Torn"
    }
}
