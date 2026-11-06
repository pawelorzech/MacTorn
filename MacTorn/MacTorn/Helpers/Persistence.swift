import Foundation

/// A user-curated list stored as JSON in UserDefaults. A stored blob that no longer
/// decodes (corruption, or a newer build's format) is copied to `<key>.unreadable` and
/// background saves leave it alone, so a poll can never replace the user's list with an
/// empty one. The first deliberate edit takes the list over again.
struct PersistedList<Element: Codable> {
    let key: String
    private var isLocked = false

    init(key: String) { self.key = key }

    /// The stored list, or nil when there is none or it cannot be read.
    mutating func load(from defaults: UserDefaults) -> [Element]? {
        guard let data = defaults.data(forKey: key) else {
            isLocked = false
            return nil
        }
        guard let decoded = try? JSONDecoder().decode([Element].self, from: data) else {
            isLocked = true
            defaults.set(data, forKey: "\(key).unreadable")
            return nil
        }
        isLocked = false
        return decoded
    }

    func save(_ elements: [Element], to defaults: UserDefaults) {
        guard !isLocked else { return }
        defaults.setEncoded(elements, forKey: key)
    }

    mutating func userEdited() { isLocked = false }
}

extension UserDefaults {
    func decoded<Value: Decodable>(_ type: Value.Type, forKey key: String) -> Value? {
        data(forKey: key).flatMap { try? JSONDecoder().decode(Value.self, from: $0) }
    }

    func setEncoded<Value: Encodable>(_ value: Value, forKey key: String) {
        if let data = try? JSONEncoder().encode(value) { set(data, forKey: key) }
    }
}

extension Array where Element: Identifiable {
    /// Puts back an element that was removed from `index`, unless it is already present.
    mutating func reinsert(_ element: Element, at index: Int) -> Bool {
        guard !contains(where: { $0.id == element.id }) else { return false }
        insert(element, at: Swift.min(Swift.max(index, 0), count))
        return true
    }
}
