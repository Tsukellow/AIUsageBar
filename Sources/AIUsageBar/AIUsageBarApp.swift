import AppKit
import SwiftUI

@main
enum AIUsageBarEntry {
    @MainActor
    static func main() {
        switch Array(CommandLine.arguments.dropFirst()) {
        case [AntigravityStatusLine.captureArgument]:
            // The hook can still be referenced by an older live CLI session.
            // Check the current preference before even reading its stdin.
            try? AntigravityStatusLine().captureFromStdin {
                UserDefaults.standard.bool(forKey: AppSettings.antigravityEnabledKey)
            }
        case [AntigravityStatusLine.connectArgument]:
            do {
                try AntigravityStatusLine().connect()
                UserDefaults.standard.set(true, forKey: AppSettings.antigravityEnabledKey)
            } catch {
                FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
                exit(1)
            }
        default:
            AIUsageBarApp.main()
        }
    }
}

struct AIUsageBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
