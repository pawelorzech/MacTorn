import Foundation
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
}
