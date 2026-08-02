import XCTest
@testable import MacTorn

@MainActor
final class AccountSessionStoreTests: XCTestCase {
    func testMigratesLegacyKeyAndRemovesUserDefaultsCopy() {
        let defaults = makeDefaults()
        defaults.set("legacy-key", forKey: "apiKey")
        let credentials = MemoryAPIKeyStore()

        let store = AccountSessionStore(
            defaults: defaults,
            credentialStore: credentials
        )

        XCTAssertEqual(store.apiKey, "legacy-key")
        XCTAssertEqual(credentials.get(), "legacy-key")
        XCTAssertNil(defaults.string(forKey: "apiKey"))
    }

    func testChangingKeyAdvancesGenerationAndRejectsOldIdentity() {
        let credentials = MemoryAPIKeyStore("old-key")
        let store = AccountSessionStore(
            defaults: makeDefaults(),
            credentialStore: credentials
        )
        let oldIdentity = store.identity
        store.isHalted = true

        XCTAssertTrue(store.updateAPIKey("new-key"))
        XCTAssertEqual(store.apiKey, "new-key")
        XCTAssertEqual(store.identity.generation, oldIdentity.generation + 1)
        XCTAssertFalse(store.isCurrent(oldIdentity))
        XCTAssertFalse(store.isHalted)
        XCTAssertEqual(credentials.get(), "new-key")
        XCTAssertFalse(store.updateAPIKey("new-key"))
        XCTAssertEqual(store.identity.generation, oldIdentity.generation + 1)
    }

    func testChangingKeyCancelsRegisteredAccountTask() async {
        let store = AccountSessionStore(
            defaults: makeDefaults(),
            credentialStore: MemoryAPIKeyStore("old-key")
        )
        let cancelled = expectation(description: "account task cancelled")

        store.startTask(.userSnapshot) {
            do {
                try await Task.sleep(nanoseconds: 10_000_000_000)
            } catch {
                cancelled.fulfill()
            }
        }

        store.updateAPIKey("new-key")
        await fulfillment(of: [cancelled], timeout: 1)
    }

    /// Regression pin for GitHub issue #62.
    ///
    /// `KeychainStore.set` deliberately writes the API key with
    /// `kSecAttrAccessibleAfterFirstUnlock` so background polling, countdown timers and
    /// notifications keep working while the Mac is locked, and deliberately never sets
    /// `kSecAttrSynchronizable`, so the key never reaches iCloud Keychain.
    ///
    /// This is a source-literal check, not a live Keychain round-trip: a standalone probe
    /// (`SecItemAdd` + `SecItemCopyMatching` with `kSecReturnAttributes`) confirmed that on
    /// this machine's default (non-data-protection) Keychain, `kSecAttrAccessible` is never
    /// echoed back on read — `AfterFirstUnlock` and `WhenUnlocked` are indistinguishable via
    /// `SecItemCopyMatching`, with or without app sandboxing, so a live assertion would fail
    /// unconditionally and prove nothing about which constant is actually in effect. Scanning
    /// the source is therefore the only reliable way to pin the choice: if a future edit
    /// "fixes" this to `kSecAttrAccessibleWhenUnlocked` (the more common default), or adds
    /// `kSecAttrSynchronizable`, this test fails loudly instead of background polling (or key
    /// sync) silently breaking.
    func testKeychainStoreSourceKeepsAfterFirstUnlockAndNonSynchronizableAccessibility() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let sourceFileURL = testFileURL
            .deletingLastPathComponent() // ViewModels
            .deletingLastPathComponent() // MacTornTests
            .deletingLastPathComponent() // MacTorn/ (Xcode project root, sibling of MacTorn/ and MacTornTests/)
            .appendingPathComponent("MacTorn")
            .appendingPathComponent("ViewModels")
            .appendingPathComponent("AccountSessionStore.swift")

        let source = try String(contentsOf: sourceFileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock"),
            "KeychainStore must keep writing kSecAttrAccessibleAfterFirstUnlock so polling/notifications survive a locked Mac"
        )
        XCTAssertFalse(
            source.contains("kSecAttrAccessibleWhenUnlocked"),
            "KeychainStore must not switch to kSecAttrAccessibleWhenUnlocked — that breaks background polling while locked"
        )
        XCTAssertFalse(
            source.contains("kSecAttrSynchronizable"),
            "KeychainStore must not set kSecAttrSynchronizable — the API key must never sync to iCloud Keychain"
        )
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "AccountSessionStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

private final class MemoryAPIKeyStore: APIKeyStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?

    init(_ value: String? = nil) {
        self.value = value
    }

    func get() -> String? {
        lock.withLock { value }
    }

    func set(_ value: String) {
        lock.withLock {
            self.value = value.isEmpty ? nil : value
        }
    }
}
