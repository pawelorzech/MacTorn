import Foundation
import SwiftUI

@MainActor
class ShortcutsManager: ObservableObject {
    @Published var shortcuts: [KeyboardShortcut] = []
    
    private let storageKey = "customShortcuts"
    
    init() {
        loadShortcuts()
    }
    
    func loadShortcuts() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([KeyboardShortcut].self, from: data) {
            shortcuts = saved
        } else {
            shortcuts = KeyboardShortcut.defaults
            saveShortcuts()
        }
    }
    
    func saveShortcuts() {
        if let data = try? JSONEncoder().encode(shortcuts) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
    
    func updateShortcut(_ shortcut: KeyboardShortcut) {
        if let index = shortcuts.firstIndex(where: { $0.id == shortcut.id }) {
            shortcuts[index] = shortcut
            saveShortcuts()
        }
    }
    
    func resetToDefaults() {
        shortcuts = KeyboardShortcut.defaults
        saveShortcuts()
    }
    
    func openURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
