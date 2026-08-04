import Foundation

// MARK: - Notification De-duplication (Etap E)
//
// Fixes the chain-expiring bug: the previous code fired "Chain Expiring!" on *every*
// poll while the chain timeout was under 60s — a burst of identical banners every
// refresh interval. This coordinator makes an alert fire exactly once per distinct
// occurrence of an event. The dedup state is persisted, so it survives an app
// restart (relaunching mid-danger-window must not re-alert), yet it re-arms once the
// situation clears so a genuinely new event alerts again.
//
// Two primitives cover the Etap E categories:
//
//  • `shouldFireOnEdge(_:active:seedOnFirstSight:)` — a rising-edge latch. Returns true
//    the first time `active` becomes true, then false until `active` returns to false
//    (re-arm). Used for the chain danger window (active = 0 < timeout < 60s), the bar
//    thresholds, the cooldown-ready alerts and hospital/jail release.
//
//    `seedOnFirstSight` is what makes those survive a relaunch. Because the latch is
//    persisted *including its cleared state*, "never observed" and "observed, inactive"
//    are distinguishable: the first ever observation of a key records the state and stays
//    silent, whatever it is, while every later observation is a real edge — even when the
//    transition happened while the app was closed. Without the seeding half, a fresh
//    install showing three ready cooldowns would open with three banners; without the
//    persistence half, a cooldown that expires between launches is silently swallowed,
//    which is the bug in #47.
//
//    Every latch also records *when* it was observed, and an observation older than
//    `stalenessWindow` counts as a first sight. Without the timestamp the latch cannot
//    tell an edge from thirty seconds ago from one from three weeks ago and fires either
//    way: quit while in hospital with cooldowns running, come back from holiday, and the
//    first poll produces the exact banner storm seeding exists to prevent — displaced
//    from first-install to first-launch-after-a-gap. The window is deliberately generous
//    (see `stalenessWindow`) so #47's intent survives: an edge that fell across a restart
//    or a lunch break is still news, one that fell across a holiday is not.
//
//  • `shouldFireOnce(_:epoch:)` — fires once per distinct `epoch` value for a key.
//    Used for per-instance events keyed by a stable identity: OC ready (OC id),
//    landing (destination + arrival time), forum new posts (last post id),
//    price alert (item id + crossed threshold), bounty (bounty id).
//
// Both stores are bounded. Their keys embed unbounded identities (bounty ids, market
// item ids, per-rule thresholds) and nothing ever deletes a stale one, so an uncapped
// store grows for the lifetime of the install. Eviction is least-recently-*touched*:
// every call for a key refreshes its recency, including a call whose answer is "already
// alerted". An entry that is still being re-checked on each poll can therefore never age
// out from under a live dedup and re-notify. (#47 / #53)
@MainActor
final class NotificationCoordinator {
    /// Rows kept per persisted dedup store. Far above any plausible working set (a
    /// handful of latches plus the bounties and market items currently in play), far
    /// below anything that would make the store a memory or disk concern.
    static let maxTrackedKeys = 256

    /// Floor for `stalenessWindow`. An hour comfortably covers the gaps #47 is about — a
    /// relaunch, a reboot, a lunch break — while being far short of "I was away".
    static let minimumStalenessWindow: TimeInterval = 60 * 60

    private let defaults: UserDefaults
    private let time: TimeSource
    private static let latchesStoreID = "notifications.latched.v2"
    private static let epochsStoreID = "notifications.epochs.v2"
    /// v1 held an uncapped string array / dictionary in a different encoding. Dropped on
    /// the first launch of this version; worst case is one alert suppressed or repeated
    /// on the upgrade poll.
    private static let retiredStoreIDs = ["notifications.latched.v1", "notifications.epochs.v1"]

    private static let latchedValue = "1"
    private static let clearedValue = "0"

    /// Poll cadence in seconds, mirrored from `AppState.refreshInterval`. Only feeds
    /// `stalenessWindow`; nothing here schedules anything.
    var refreshInterval: TimeInterval = 30

    /// How old a recorded observation may be and still count as "the previous state"
    /// rather than "no state at all". `max(1 h, 4 × refreshInterval)`: the floor keeps
    /// restart- and break-sized gaps alerting, and the multiple keeps the window at least
    /// a few polls wide should the cadence ever be slowed to something coarse, so a
    /// merely-slow poller never mistakes its own last poll for ancient history.
    var stalenessWindow: TimeInterval {
        max(Self.minimumStalenessWindow, 4 * refreshInterval)
    }

    /// Last observed `active` state per edge key, with the instant it was observed.
    /// Presence means "observed at least once" and the instant means "recently enough to
    /// still be the previous state" — both distinctions feed `seedOnFirstSight`.
    private var latches: BoundedRecencyStore
    /// Last epoch value alerted for each key.
    private var epochs: BoundedRecencyStore

    init(defaults: UserDefaults = .standard, time: TimeSource = SystemTimeSource()) {
        self.defaults = defaults
        self.time = time
        self.latches = BoundedRecencyStore(
            encoded: defaults.stringArray(forKey: Self.latchesStoreID) ?? [],
            capacity: Self.maxTrackedKeys
        )
        self.epochs = BoundedRecencyStore(
            encoded: defaults.stringArray(forKey: Self.epochsStoreID) ?? [],
            capacity: Self.maxTrackedKeys
        )
        for retired in Self.retiredStoreIDs { defaults.removeObject(forKey: retired) }
    }

    /// Rising-edge latch. Fires (returns true) exactly once when `active` transitions
    /// from false to true, then stays silent until `active` returns to false.
    ///
    /// - Parameter seedOnFirstSight: when true, the very first observation of `key`
    ///   records the state and returns false whatever it is. Use it for any alert whose
    ///   "active" condition can legitimately already hold at launch. An observation older
    ///   than `stalenessWindow` counts as a first sight too — a transition nobody saw for
    ///   three weeks is not news, and announcing it is the storm this flag prevents.
    @discardableResult
    func shouldFireOnEdge(_ key: String, active: Bool, seedOnFirstSight: Bool = false) -> Bool {
        let now = time.now
        let observed = latches.entry(for: key)
        // A row with no usable timestamp is a pre-timestamp row written by an older
        // build: its age is unknown, so it is treated as stale rather than trusted.
        let firstSight = observed.map { isStale($0.observedAt, now: now) } ?? true
        let wasActive = !firstSight && observed?.value == Self.latchedValue
        let fire = active && !wasActive && !(firstSight && seedOnFirstSight)
        latches.record(key, as: active ? Self.latchedValue : Self.clearedValue, at: now)
        persistLatches()
        return fire
    }

    /// Fires (returns true) once per distinct `epoch` for `key`. A new epoch re-alerts;
    /// the same epoch is suppressed, even across app restarts. A suppressed call still
    /// refreshes the key's recency, so anything polled regularly is never evicted.
    ///
    /// No staleness rule here: an epoch identifies one specific occurrence (this bounty,
    /// this OC), so a remembered epoch means "already announced" no matter how long ago —
    /// exactly what should stay suppressed.
    @discardableResult
    func shouldFireOnce(_ key: String, epoch: String) -> Bool {
        let alreadyAlerted = (epochs.entry(for: key)?.value == epoch)
        epochs.record(key, as: epoch, at: time.now)
        persistEpochs()
        return !alreadyAlerted
    }

    /// Whether an observation recorded at `observedAt` is too old to count as the
    /// previous state. A `nil` instant (row from before timestamps existed) is unknown
    /// and therefore stale; an instant in the future (clock moved backwards) is not.
    private func isStale(_ observedAt: Date?, now: Date) -> Bool {
        guard let observedAt else { return true }
        return now.timeIntervalSince(observedAt) > stalenessWindow
    }

    /// Whether `key` is currently latched — exposed for diagnostics/tests.
    func isLatched(_ key: String) -> Bool { latches.entry(for: key)?.value == Self.latchedValue }

    /// When `key` was last observed, or `nil` if never (or by a pre-timestamp build).
    /// Exposed for diagnostics/tests.
    func lastObserved(_ key: String) -> Date? { latches.entry(for: key)?.observedAt }

    /// Forget all dedup state (used when the key changes, or in tests).
    func reset() {
        latches.removeAll()
        epochs.removeAll()
        defaults.removeObject(forKey: Self.latchesStoreID)
        defaults.removeObject(forKey: Self.epochsStoreID)
    }

    private func persistLatches() {
        defaults.set(latches.encoded, forKey: Self.latchesStoreID)
    }

    private func persistEpochs() {
        defaults.set(epochs.encoded, forKey: Self.epochsStoreID)
    }
}

// MARK: - Bounded, recency-ordered string map

/// A capped name→(value, observation instant) map that evicts the least-recently-touched
/// entry.
///
/// Persisted as a plain `[String]` in recency order (coldest first) so the *ordering* —
/// not just the contents — round-trips through `UserDefaults`. A dictionary would lose it
/// and a relaunch would then evict arbitrary entries. Each row is
/// `name`, a unit-separator character, `value`, the separator again, then the observation
/// instant as a Unix timestamp; the separator cannot occur in any key or value this app
/// builds. Rows written by a build from before the timestamp existed still parse — they
/// simply carry no instant, which callers read as "age unknown".
///
/// The instant is refreshed on *every* observation, not only when the value changes: it
/// answers "how long ago did we last look at this key", so a value that has legitimately
/// held steady for days while the app polls must not read as ancient. That is also why
/// `record` no longer reports "nothing changed" — the instant always changes, so every
/// observation is worth persisting.
private struct BoundedRecencyStore {
    private static let separator: Character = "\u{1F}"

    struct Entry {
        var value: String
        /// `nil` for rows migrated from a build that stored no timestamp.
        var observedAt: Date?
    }

    private let capacity: Int
    /// Coldest first, hottest last.
    private var order: [String] = []
    private var entries: [String: Entry] = [:]

    init(encoded: [String], capacity: Int) {
        self.capacity = max(1, capacity)
        for row in encoded {
            let fields = row.split(separator: Self.separator, omittingEmptySubsequences: false)
            guard fields.count >= 2 else { continue }
            let name = String(fields[0])
            guard !name.isEmpty else { continue }
            let entry: Entry
            if fields.count == 2 {
                entry = Entry(value: String(fields[1]), observedAt: nil)
            } else {
                // Value keeps any interior separators it somehow acquired; the trailing
                // field is the instant.
                let value = fields[1..<(fields.count - 1)].joined(separator: String(Self.separator))
                let observedAt = Double(fields[fields.count - 1]).map(Date.init(timeIntervalSince1970:))
                entry = Entry(value: value, observedAt: observedAt)
            }
            if entries.updateValue(entry, forKey: name) != nil,
               let existing = order.firstIndex(of: name) {
                order.remove(at: existing)
            }
            order.append(name)
        }
        trim()
    }

    func entry(for name: String) -> Entry? { entries[name] }

    /// Stores `value` under `name`, stamps it as observed at `date`, and marks it the most
    /// recently touched entry.
    mutating func record(_ name: String, as value: String, at date: Date) {
        if entries.updateValue(Entry(value: value, observedAt: date), forKey: name) != nil,
           let existing = order.firstIndex(of: name) {
            order.remove(at: existing)
        }
        order.append(name)
        trim()
    }

    mutating func removeAll() {
        order.removeAll()
        entries.removeAll()
    }

    var encoded: [String] {
        order.compactMap { name in
            guard let entry = entries[name] else { return nil }
            let sep = Self.separator
            guard let observedAt = entry.observedAt else { return "\(name)\(sep)\(entry.value)" }
            return "\(name)\(sep)\(entry.value)\(sep)\(observedAt.timeIntervalSince1970)"
        }
    }

    private mutating func trim() {
        while order.count > capacity {
            let evicted = order.removeFirst()
            entries.removeValue(forKey: evicted)
        }
    }
}
