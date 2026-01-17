import SwiftUI
import AppKit

class SoundManager {
    static let shared = SoundManager()
    
    private init() {}
    
    func play(_ sound: NotificationSound) {
        guard sound != .none else { return }
        
        if sound == .default {
            NSSound.beep()
            return
        }
        
        // Try system sounds
        if let systemSound = NSSound(named: sound.rawValue) {
            systemSound.play()
        } else {
            // Fallback to beep
            NSSound.beep()
        }
    }
    
    func playForEvent(_ eventType: String, rules: [NotificationRule]) {
        // Find matching rule and play its sound
        if let rule = rules.first(where: { $0.enabled && $0.barType.rawValue.lowercased() == eventType.lowercased() }) {
            if let sound = NotificationSound(rawValue: rule.soundName) {
                play(sound)
            }
        }
    }
}
