import Foundation

enum PositiveIntegerInput {
    static func value(from input: String) -> Int? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(trimmed), value > 0 else { return nil }
        return value
    }

    static func errorMessage(for input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value(from: input) == nil else { return nil }
        if trimmed.isEmpty {
            return "Enter a price."
        }
        if let value = Int(trimmed), value <= 0 {
            return "Price must be greater than zero."
        }
        return "Enter a whole number."
    }
}
