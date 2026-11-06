import Foundation

/// The torn.com pages MacTorn links to. Torn moves pages now and then (the item market
/// left `imarket.php` for `page.php?sid=ItemMarket`), so each destination is spelled once.
enum TornLink {
    static let home = page("")
    static let items = page("item.php")
    static let itemMarket = page("page.php?sid=ItemMarket")
    static let travelAgency = page("travelagency.php")
    static let stocks = page("page.php?sid=stocks")
    static let bounties = page("bounties.php")
    static let hospital = page("hospitalview.php")
    static let gym = page("gym.php")
    static let crimes = page("crimes.php")
    static let forums = page("forums.php")
    static let trades = page("trade.php")
    static let faction = page("factions.php?step=your")
    static let factionWars = factionTab("wars")
    static let factionCrimes = factionTab("crimes")
    static let factionArmoury = factionTab("armoury")
    static let apiKeyPreferences = page("preferences.php#tab=api")

    static func itemMarket(itemID: Int) -> URL {
        page("page.php?sid=ItemMarket#/market/view=item&itemID=\(itemID)")
    }

    static func profile(_ playerID: Int) -> URL { page("profiles.php?XID=\(playerID)") }

    static func factionProfile(_ factionID: Int) -> URL { page("factions.php?step=profile&ID=\(factionID)") }

    static func forumThread(_ threadID: Int) -> URL { page("forums.php#/p=threads&t=\(threadID)") }

    static func trade(_ tradeID: Int) -> URL { page("trade.php#step=view&ID=\(tradeID)") }

    static func factionTab(_ tab: String) -> URL { page("factions.php?step=your#/tab=\(tab)") }

    static func page(_ path: String) -> URL {
        URL(string: "https://www.torn.com/\(path)")!
    }
}
