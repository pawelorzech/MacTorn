import SwiftUI

/// The board itself: what can be done right now, then everything that is counting down,
/// soonest first. One timeline for bars, cooldowns, flights, hospital, education, OCs and
/// the chain, ticking once a second against Torn's clock.
struct NextUpSection: View {
    @Environment(AppState.self) private var appState
    @AppStorage(StoredPreference.boosterCooldownTarget) private var boosterTarget: BoosterCooldownTarget = .boosters

    private struct ReadyAction: Identifiable {
        let id: String
        let title: String
        let spoken: String
        let url: URL
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            let events = appState.nextEvents(now: now)
            let ready = readyActions(events: events, now: now)
            let chain = appState.liveChain.flatMap { ChainView.mode(for: $0) == .hidden ? nil : $0 }
            // The chain has its own row (it also knows the hit count), so its bare
            // "Chain timeout" event is left out of the generic list.
            let upcoming = events.filter { !$0.isReady && $0.category != .chain }

            VStack(alignment: .leading, spacing: 18) {
                if !ready.isEmpty {
                    readySection(ready)
                }
                if chain != nil || !upcoming.isEmpty {
                    BoardSection("Next up", note: "soonest first") {
                        if let chain {
                            ChainView(chain: chain, serverClock: appState.player.serverClock)
                        }
                        ForEach(Array(upcoming.enumerated()), id: \.element.id) { index, event in
                            row(event, now: now)
                                .uiTestID(ready.isEmpty && chain == nil && index == 0 ? "uitest.nextAction" : "nextUp.\(event.id)")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Ready now

    private func readySection(_ actions: [ReadyAction]) -> some View {
        BoardSection("Ready now") {
            VStack(alignment: .leading, spacing: 6) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                    ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                        Button(action.title) { BrowserManager.shared.open(action.url) }
                            .buttonStyle(.board(.ready))
                            .accessibilityLabel(action.spoken)
                            .accessibilityHint("Opens Torn in your browser")
                            .uiTestID(index == 0 ? "uitest.nextAction" : "ready.\(action.id)")
                    }
                }
                if let unclaimed = appState.player.refills?.unclaimed, !unclaimed.isEmpty,
                   actions.contains(where: { $0.id == "refills" }) {
                    Text("Refills not claimed today: \(unclaimed.joined(separator: ", "))")
                        .font(.boardDetail)
                        .foregroundStyle(Board.inkSecondary)
                }
            }
            .padding(.top, Board.Space.s)
        }
    }

    private func readyActions(events: [NextEvent], now: Date) -> [ReadyAction] {
        // The three cooldowns are shown whenever they are over, whatever is hidden from the
        // timeline: a hidden category drops its countdown row, never the way to act on it.
        var actions: [ReadyAction] = []

        if events.contains(where: { $0.category == .refills && $0.isReady }) {
            actions.append(ReadyAction(id: "refills", title: "Refills", spoken: "Claim refills",
                                       url: TornLink.page("page.php?sid=points")))
        }
        if isOver(\.drugEndsAt, \.drug, now: now) {
            actions.append(ReadyAction(id: "drug", title: "Drug", spoken: "Use Drug",
                                       url: TornLink.page("item.php#drugs-items")))
        }
        if isOver(\.medicalEndsAt, \.medical, now: now) {
            actions.append(ReadyAction(id: "medical", title: "Medical", spoken: "Use Medical",
                                       url: TornLink.page("item.php#medical-items")))
        }
        if isOver(\.boosterEndsAt, \.booster, now: now) {
            actions.append(ReadyAction(id: "booster", title: boosterTarget.title.replacingOccurrences(of: "Boosters", with: "Booster"),
                                       spoken: "Use \(boosterTarget == .alcohol ? "Alcohol" : "Booster")",
                                       url: boosterTarget.itemsURL))
        }
        if events.contains(where: { $0.category == .stockBonus && $0.isReady }) {
            actions.append(ReadyAction(id: "stockBonus", title: "Stock bonus", spoken: "Collect stock bonus",
                                       url: TornLink.stocks))
        }
        return actions
    }

    /// A cooldown is over when its end is in Torn's past. The absolute end is preferred;
    /// the seconds-left snapshot is the fallback when no end could be computed.
    private func isOver(_ end: KeyPath<CooldownEnds, Int>, _ left: KeyPath<Cooldowns, Int>, now: Date) -> Bool {
        if let ends = appState.player.cooldownEnds {
            let endsAt = ends[keyPath: end]
            return endsAt <= 0 || endsAt <= appState.player.serverClock.serverUnix(now)
        }
        if let cooldowns = appState.player.data?.cooldowns {
            return cooldowns[keyPath: left] <= 0
        }
        return false
    }

    // MARK: - Next up

    private func row(_ event: NextEvent, now: Date) -> some View {
        let value = event.eta < 86_400 ? TornFormatter.clock(event.eta) : TornFormatter.coarseDuration(event.eta)
        return CountdownRow(
            tone: tone(for: event),
            title: event.title,
            detail: Self.when(now.addingTimeInterval(TimeInterval(event.eta)), from: now),
            value: value,
            progress: progress(for: event)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(event.title), in \(TornFormatter.compactETA(event.eta))")
    }

    private func tone(for event: NextEvent) -> Board.Tone {
        switch event.category {
        case .hospital, .jail: return .alert
        default: return event.eta >= 86_400 ? .idle : .counting
        }
    }

    /// Only rows that can honestly say how far along they are get a progress line.
    private func progress(for event: NextEvent) -> Double? {
        let bars = appState.player.data?.bars
        switch event.category {
        case .energy: return bars.map { NumericSafety.progress(current: $0.energy.current, maximum: $0.energy.maximum) }
        case .nerve: return bars.map { NumericSafety.progress(current: $0.nerve.current, maximum: $0.nerve.maximum) }
        case .happy: return bars.map { NumericSafety.progress(current: $0.happy.current, maximum: $0.happy.maximum) }
        case .life: return bars.map { NumericSafety.progress(current: $0.life.current, maximum: $0.life.maximum) }
        case .travel:
            guard let travel = appState.player.data?.travel,
                  let arrival = travel.timestamp, let departure = travel.departed else { return nil }
            return Travel.flightProgress(arrival: arrival, departure: departure, remainingSeconds: event.eta)
        default: return nil
        }
    }

    /// "at 13:44" today, "Friday at 14:10" otherwise — the wall-clock moment on this Mac.
    static func when(_ date: Date, from now: Date) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDate(date, inSameDayAs: now) { return "at \(time)" }
        if Calendar.current.isDate(date, inSameDayAs: now.addingTimeInterval(86_400)) { return "tomorrow at \(time)" }
        return "\(date.formatted(.dateTime.weekday(.wide))) at \(time)"
    }
}
