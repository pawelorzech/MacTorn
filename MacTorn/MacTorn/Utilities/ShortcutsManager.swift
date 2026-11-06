import Foundation
import Observation
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
    
    func openURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        BrowserManager.shared.open(url)
    }
}
