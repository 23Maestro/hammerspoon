import AppKit
import SwiftUI

@main
enum XSpoonMenuApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.appearance = nil
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "XSpoon")
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(settings)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit XSpoon", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)
        NSApp.mainMenu = menu
        statusItemController = StatusItemController(store: InspectorStore.shared)
    }

    @objc private func openSettings() {
        NotificationCenter.default.post(name: .xspoonOpenInspector, object: nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        false
    }
}

extension Notification.Name {
    static let xspoonBeginInspection = Notification.Name("com.singleton23.XSpoon.beginInspection")
    static let xspoonToggleMenu = Notification.Name("com.singleton23.XSpoon.toggleMenu")
    static let xspoonOpenInspector = Notification.Name("com.singleton23.XSpoon.openInspector")
    static let xspoonInspectCurrentApp = Notification.Name("com.singleton23.XSpoon.inspectCurrentApp")
    static let xspoonToggleInspectorSidebar = Notification.Name("com.singleton23.XSpoon.toggleInspectorSidebar")
    static let xspoonLiveElementUpdated = Notification.Name("com.singleton23.XSpoon.liveElementUpdated")
    static let xspoonCaptureUpdated = Notification.Name("com.singleton23.XSpoon.captureUpdated")
    static let xspoonMenuItemsRead = Notification.Name("com.singleton23.XSpoon.menuItemsRead")
}
