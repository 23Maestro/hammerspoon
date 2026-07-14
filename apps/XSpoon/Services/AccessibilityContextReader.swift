import AppKit

struct AccessibilityContextReader {
    func read() -> AppContext {
        let app = NSWorkspace.shared.frontmostApplication
        return AppContext(
            appName: app?.localizedName ?? "Unknown App",
            bundleIdentifier: app?.bundleIdentifier ?? "",
            windowTitle: "",
            source: .accessibility
        )
    }
}
