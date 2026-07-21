import AppKit

struct AppLauncher {
    func focus(_ app: MyAppDefinition) -> Bool {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleIdentifier).first {
            return running.activate(options: [.activateAllWindows])
        }

        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleIdentifier) else {
            return false
        }

        return NSWorkspace.shared.open(url)
    }
}
