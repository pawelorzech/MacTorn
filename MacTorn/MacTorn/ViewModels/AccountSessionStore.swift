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
}

protocol APIKeyStoring: Sendable {
    func get() -> String?
    func set(_ value: String)
}

struct KeychainAPIKeyStore: APIKeyStoring {
    func get() -> String? { KeychainStore.get() }
    func set(_ value: String) { KeychainStore.set(value) }
}

/// Owns authenticated-account identity and task invalidation. Feature state still lives
/// behind `AppState`, but every account-scoped service shares this generation contract.
@MainActor
@Observable
final class AccountSessionStore {
    private(set) var apiKey: String
    private(set) var generation: UInt = 0
    var isHalted = false

    @ObservationIgnored private let credentialStore: APIKeyStoring
    @ObservationIgnored private var tasks: [AccountTaskKind: Task<Void, Never>] = [:]

    init(defaults: UserDefaults,
         credentialStore: APIKeyStoring = KeychainAPIKeyStore()) {
        self.credentialStore = credentialStore

        if let legacy = defaults.string(forKey: "apiKey"), !legacy.isEmpty {
            credentialStore.set(legacy)
            defaults.removeObject(forKey: "apiKey")
            accountLogger.info("Migrated API key from UserDefaults to Keychain")
        }
        self.apiKey = credentialStore.get() ?? ""
    }

    var identity: AccountIdentity {
        AccountIdentity(apiKey: apiKey, generation: generation)
    }

    @discardableResult
    func updateAPIKey(_ newValue: String) -> Bool {
        guard newValue != apiKey else { return false }
        credentialStore.set(newValue)
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

    static func set(_ value: String) {
        guard !value.isEmpty else {
            delete()
            return
        }
        #if DEBUG
        if UITestConfiguration.isActive {
            UITestConfiguration.keychainOverride[account] = value
            return
        }
        #endif
        guard let data = value.data(using: .utf8) else { return }
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
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
        } else if updateStatus != errSecSuccess {
            accountLogger.error("Keychain update failed: OSStatus \(updateStatus)")
        }
    }

    static func delete() {
        #if DEBUG
        if UITestConfiguration.isActive {
            UITestConfiguration.keychainOverride[account] = nil
            return
        }
        #endif
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
