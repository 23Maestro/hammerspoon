import AppKit

struct AccessibilityContextReader {
    func read() -> AppContext {
        let app = NSWorkspace.shared.frontmostApplication
        let bundleIdentifier = app?.bundleIdentifier ?? ""
        return AppContext(
            appName: app?.localizedName ?? "Unknown App",
            bundleIdentifier: bundleIdentifier,
            windowTitle: "",
            source: bundleIdentifier == "com.google.Chrome" ? .dom : .accessibility
        )
    }
}
