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
//  • `shouldFireOnEdge(_:active:)` — a rising-edge latch. Returns true the first time
//    `active` becomes true, then false until `active` returns to false (re-arm).
//    Used for the chain danger window (active = 0 < timeout < 60s). Also fits any
//    threshold-style alert (bar threshold, hospital/jail released).
//
//  • `shouldFireOnce(_:epoch:)` — fires once per distinct `epoch` value for a key.
//    Used for per-instance events keyed by a stable identity: OC ready (OC id),
//    landing (destination + arrival time), forum new posts (last post id),
//    price alert (item id + crossed threshold), bounty (bounty id).
//
// A later stage routes the remaining notification categories through this coordinator
// (see ISA backlog E-02); this stage wires the chain alert — the actual reported bug.
@MainActor
final class NotificationCoordinator {
    private let defaults: UserDefaults
    private static let latchesStoreID = "notifications.latched.v1"
    private static let epochsStoreID = "notifications.epochs.v1"

    /// Keys currently latched (fired, awaiting re-arm). Stored as a string array so it
    /// round-trips through UserDefaults without NSNumber/Bool bridging ambiguity.
    private var latchedKeys: Set<String>
    /// Last epoch value alerted for each key.
    private var epochs: [String: String]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.latchedKeys = Set(defaults.stringArray(forKey: Self.latchesStoreID) ?? [])
        self.epochs = (defaults.dictionary(forKey: Self.epochsStoreID) as? [String: String]) ?? [:]
    }

    /// Rising-edge latch. Fires (returns true) exactly once when `active` transitions
    /// from false to true, then stays silent until `active` returns to false.
    @discardableResult
    func shouldFireOnEdge(_ key: String, active: Bool) -> Bool {
        let latched = latchedKeys.contains(key)
        if active && !latched {
            latchedKeys.insert(key)
            persistLatches()
            return true
        }
        if !active && latched {
            latchedKeys.remove(key)
            persistLatches()
        }
        return false
    }

    /// Fires (returns true) once per distinct `epoch` for `key`. A new epoch re-alerts;
    /// the same epoch is suppressed, even across app restarts.
    @discardableResult
    func shouldFireOnce(_ key: String, epoch: String) -> Bool {
        if epochs[key] == epoch { return false }
        epochs[key] = epoch
        persistEpochs()
        return true
    }

    /// Whether `key` is currently latched — exposed for diagnostics/tests.
    func isLatched(_ key: String) -> Bool { latchedKeys.contains(key) }

    /// Forget all dedup state (used when the key changes, or in tests).
    func reset() {
        latchedKeys.removeAll()
        epochs.removeAll()
        defaults.removeObject(forKey: Self.latchesStoreID)
        defaults.removeObject(forKey: Self.epochsStoreID)
    }

    private func persistLatches() {
        defaults.set(Array(latchedKeys), forKey: Self.latchesStoreID)
    }

    private func persistEpochs() {
        defaults.set(epochs, forKey: Self.epochsStoreID)
    }
}
