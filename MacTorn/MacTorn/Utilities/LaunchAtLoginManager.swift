import Foundation
import ServiceManagement

@MainActor
class LaunchAtLoginManager: ObservableObject {
    @Published var isEnabled: Bool = false
    
    private let service = SMAppService.mainApp
    
    init() {
        updateStatus()
    }
    
    func updateStatus() {
        isEnabled = service.status == .enabled
    }
    
    func toggle() {
        do {
            if isEnabled {
                try service.unregister()
            } else {
                try service.register()
            }
            updateStatus()
        } catch {
            print("Launch at Login error: \(error)")
        }
    }
}
