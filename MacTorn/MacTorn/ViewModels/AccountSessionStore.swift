import Foundation
import Observation
import Security
import os.log

private let accountLogger = Logger(
    subsystem: TornConstants.logSubsystem,
    category: "AccountSessionStore"
)

struct AccountIdentity: Equatable, Sendable {
    let apiKey: String
    let generation: UInt
}

enum AccountTaskKind: Hashable, Sendable {
    case userSnapshot
    case watchlist
    case forum
    case stockMetadata
    case itemCatalog
    /// The background price-alert refresh. Separate from `.watchlist` so a timer tick
    /// never cancels a refresh the user started from the Watchlist tab, or vice versa.
    case priceAlerts
}

protocol APIKeyStoring: Sendable {
    func get() -> String?
    @discardableResult func set(_ value: String) -> Bool
}

struct KeychainAPIKeyStore: APIKeyStoring {
    func get() -> String? { KeychainStore.get() }
    @discardableResult func set(_ value: String) -> Bool { KeychainStore.set(value) }
}

/// Owns authenticated-account identity and task invalidation. Feature state still lives
/// behind `AppState`, but every account-scoped service shares this generation contract.
@MainActor
@Observable
final class AccountSessionStore {
    private(set) var apiKey: String
    private(set) var generation: UInt = 0
    var isHalted = false
    private(set) var persistenceError: String?

    @ObservationIgnored private let credentialStore: APIKeyStoring
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var tasks: [AccountTaskKind: Task<Void, Never>] = [:]

    init(defaults: UserDefaults,
         credentialStore: APIKeyStoring = KeychainAPIKeyStore()) {
        self.credentialStore = credentialStore
        self.defaults = defaults

        if let legacy = defaults.string(forKey: "apiKey"), !legacy.isEmpty {
            if credentialStore.set(legacy) {
                defaults.removeObject(forKey: "apiKey")
                accountLogger.info("Migrated API key from UserDefaults to Keychain")
            } else {
                persistenceError = "Could not move your saved key to Keychain. Unlock Keychain and save the key again."
            }
        }
        self.apiKey = credentialStore.get() ?? ""
    }

    var identity: AccountIdentity {
        AccountIdentity(apiKey: apiKey, generation: generation)
    }

    @discardableResult
    func updateAPIKey(_ newValue: String) -> Bool {
        persistenceError = nil
        guard newValue != apiKey || isHalted || defaults.string(forKey: "apiKey") != nil else { return false }
        guard credentialStore.set(newValue) else {
            persistenceError = "Could not save your API key in Keychain. Your previous account is unchanged. Unlock Keychain and try again."
            return false
        }
        defaults.removeObject(forKey: "apiKey")
        generation &+= 1
        cancelAllTasks()
        apiKey = newValue
        isHalted = false
        return true
    }

    func isCurrent(_ identity: AccountIdentity) -> Bool {
        self.identity == identity
    }

    func startTask(
        _ kind: AccountTaskKind,
        operation: @escaping @MainActor () async -> Void
    ) {
        tasks[kind]?.cancel()
        tasks[kind] = Task { await operation() }
    }

    func cancelTask(_ kind: AccountTaskKind) {
        tasks[kind]?.cancel()
        tasks[kind] = nil
    }

    func cancelAllTasks() {
        for task in tasks.values {
            task.cancel()
        }
        tasks.removeAll(keepingCapacity: true)
    }
}

// MARK: - Keychain

/// Minimal generic-password Keychain wrapper for the single Torn API key.
///
/// Test isolation: XCTest workers use a PID-suffixed service, while the UI-test harness
/// routes through an in-memory override and never reads a developer's real key.
enum KeychainStore {
    static let account = "apiKey"

    static var service: String {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return "com.mactorn.app.tests.\(ProcessInfo.processInfo.processIdentifier)"
        }
        return "com.mactorn.app"
    }

    static func get() -> String? {
        #if DEBUG
        if UITestConfiguration.isActive {
            return UITestConfiguration.keychainOverride[account]
        }
        #endif
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }

    @discardableResult
    static func set(_ value: String) -> Bool {
        guard !value.isEmpty else {
            return delete()
        }
        #if DEBUG
        if UITestConfiguration.isActive {
            UITestConfiguration.keychainOverride[account] = value
            return true
        }
        #endif
        guard let data = value.data(using: .utf8) else { return false }
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        // `kSecAttrAccessibleAfterFirstUnlock` is DELIBERATE, not an oversight.
        // MacTorn must keep polling the Torn API, running countdown timers and posting
        // notifications while the Mac is locked (menu bar apps run headless in that state).
        // `kSecAttrAccessibleWhenUnlocked` would make the Keychain item unreadable while
        // locked and silently break all of that background work — do not "fix" this to
        // `WhenUnlocked`, even though it looks like the more conservative default.
        //
        // We also deliberately do NOT set `kSecAttrSynchronizable` here: the API key must
        // stay device-local and never sync to iCloud Keychain.
        let updateAttributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            updateAttributes as CFDictionary
        )
        if updateStatus == errSecItemNotFound {
            var addQuery = baseQuery
            addQuery.merge(updateAttributes) { _, new in new }
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            if addStatus != errSecSuccess {
                accountLogger.error("Keychain add failed: OSStatus \(addStatus)")
            }
            return addStatus == errSecSuccess
        } else if updateStatus != errSecSuccess {
            accountLogger.error("Keychain update failed: OSStatus \(updateStatus)")
        }
        return updateStatus == errSecSuccess
    }

    @discardableResult
    static func delete() -> Bool {
        #if DEBUG
        if UITestConfiguration.isActive {
            UITestConfiguration.keychainOverride[account] = nil
            return true
        }
        #endif
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            accountLogger.error("Keychain delete failed: OSStatus \(status)")
        }
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
