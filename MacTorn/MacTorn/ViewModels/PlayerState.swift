import Foundation
import Observation

/// Everything MacTorn knows about the signed-in player that came from Torn. An account
/// change replaces the whole object, so a field added here can never leak across
/// accounts.
@MainActor
@Observable
final class PlayerState {
    var data: TornResponse?
    var lastUpdated: Date?
    var moneyData: MoneyData?
    var battleStats: BattleStats?
    var recentAttacks: [AttackResult]?
    var activityEvents: [TornEvent] = []
    var unreadMessages: Int = 0
    var propertiesData: [PropertyInfo]?
    var stocksData: [StockHolding] = []
    var organizedCrime: OrganizedCrime2?
    var organizedCrimeUnavailableReason: String?
    var refills: Refills?
    var education: EducationStatus?
    var bountiesOnMe: [Bounty] = []
    var bountiesDataTimestamp: Date?
    var bountiesFetchedAt: Date?
    var bountiesCacheDelay: TimeInterval?
    /// Unread messages / events / awards / competition, from the point-in-time
    /// `notifications` selection. Cheap enough to refresh on every poll.
    var notificationCounts: TornNotifications?
    /// The virus currently being written, if any. Read rarely — see `fetchVirusIfNeeded`.
    var virus: VirusProgramming?
    var lastFetchTime: Date = Date()
    /// Mac↔Torn clock skew, re-derived from `server_time` on every successful snapshot. Every countdown
    /// in the app (travel, hospital, jail, chain, OC, cooldowns, bars) is measured through this, so the
    /// whole window agrees on one clock. Absent or implausible anchors leave it `.synchronized`, i.e. the
    /// plain local clock.
    var serverClock: ServerClock = .synchronized
    /// Absolute end-timestamps for active cooldowns, derived at fetch time from
    /// the server's response timestamp. The single source of truth that keeps
    /// the menu-bar and Status tab cooldown countdowns matching torn.com.
    var cooldownEnds: CooldownEnds?
    var travelSecondsRemaining: Int = 0
    var menuBarDisplay: MenuBarDisplay = .fallbackIcon
    @ObservationIgnored var previousTravel: Travel?
}
