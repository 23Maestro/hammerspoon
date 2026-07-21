import AppKit
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let store: InspectorStore
    private let overlay = CaptureOverlayController()
    private let hammerspoon = HammerspoonClient()
    private var inspectorWindow: NSWindow?
    private var appearanceObserver: NSKeyValueObservation?
    private var notificationObservers: [NSObjectProtocol] = []

    init(store: InspectorStore) {
        self.store = store
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.popover = NSPopover()
        super.init()

        configureStatusItem()
        configurePopover()
        configureInspectorWindow()
        appearanceObserver = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                self?.updateIcon()
            }
        }
        notificationObservers = [
            observeDistributed(.xspoonToggleMenu) { [weak self] in self?.togglePopover(nil) },
            observe(.xspoonOpenInspector) { [weak self] in self?.toggleInspector() },
            observeDistributed(.xspoonOpenInspector) { [weak self] in self?.toggleInspector() },
            observeDistributed(.xspoonInspectCurrentApp) { [weak self] in
                self?.handleHammerspoonInspectionToggle()
            },
            observeDistributed(.xspoonLiveElementUpdated) { [weak self] in self?.showLiveElement() },
            observeDistributed(.xspoonCaptureCurrentElement) { [weak self] in self?.captureCurrentElement() },
            observeDistributed(.xspoonCaptureUpdated) { [weak self] in self?.handleCaptureUpdated() }
        ]
    }

    private func observe(_ name: Notification.Name, action: @escaping @MainActor () -> Void) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
            Task { @MainActor in action() }
        }
    }

    private func observeDistributed(_ name: Notification.Name, action: @escaping @MainActor () -> Void) -> NSObjectProtocol {
        DistributedNotificationCenter.default().addObserver(forName: name, object: nil, queue: .main) { _ in
            Task { @MainActor in action() }
        }
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = iconForCurrentAppearance()
        button.imageScaling = .scaleProportionallyDown
        button.imagePosition = .imageOnly
        button.toolTip = "XSpoon"
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp])
    }

    private func configurePopover() {
        popover.delegate = self
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 270, height: 340)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView(
                store: store,
                onInspect: { [weak self] in self?.toggleInspectionFromMenu() },
                onOpenInspector: { [weak self] in self?.openInspector() }
            )
        )
    }

    private func configureInspectorWindow() {
        let size = NSSize(width: 790, height: 830)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "XSpoon"
        window.isReleasedWhenClosed = false
        window.minSize = size
        window.maxSize = size
        window.contentViewController = NSHostingController(rootView: ContentView(store: store))
        positionInspectorWindow(window, size: size)
        window.orderOut(nil)
        inspectorWindow = window
    }

    private func positionInspectorWindow(_ window: NSWindow, size: NSSize) {
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(
            x: visible.maxX - size.width - 24,
            y: visible.maxY - size.height - 24
        )
        window.setFrame(NSRect(origin: origin, size: size), display: false)
    }

    private func updateIcon() {
        statusItem.button?.image = iconForCurrentAppearance()
    }

    private func iconForCurrentAppearance() -> NSImage? {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let name = isDark ? "InspectorIconDark" : "InspectorIconLight"
        guard let url = Bundle.module.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            return NSImage(systemSymbolName: "scope", accessibilityDescription: "XSpoon")
        }

        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = false
        return image
    }

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func openInspector() {
        popover.performClose(nil)
        stopInspecting()
        NSApp.activate(ignoringOtherApps: true)
        if let inspectorWindow {
            positionInspectorWindow(inspectorWindow, size: inspectorWindow.frame.size)
        }
        inspectorWindow?.makeKeyAndOrderFront(nil)
    }

    private func toggleInspector() {
        if inspectorWindow?.isVisible == true {
            stopInspecting()
            inspectorWindow?.orderOut(nil)
        } else {
            openInspector()
        }
    }

    private func handleCaptureUpdated() {
        store.refresh()
        stopInspecting()
        overlay.show(snapshot: store.snapshot, context: store.context, status: store.status)
    }

    private func toggleInspectionFromMenu() {
        guard case .success = hammerspoon.toggleLiveInspector() else {
            store.status = "Hammerspoon live inspector unavailable"
            return
        }
        handleHammerspoonInspectionToggle()
    }

    private func handleHammerspoonInspectionToggle() {
        if store.isInspecting {
            stopInspecting()
            return
        }

        store.startInspecting()
        showLiveElement()
        showPopover()
    }

    private func stopInspecting() {
        overlay.hide()
        if store.isInspecting {
            store.stopInspecting()
        }
    }

    private func showLiveElement() {
        guard store.isInspecting, let snapshot = hammerspoon.liveSnapshot() else { return }
        let context = AppContext(
            appName: snapshot.appDisplayName,
            bundleIdentifier: snapshot.appBundleIdentifier,
            windowTitle: snapshot.windowTitle ?? "",
            source: snapshot.captureSource
        )
        store.updateLiveSnapshot(snapshot, context: context)
        overlay.show(snapshot: snapshot, context: context, status: "Inspecting", autoDismiss: false, anchorAtMouse: true)
    }

    private func captureCurrentElement() {
        let pending = store.createElementFromCurrentTarget()
        stopInspecting()

        if let pending {
            overlay.show(snapshot: pending.snapshot, context: store.context, status: "Ready for shortcut")
            openInspector()
            Task { @MainActor in
                store.pendingCapture = nil
                await Task.yield()
                store.pendingCapture = pending
            }
        }
    }
}

extension StatusItemController: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
    }
}
