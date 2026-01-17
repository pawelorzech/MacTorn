import Foundation
import Combine
import SwiftUI

@MainActor
class AppState: ObservableObject {
    // MARK: - Persisted
    @AppStorage("apiKey") var apiKey: String = ""
    
    // MARK: - Published State
    @Published var data: TornResponse?
    @Published var lastUpdated: Date?
    @Published var errorMsg: String?
    @Published var isLoading: Bool = false
    
    // MARK: - Managers
    let launchAtLogin = LaunchAtLoginManager()
    let shortcutsManager = ShortcutsManager()
    
    // MARK: - State Comparison
    private var previousBars: Bars?
    private var previousCooldowns: Cooldowns?
    private var previousTravel: Travel?
    
    // MARK: - Timer
    private var timerCancellable: AnyCancellable?
    
    init() {
        startPolling()
        Task {
            await NotificationManager.shared.requestPermission()
        }
    }
    
    func startPolling() {
        // Initial fetch
        fetchData()
        
        // Set up 30-second polling
        timerCancellable = Timer.publish(every: 30, on: .main, in: .common)
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
        // Bar notifications
        if let prev = previousBars, let current = newData.bars {
            // Energy full notification
            if prev.energy.current < prev.energy.maximum &&
               current.energy.current >= current.energy.maximum {
                NotificationManager.shared.send(
                    title: "Energy Full! ⚡️",
                    body: "Your energy bar is now full (\(current.energy.maximum)/\(current.energy.maximum))"
                )
            }
            
            // Nerve full notification
            if prev.nerve.current < prev.nerve.maximum &&
               current.nerve.current >= current.nerve.maximum {
                NotificationManager.shared.send(
                    title: "Nerve Full! 💪",
                    body: "Your nerve bar is now full (\(current.nerve.maximum)/\(current.nerve.maximum))"
                )
            }
        }
        
        // Cooldown notifications
        if let prevCD = previousCooldowns, let currentCD = newData.cooldowns {
            if prevCD.drug > 0 && currentCD.drug == 0 {
                NotificationManager.shared.send(
                    title: "Drug Ready! 💊",
                    body: "Drug cooldown has ended"
                )
            }
            if prevCD.medical > 0 && currentCD.medical == 0 {
                NotificationManager.shared.send(
                    title: "Medical Ready! 🏥",
                    body: "Medical cooldown has ended"
                )
            }
            if prevCD.booster > 0 && currentCD.booster == 0 {
                NotificationManager.shared.send(
                    title: "Booster Ready! 🚀",
                    body: "Booster cooldown has ended"
                )
            }
        }
        
        // Travel notifications
        if let prevTravel = previousTravel, let currentTravel = newData.travel {
            // Landed notification
            if prevTravel.isTraveling && !currentTravel.isTraveling {
                NotificationManager.shared.send(
                    title: "Landed! ✈️",
                    body: "You have arrived in \(currentTravel.destination)"
                )
            }
        }
    }
}

// MARK: - Errors
enum APIError: Error {
    case invalidResponse
    case invalidData
}
