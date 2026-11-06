import XCTest
@testable import MacTorn

final class WatchedThreadTests: XCTestCase {

    // MARK: - Encoding/Decoding Tests

    func testEncoding_roundTrip() throws {
        let original = WatchedThread(
            id: 12345,
            title: "Test Thread",
            notificationsEnabled: false,
            lastKnownPostCount: 42,
            lastChecked: Date(),
            error: nil,
            isFactionThread: true
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WatchedThread.self, from: data)

        XCTAssertEqual(original.id, decoded.id)
        XCTAssertEqual(original.title, decoded.title)
        XCTAssertEqual(original.notificationsEnabled, decoded.notificationsEnabled)
        XCTAssertEqual(original.lastKnownPostCount, decoded.lastKnownPostCount)
        XCTAssertEqual(original.isFactionThread, decoded.isFactionThread)
    }

    func testDecoding_withError() throws {
        let json: [String: Any] = [
            "id": 12345,
            "title": "Error Thread",
            "notificationsEnabled": true,
            "lastKnownPostCount": 0,
            "isFactionThread": false,
            "error": "API Error"
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let thread = try JSONDecoder().decode(WatchedThread.self, from: data)

        XCTAssertEqual(thread.error, "API Error")
    }
}

/// Tolerant decoding for the four persisted preference types.
///
/// Swift's synthesized `init(from:)` throws on a missing key even where the memberwise
/// initialiser supplies a default, and all four load paths answer a decode failure by
/// installing the shipped defaults — three of them saving those defaults over the user's
/// blob in the same statement. So "a new field was added" and "the user's settings were
/// destroyed" used to be the same event. These tests pin that shut.
///
/// Housed in this file because a new test file needs an Xcode project entry; they are
/// self-contained if you would rather move them to `CodableMigrationTests.swift`.
final class PersistedPreferenceDecodingTests: XCTestCase {

    private func blob(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }

    // MARK: - A blob from an older build still loads

    func testWatchedThreadWithoutIsFactionThreadStillLoads() throws {
        // Exactly what a build before 1.8.0 wrote.
        let legacy = try blob([[
            "id": 42, "title": "Raid tonight",
            "notificationsEnabled": true, "lastKnownPostCount": 12,
        ]])
        let decoded = try JSONDecoder().decode([WatchedThread].self, from: legacy)

        XCTAssertEqual(decoded.count, 1, "one unknown field must not cost the whole list")
        XCTAssertEqual(decoded[0].id, 42)
        XCTAssertEqual(decoded[0].title, "Raid tonight")
        XCTAssertEqual(decoded[0].lastKnownPostCount, 12)
        XCTAssertFalse(decoded[0].isFactionThread)
    }

    func testNotificationRuleWithoutSoundNameStillLoads() throws {
        let legacy = try blob([[
            "id": "energy_full", "barType": "Energy", "threshold": 90, "enabled": false,
        ]])
        let decoded = try JSONDecoder().decode([NotificationRule].self, from: legacy)

        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].threshold, 90, "the user's threshold must survive")
        XCTAssertFalse(decoded[0].enabled)
        XCTAssertEqual(decoded[0].soundName, "default",
                       "a missing field falls back to the shipped rule for this id")
    }

    func testTravelNotificationSettingWithoutEnabledStillLoads() throws {
        let legacy = try blob([["id": "travel_1min", "secondsBefore": 60]])
        let decoded = try JSONDecoder().decode([TravelNotificationSetting].self, from: legacy)

        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].secondsBefore, 60)
    }

    func testKeyboardShortcutWithoutModifiersStillLoads() throws {
        let legacy = try blob([[
            "id": "home", "name": "Home",
            "url": "https://www.torn.com/", "keyEquivalent": "h",
        ]])
        let decoded = try JSONDecoder().decode([KeyboardShortcut].self, from: legacy)

        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].modifiers, ["command", "shift"],
                       "a partial row rebuilds from the shipped shortcut with the same id")
    }

    // MARK: - The fallback never overwrites something the user actually chose

    func testStoredValuesWinOverTheShippedDefault() throws {
        // `energy_full` ships as threshold 100 / enabled true / Energy / "default".
        let stored = try blob([[
            "id": "energy_full", "barType": "Nerve", "threshold": 55,
            "enabled": false, "soundName": "Glass",
        ]])
        let decoded = try JSONDecoder().decode([NotificationRule].self, from: stored)[0]

        XCTAssertEqual(decoded.threshold, 55)
        XCTAssertFalse(decoded.enabled)
        XCTAssertEqual(decoded.soundName, "Glass")
        XCTAssertEqual(decoded.barType, .nerve)
    }

    // MARK: - An unknown enum case is survivable

    func testAnUnknownBarTypeDoesNotTakeTheOtherRulesDown() throws {
        // `decodeIfPresent` still throws on a raw value this build does not know, so
        // retiring or renaming a bar in a later release used to destroy every rule.
        let stored = try blob([
            ["id": "energy_full", "barType": "Energy", "threshold": 100,
             "enabled": true, "soundName": "default"],
            ["id": "life_low", "barType": "Stamina", "threshold": 20,
             "enabled": true, "soundName": "Ping"],
        ])
        let decoded = try JSONDecoder().decode([NotificationRule].self, from: stored)

        XCTAssertEqual(decoded.count, 2, "one unrecognised bar must not cost the other rule")
        XCTAssertEqual(decoded[0].threshold, 100)
        XCTAssertEqual(decoded[1].barType, .life, "falls back to the shipped bar for this id")
        XCTAssertEqual(decoded[1].soundName, "Ping", "the rest of the row is untouched")
    }

    // MARK: - Identity is still required

    func testARowWithoutAnIdIsStillRejected() {
        // Tolerance is for fields with a sane default, not for identity: a rule with no
        // id cannot be matched to anything and must not be silently invented.
        let headless = try? blob([["threshold": 50]])
        XCTAssertNotNil(headless)
        XCTAssertThrowsError(
            try JSONDecoder().decode([NotificationRule].self, from: headless!)
        )
    }

    // MARK: - Round trips

    func testTheShippedDefaultsRoundTripUnchanged() throws {
        let rules = NotificationRule.defaults
        XCTAssertEqual(
            try JSONDecoder().decode([NotificationRule].self,
                                     from: JSONEncoder().encode(rules)),
            rules
        )

        let travel = TravelNotificationSetting.defaults
        XCTAssertEqual(
            try JSONDecoder().decode([TravelNotificationSetting].self,
                                     from: JSONEncoder().encode(travel)),
            travel
        )

        let shortcuts = KeyboardShortcut.defaults
        XCTAssertEqual(
            try JSONDecoder().decode([KeyboardShortcut].self,
                                     from: JSONEncoder().encode(shortcuts)),
            shortcuts
        )
    }
}
