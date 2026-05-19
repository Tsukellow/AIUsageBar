import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginManager: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published var errorMessage: String?

    init() {
        self.refreshStatus()
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }

            self.errorMessage = nil
        } catch {
            self.errorMessage = error.localizedDescription
        }

        self.refreshStatus()
    }

    func refreshStatus() {
        self.isEnabled = SMAppService.mainApp.status == .enabled
    }
}
