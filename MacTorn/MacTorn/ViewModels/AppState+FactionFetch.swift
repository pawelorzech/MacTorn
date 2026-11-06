import Foundation

extension AppState {
    func fetchFactionData() async {
        guard let payload = await requester.fetch("faction.basic", decode: FactionStore.decodeBasic).value else {
            return
        }
        // Torn's `chain.timeout` is seconds remaining, not a timestamp. Resolve it to an
        // absolute server-clock expiry here, at the boundary, so every consumer downstream
        // compares it against `serverNow` — see `FactionChain.resolvingExpiry`.
        faction.basic = payload.resolvingChainExpiry(fetchedAt: Date(), clock: player.serverClock)
        checkChainNotification()
    }

    /// Ranked wars and news are heavy and slow-changing, and news is row-based, so both
    /// are read on the registry's five-minute interval rather than every poll.
    func fetchFactionV2Data() async {
        if requester.isDue("faction.rankedwars"),
           let wars = await requester.fetch("faction.rankedwars", decode: FactionStore.decodeWars).value {
            faction.wars = wars
        }
        if requester.isDue("faction.news"),
           let news = await requester.fetch("faction.news", decode: FactionStore.decodeNews).value {
            faction.news = news
        }
    }
}
