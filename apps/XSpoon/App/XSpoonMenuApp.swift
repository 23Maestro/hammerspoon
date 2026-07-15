import AppKit
import SwiftUI

@main
struct XSpoonMenuApp: App {
    @StateObject private var store = InspectorStore.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings") {
                    NotificationCenter.default.post(name: .xspoonOpenInspector, object: nil)
                }
                .keyboardShortcut("0", modifiers: [.control, .option])
            }
            CommandGroup(after: .sidebar) {
                Button("Toggle Sidebar") {
                    NotificationCenter.default.post(name: .xspoonToggleInspectorSidebar, object: nil)
                }
                .keyboardShortcut("b", modifiers: [.command])
            }
        }

    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.appearance = nil
        statusItemController = StatusItemController(store: InspectorStore.shared)
    }
}

extension Notification.Name {
    static let xspoonToggleMenu = Notification.Name("com.singleton23.XSpoon.toggleMenu")
    static let xspoonOpenInspector = Notification.Name("com.singleton23.XSpoon.openInspector")
    static let xspoonInspectCurrentApp = Notification.Name("com.singleton23.XSpoon.inspectCurrentApp")
    static let xspoonToggleInspectorSidebar = Notification.Name("com.singleton23.XSpoon.toggleInspectorSidebar")
    static let xspoonLiveElementUpdated = Notification.Name("com.singleton23.XSpoon.liveElementUpdated")
    static let xspoonCaptureCurrentElement = Notification.Name("com.singleton23.XSpoon.captureCurrentElement")
    static let xspoonCaptureUpdated = Notification.Name("com.singleton23.XSpoon.captureUpdated")
}
