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

    private let defaults: UserDefaults
    private static let latchesStoreID = "notifications.latched.v2"
    private static let epochsStoreID = "notifications.epochs.v2"
    /// v1 held an uncapped string array / dictionary in a different encoding. Dropped on
    /// the first launch of this version; worst case is one alert suppressed or repeated
    /// on the upgrade poll.
    private static let retiredStoreIDs = ["notifications.latched.v1", "notifications.epochs.v1"]

    private static let latchedValue = "1"
    private static let clearedValue = "0"

    /// Last observed `active` state per edge key. Presence means "observed at least
    /// once" — that distinction is the whole point of `seedOnFirstSight`.
    private var latches: BoundedRecencyStore
    /// Last epoch value alerted for each key.
    private var epochs: BoundedRecencyStore

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
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
    ///   "active" condition can legitimately already hold at launch.
    @discardableResult
    func shouldFireOnEdge(_ key: String, active: Bool, seedOnFirstSight: Bool = false) -> Bool {
        let observed = latches.value(for: key)
        let wasActive = (observed == Self.latchedValue)
        let firstSight = (observed == nil)
        let fire = active && !wasActive && !(firstSight && seedOnFirstSight)
        if latches.record(key, as: active ? Self.latchedValue : Self.clearedValue) {
            persistLatches()
        }
        return fire
    }

    /// Fires (returns true) once per distinct `epoch` for `key`. A new epoch re-alerts;
    /// the same epoch is suppressed, even across app restarts. A suppressed call still
    /// refreshes the key's recency, so anything polled regularly is never evicted.
    @discardableResult
    func shouldFireOnce(_ key: String, epoch: String) -> Bool {
        let alreadyAlerted = (epochs.value(for: key) == epoch)
        if epochs.record(key, as: epoch) { persistEpochs() }
        return !alreadyAlerted
    }

    /// Whether `key` is currently latched — exposed for diagnostics/tests.
    func isLatched(_ key: String) -> Bool { latches.value(for: key) == Self.latchedValue }

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

/// A capped name→value map that evicts the least-recently-touched entry.
///
/// Persisted as a plain `[String]` in recency order (coldest first) so the *ordering* —
/// not just the contents — round-trips through `UserDefaults`. A dictionary would lose it
/// and a relaunch would then evict arbitrary entries. Each row is `name`, a unit-separator
/// character, then `value`; the separator cannot occur in either half of any key this app
/// builds.
private struct BoundedRecencyStore {
    private static let separator: Character = "\u{1F}"

    private let capacity: Int
    /// Coldest first, hottest last.
    private var order: [String] = []
    private var values: [String: String] = [:]

    init(encoded: [String], capacity: Int) {
        self.capacity = max(1, capacity)
        for row in encoded {
            guard let split = row.firstIndex(of: Self.separator) else { continue }
            let name = String(row[row.startIndex..<split])
            guard !name.isEmpty else { continue }
            let value = String(row[row.index(after: split)...])
            if values.updateValue(value, forKey: name) != nil,
               let existing = order.firstIndex(of: name) {
                order.remove(at: existing)
            }
            order.append(name)
        }
        trim()
    }

    func value(for name: String) -> String? { values[name] }

    /// Stores `value` under `name` and marks it the most recently touched entry.
    /// Returns whether anything actually changed — a re-observation of the already-hottest
    /// entry with an unchanged value need not hit the persistent store.
    @discardableResult
    mutating func record(_ name: String, as value: String) -> Bool {
        if values[name] == value && order.last == name { return false }
        if values.updateValue(value, forKey: name) != nil,
           let existing = order.firstIndex(of: name) {
            order.remove(at: existing)
        }
        order.append(name)
        trim()
        return true
    }

    mutating func removeAll() {
        order.removeAll()
        values.removeAll()
    }

    var encoded: [String] {
        order.map { "\($0)\(Self.separator)\(values[$0] ?? "")" }
    }

    private mutating func trim() {
        while order.count > capacity {
            let evicted = order.removeFirst()
            values.removeValue(forKey: evicted)
        }
    }
}
