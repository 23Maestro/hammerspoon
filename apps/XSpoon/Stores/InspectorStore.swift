import AppKit
import Foundation

@MainActor
final class InspectorStore: ObservableObject {
    static let shared = InspectorStore()

    @Published var context = AppContext()
    @Published var snapshot: ElementSnapshot?
    @Published var isInspecting = false
    @Published var selectedAdapter: AdapterKind = .button
    @Published var status = "Ready"
    @Published private(set) var myApps: [MyAppDefinition] = []
    @Published var liveSnapshot: ElementSnapshot?
    @Published var pendingCapture: PendingElementCapture?
    @Published var menuItems: [MenuItemSnapshot] = []

    private let contextReader = AccessibilityContextReader()
    private let hammerspoon: HammerspoonClient
    private let appLauncher = AppLauncher()
    private var handledCaptureIDs = Set<String>()
    private var registryReady = false

    init(hammerspoon: HammerspoonClient = HammerspoonClient(), legacyDefaults: UserDefaults = .standard) {
        self.hammerspoon = hammerspoon
        for source in [CaptureSource.accessibility, .dom] {
            if let id = hammerspoon.latestSnapshot(source: source)?.captureID { handledCaptureIDs.insert(id) }
        }
        do {
            let registry: ActionRegistry
            if hammerspoon.hasCanonicalRegistry {
                registry = try hammerspoon.loadRegistry()
            } else {
                let data = legacyDefaults.data(forKey: "XSpoon.myApps")
                let legacyApps = try data.map { try JSONDecoder().decode([MyAppDefinition].self, from: $0) } ?? MyAppsCatalog.all
                registry = try hammerspoon.loadRegistry(legacyApps: legacyApps,
                    deletedAppIDs: Set(legacyDefaults.stringArray(forKey: "XSpoon.deletedAppIDs") ?? []),
                    deletedShortcutIDs: Set(legacyDefaults.stringArray(forKey: "XSpoon.deletedShortcutIDs") ?? []),
                    legacyCatalogData: data)
            }
            myApps = registry.apps.map(\.definition)
            registryReady = true
        } catch {
            status = "Registry unavailable: \(error.localizedDescription)"
        }
    }

    func refresh() {
        let currentContext = contextReader.read()
        if currentContext.bundleIdentifier != "com.singleton23.XSpoon", !currentContext.bundleIdentifier.isEmpty {
            context = currentContext
        }
    }

    func loadMenuItems() {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".hammerspoon/menu_items_latest.json")
        guard let data = try? Data(contentsOf: url),
              let items = try? JSONDecoder().decode([MenuItemSnapshot].self, from: data) else {
            menuItems = []
            return
        }
        menuItems = items
    }

    func toggleInspecting() {
        switch hammerspoon.toggleLiveInspector() {
        case .success: synchronizeInspection()
        case .failure(let error): status = error.localizedDescription
        }
    }

    func startInspecting() {
        if !hammerspoon.inspectionActive() { toggleInspecting() }
    }

    func stopInspecting() {
        _ = hammerspoon.stopLiveInspector()
        synchronizeInspection()
    }

    func synchronizeInspection() {
        isInspecting = hammerspoon.inspectionActive()
        if !isInspecting { liveSnapshot = nil }
    }

    func updateLiveSnapshot(_ snapshot: ElementSnapshot, context: AppContext) {
        self.context = context
        self.liveSnapshot = snapshot
        self.snapshot = snapshot
        if let kind = AdapterKind.detect(snapshot) {
            selectedAdapter = kind
            status = kind.rawValue
        } else {
            status = "Unsupported item"
        }
    }

    func capture() {
        _ = createElementFromCurrentTarget()
    }

    func createElementFromCurrentTarget() -> PendingElementCapture? {
        switch hammerspoon.captureCurrentTarget() {
        case .failure(let error):
            status = "Capture failed: \(error.localizedDescription)"
            return nil
        case .success(let response):
            guard let data = response.data(using: .utf8),
                  let receipt = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                status = "Capture failed: invalid receipt"
                return nil
            }
            if receipt["status"] as? String == "selector-picker-active" {
                status = "Choose a control in Chrome"
                return nil
            }
            guard let id = receipt["captureID"] as? String,
                  let captured = hammerspoon.latestSnapshot(source: .accessibility), captured.captureID == id else {
                status = "Capture failed: no matching fresh capture"
                return nil
            }
            return acceptCapturedElement(captured)
        }
    }

    func receiveCompletedCapture(source: CaptureSource) -> PendingElementCapture? {
        guard let captured = hammerspoon.latestSnapshot(source: source) else { return nil }
        return acceptCapturedElement(captured)
    }

    private func acceptCapturedElement(_ captured: ElementSnapshot) -> PendingElementCapture? {
        guard let id = captured.captureID, !id.isEmpty, !handledCaptureIDs.contains(id),
              !captured.appBundleIdentifier.isEmpty else { return nil }
        handledCaptureIDs.insert(id)
        isInspecting = false
        liveSnapshot = nil
        guard let kind = AdapterKind.detect(captured) else {
            status = "Capture a button, menu option, or text field"
            return nil
        }
        selectedAdapter = kind
        snapshot = captured
        context = AppContext(appName: captured.appDisplayName, bundleIdentifier: captured.appBundleIdentifier, windowTitle: captured.windowTitle ?? "", source: captured.captureSource)
        status = "Ready for shortcut"
        copySnapshotToClipboard(captured)
        guard let app = ensureApp(for: captured) else { return nil }
        let pending = PendingElementCapture(snapshot: captured, appID: app.id, kind: kind)
        pendingCapture = pending
        return pending
    }

    func focus(_ app: MyAppDefinition) {
        status = appLauncher.focus(app) ? "Focused \(app.name)" : "Could not open \(app.name)"
    }

    @discardableResult
    func saveElementShortcut(_ shortcut: AppShortcut, forAppID appID: String, snapshot: ElementSnapshot, menuItemTitle: String? = nil) -> Bool {
        guard registryReady, let app = myApps.first(where: { $0.id == appID }) else { return false }

        do {
            let saved = try hammerspoon.saveElementAction(app: app, shortcut: shortcut, snapshot: snapshot, menuItemTitle: menuItemTitle)
            try reloadRegistry()
            _ = try hammerspoon.refreshSavedShortcuts(actionID: saved.id).get()
            status = "Saved \(app.name) shortcut"
            return true
        } catch {
            status = "Could not save capture: \(error.localizedDescription)"
            return false
        }
    }

    func app(id: String) -> MyAppDefinition? {
        myApps.first(where: { $0.id == id })
    }

    func deleteShortcut(_ shortcut: AppShortcut, from app: MyAppDefinition) {
        guard registryReady else { return }
        do {
            try hammerspoon.deleteElementAction(id: shortcut.id)
            try reloadRegistry()
            _ = try hammerspoon.refreshSavedShortcuts().get()
            status = "Deleted \(shortcut.action)"
        } catch {
            status = "Could not delete shortcut: \(error.localizedDescription)"
        }
    }

    func deleteApp(_ app: MyAppDefinition) {
        guard registryReady else { return }
        do {
            try hammerspoon.deleteElementActions(for: app)
            try reloadRegistry()
            _ = try hammerspoon.refreshSavedShortcuts().get()
            status = "Removed \(app.name)"
        } catch {
            status = "Could not remove app: \(error.localizedDescription)"
        }
    }

    func addAppFromCurrentContext() {
        guard registryReady else { return }
        refresh()
        guard !context.bundleIdentifier.isEmpty else {
            status = "No front app to add"
            return
        }

        if myApps.contains(where: { $0.bundleIdentifier == context.bundleIdentifier }) {
            status = "\(context.appName) already exists"
            return
        }

        let app = MyAppDefinition(
            id: Self.slug(context.appName.isEmpty ? context.bundleIdentifier : context.appName),
            name: context.appName.isEmpty ? context.bundleIdentifier : context.appName,
            bundleIdentifier: context.bundleIdentifier,
            icon: "app.badge"
        )
        do {
            try hammerspoon.addRegistryApp(app)
            try reloadRegistry()
            status = "Added \(app.name)"
        } catch { status = "Could not add app: \(error.localizedDescription)" }
    }

    private func reloadRegistry() throws {
        myApps = try hammerspoon.loadRegistry().apps.map(\.definition)
    }

    private func copySnapshotToClipboard(_ snapshot: ElementSnapshot) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(snapshot),
              let value = String(data: data, encoding: .utf8) else { return }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func ensureApp(for snapshot: ElementSnapshot) -> MyAppDefinition? {
        guard registryReady else { return nil }
        if let existing = myApps.first(where: { $0.bundleIdentifier == snapshot.appBundleIdentifier }), !snapshot.appBundleIdentifier.isEmpty {
            return existing
        }

        let name = snapshot.appDisplayName
        let app = MyAppDefinition(
            id: Self.slug(name.isEmpty ? snapshot.appBundleIdentifier : name),
            name: name.isEmpty ? "Unknown App" : name,
            bundleIdentifier: snapshot.appBundleIdentifier,
            icon: "app.badge"
        )
        do {
            try hammerspoon.addRegistryApp(app)
            try reloadRegistry()
            return app
        } catch {
            status = "Could not add captured app: \(error.localizedDescription)"
            return nil
        }
    }

    private static func slug(_ value: String) -> String {
        let lowered = value.lowercased()
        let scalars = lowered.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "-" }
        let collapsed = String(scalars).split(separator: "-").joined(separator: "-")
        return collapsed.isEmpty ? UUID().uuidString : collapsed
    }
}
