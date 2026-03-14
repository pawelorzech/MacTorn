import Foundation
import ServiceManagement
import os.log

private let logger = Logger(subsystem: TornConstants.logSubsystem, category: "LaunchAtLoginManager")

@MainActor
class LaunchAtLoginManager: ObservableObject {
    @Published var isEnabled: Bool = false
    @Published var errorMessage: String?

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
            errorMessage = nil
            updateStatus()
        } catch {
            logger.error("Launch at Login error: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }
}
