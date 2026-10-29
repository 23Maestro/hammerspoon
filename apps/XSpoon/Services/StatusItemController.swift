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
    private var synchronizationTimer: Timer?
    private var commandMonitor: Any?

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
            observe(.xspoonBeginInspection) { [weak self] in
                self?.inspectorWindow?.orderOut(nil)
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(300))
                    self?.store.startInspecting()
                }
            },
            observeDistributed(.xspoonToggleMenu) { [weak self] in self?.togglePopover(nil) },
            observe(.xspoonOpenInspector) { [weak self] in self?.toggleInspector() },
            observeDistributed(.xspoonOpenInspector) { [weak self] in self?.toggleInspector() },
            observeDistributed(.xspoonInspectCurrentApp) { [weak self] in
                self?.handleHammerspoonInspectionToggle()
            },
            observeDistributed(.xspoonLiveElementUpdated) { [weak self] in self?.showLiveElement() },
            observeDistributed(.xspoonCaptureUpdated) { [weak self] in self?.handleCaptureUpdated() },
            observeDistributed(.xspoonMenuItemsRead) { [weak self] in self?.store.loadMenuItems() }
        ]
        commandMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 43 && event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command {
                self?.openInspector()
                return nil
            }
            return event
        }
        // Notifications are hints, not a reliable queue. Reconcile durable state without IPC.
        synchronizationTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.synchronizeRuntime() }
        }
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
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(
            x: visible.midX - (size.width / 2),
            y: visible.midY - (size.height / 2)
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
        if let pending = store.receiveCompletedCapture(source: .accessibility)
            ?? store.receiveCompletedCapture(source: .dom) {
            presentCapture(pending)
        }
    }

    private func toggleInspectionFromMenu() {
        popover.performClose(nil)
        store.toggleInspecting()
        handleHammerspoonInspectionToggle()
    }

    private func handleHammerspoonInspectionToggle() {
        store.synchronizeInspection()
        if store.isInspecting { showLiveElement() } else { overlay.hide() }
    }

    private func synchronizeRuntime() {
        let wasInspecting = store.isInspecting
        store.synchronizeInspection()
        store.refresh()
        if store.isInspecting { showLiveElement() }
        else if wasInspecting { overlay.hide() }
        handleCaptureUpdated()
    }

    private func stopInspecting() {
        overlay.hide()
        if hammerspoon.inspectionActive() { store.stopInspecting() }
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

    private func presentCapture(_ pending: PendingElementCapture) {
        stopInspecting()
        openInspector()
        overlay.show(snapshot: pending.snapshot, context: store.context, status: "Ready for shortcut")
        store.pendingCapture = pending
    }
}

extension StatusItemController: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
    }
}
