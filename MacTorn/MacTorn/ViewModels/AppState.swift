import Foundation
import Combine
import SwiftUI

@MainActor
class AppState: ObservableObject {
    // MARK: - Persisted
    @AppStorage("apiKey") var apiKey: String = ""
    @AppStorage("refreshInterval") var refreshInterval: Int = 30
    
    // MARK: - Published State
    @Published var data: TornResponse?
    @Published var lastUpdated: Date?
    @Published var errorMsg: String?
    @Published var isLoading: Bool = false
    @Published var notificationRules: [NotificationRule] = []
    
    // MARK: - Managers
    let launchAtLogin = LaunchAtLoginManager()
    let shortcutsManager = ShortcutsManager()
    
    // MARK: - State Comparison
    private var previousBars: Bars?
    private var previousCooldowns: Cooldowns?
    private var previousTravel: Travel?
    private var previousChain: Chain?
    private var previousStatus: Status?
    
    // MARK: - Timer
    private var timerCancellable: AnyCancellable?
    
    init() {
        loadNotificationRules()
        startPolling()
        Task {
            await NotificationManager.shared.requestPermission()
        }
    }
    
    func loadNotificationRules() {
        if let data = UserDefaults.standard.data(forKey: "notificationRules"),
           let rules = try? JSONDecoder().decode([NotificationRule].self, from: data) {
            notificationRules = rules
        } else {
            notificationRules = NotificationRule.defaults
            saveNotificationRules()
        }
    }
    
    func saveNotificationRules() {
        if let data = try? JSONEncoder().encode(notificationRules) {
            UserDefaults.standard.set(data, forKey: "notificationRules")
        }
    }
    
    func updateRule(_ rule: NotificationRule) {
        if let index = notificationRules.firstIndex(where: { $0.id == rule.id }) {
            notificationRules[index] = rule
            saveNotificationRules()
        }
    }
    
    func startPolling() {
        // Stop existing timer
        timerCancellable?.cancel()
        
        // Initial fetch
        fetchData()
        
        // Set up polling with configurable interval
        timerCancellable = Timer.publish(every: Double(refreshInterval), on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.fetchData()
            }
    }
    
    func stopPolling() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }
    
    func refreshNow() {
        fetchData()
    }
    
    func fetchData() {
        guard !apiKey.isEmpty else {
            errorMsg = "API Key required"
            return
        }
        
        guard let url = TornAPI.url(for: apiKey) else {
            errorMsg = "Invalid URL"
            return
        }
        
        isLoading = true
        errorMsg = nil
        
        Task {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw APIError.invalidResponse
                }
                
                switch httpResponse.statusCode {
                case 200:
                    let decoded = try JSONDecoder().decode(TornResponse.self, from: data)
                    
                    if let error = decoded.error {
                        self.errorMsg = "API Error: \(error.error)"
                        self.data = nil
                    } else {
                        // Check for notifications before updating
                        checkNotifications(newData: decoded)
                        
                        self.data = decoded
                        self.lastUpdated = Date()
                        self.errorMsg = nil
                        
                        // Store for comparison
                        self.previousBars = decoded.bars
                        self.previousCooldowns = decoded.cooldowns
                        self.previousTravel = decoded.travel
                        self.previousChain = decoded.chain
                        self.previousStatus = decoded.status
                    }
                case 403, 404:
                    self.errorMsg = "Invalid API Key"
                    self.data = nil
                default:
                    self.errorMsg = "HTTP Error: \(httpResponse.statusCode)"
                }
            } catch {
                self.errorMsg = error.localizedDescription
            }
            
            self.isLoading = false
        }
    }
    
    private func checkNotifications(newData: TornResponse) {
        // Bar notifications with custom rules
        if let prev = previousBars, let current = newData.bars {
            checkBarNotification(prevBar: prev.energy, currentBar: current.energy, barType: .energy)
            checkBarNotification(prevBar: prev.nerve, currentBar: current.nerve, barType: .nerve)
            checkBarNotification(prevBar: prev.happy, currentBar: current.happy, barType: .happy)
            checkBarNotification(prevBar: prev.life, currentBar: current.life, barType: .life)
        }
        
        // Cooldown notifications
        if let prevCD = previousCooldowns, let currentCD = newData.cooldowns {
            if prevCD.drug > 0 && currentCD.drug == 0 {
                NotificationManager.shared.send(title: "Drug Ready! 💊", body: "Drug cooldown has ended")
            }
            if prevCD.medical > 0 && currentCD.medical == 0 {
                NotificationManager.shared.send(title: "Medical Ready! 🏥", body: "Medical cooldown has ended")
            }
            if prevCD.booster > 0 && currentCD.booster == 0 {
                NotificationManager.shared.send(title: "Booster Ready! 🚀", body: "Booster cooldown has ended")
            }
        }
        
        // Travel notifications
        if let prevTravel = previousTravel, let currentTravel = newData.travel {
            if prevTravel.isTraveling && !currentTravel.isTraveling {
                NotificationManager.shared.send(title: "Landed! ✈️", body: "You have arrived in \(currentTravel.destination)")
            }
        }
        
        // Chain timeout warning
        if let chain = newData.chain, chain.isActive {
            if chain.timeoutRemaining < 60 && chain.timeoutRemaining > 0 {
                NotificationManager.shared.send(title: "Chain Expiring! ⚠️", body: "Chain timeout in \(chain.timeoutRemaining) seconds!")
            }
        }
        
        // Hospital/Jail release
        if let prevStatus = previousStatus, let currentStatus = newData.status {
            if !prevStatus.isOkay && currentStatus.isOkay {
                NotificationManager.shared.send(title: "Released! 🎉", body: "You are now free")
            }
        }
    }
    
    private func checkBarNotification(prevBar: Bar, currentBar: Bar, barType: NotificationRule.BarType) {
        let prevPct = prevBar.percentage
        let currentPct = currentBar.percentage
        
        for rule in notificationRules where rule.enabled && rule.barType == barType {
            let threshold = Double(rule.threshold)
            
            // Check if we crossed the threshold upwards
            if prevPct < threshold && currentPct >= threshold {
                let title: String
                switch barType {
                case .energy: title = "Energy \(rule.threshold)%! ⚡️"
                case .nerve: title = "Nerve \(rule.threshold)%! 💪"
                case .happy: title = "Happy \(rule.threshold)%! 😊"
                case .life: title = "Life \(rule.threshold)%! ❤️"
                }
                NotificationManager.shared.send(title: title, body: "\(barType.rawValue) is now at \(currentBar.current)/\(currentBar.maximum)")
                
                // Play sound
                if let sound = NotificationSound(rawValue: rule.soundName) {
                    SoundManager.shared.play(sound)
                }
            }
        }
    }
}

// MARK: - Errors
enum APIError: Error {
    case invalidResponse
    case invalidData
}
