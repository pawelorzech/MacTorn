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
