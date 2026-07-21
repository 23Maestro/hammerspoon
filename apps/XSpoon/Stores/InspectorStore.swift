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
    @Published var myApps = MyAppsCatalog.all
    @Published var liveSnapshot: ElementSnapshot?
    @Published var pendingCapture: PendingElementCapture?

    private let contextReader = AccessibilityContextReader()
    private let hammerspoon = HammerspoonClient()
    private let appLauncher = AppLauncher()

    private let savedAppsKey = "XSpoon.myApps"
    private let deletedAppIDsKey = "XSpoon.deletedAppIDs"
    private let deletedShortcutIDsKey = "XSpoon.deletedShortcutIDs"
    private let staleShortcutIDs: Set<String> = [
        "chrome-3A067D54-ECDF-407F-8481-6E31A7A92D3D",
        "chatgpt-F63AF330-DB4A-497E-BCD2-ABAEA210B1FB",
        "mac-sai-E6C2D12D-C721-4E28-B46A-5F1F8FA11158",
        "chatgpt-5B0921FA-E75F-4149-A973-5C5A7088CD2F",
        "chatgpt-F6FAF464-FED8-4285-9FA5-51E7A36A9B79",
        "chatgpt-A6908D04-EDD7-48E7-9FBC-B95E2029B54F"
    ]
    private let staleAppIDs: Set<String> = [
        "mac-sai",
        "open-and-save-panel-service-google-chrome"
    ]

    init() {
        purgeKnownStaleDefaults()
        let deletedAppIDs = Set(UserDefaults.standard.stringArray(forKey: deletedAppIDsKey) ?? [])
        let deletedShortcutIDs = Set(UserDefaults.standard.stringArray(forKey: deletedShortcutIDsKey) ?? [])
        if let data = UserDefaults.standard.data(forKey: savedAppsKey),
           let saved = try? JSONDecoder().decode([MyAppDefinition].self, from: data) {
            myApps = Self.mergedApps(
                saved: saved,
                builtIns: MyAppsCatalog.all,
                deletedAppIDs: deletedAppIDs,
                deletedShortcutIDs: deletedShortcutIDs
            )
            persistApps()
        } else {
            myApps = Self.mergedApps(
                saved: [],
                builtIns: MyAppsCatalog.all,
                deletedAppIDs: deletedAppIDs,
                deletedShortcutIDs: deletedShortcutIDs
            )
        }
    }

    func refresh() {
        let currentContext = contextReader.read()
        let latestSnapshot = hammerspoon.latestSnapshot(source: currentContext.source)
        snapshot = latestSnapshot
        context = AppContext(
            appName: latestSnapshot?.appName ?? currentContext.appName,
            bundleIdentifier: latestSnapshot?.bundleID ?? currentContext.bundleIdentifier,
            windowTitle: latestSnapshot?.windowTitle ?? currentContext.windowTitle,
            source: latestSnapshot?.captureSource ?? currentContext.source
        )
        status = snapshot == nil ? "No captured element" : "Latest capture loaded"
    }

    func toggleInspecting() {
        isInspecting ? stopInspecting() : startInspecting()
    }

    func startInspecting() {
        refresh()
        isInspecting = true
        status = "Choose a type, point at the item, then press Capture"
    }

    func stopInspecting() {
        isInspecting = false
        liveSnapshot = nil
        status = "Inspect mode paused"
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
        let bridgeResult = hammerspoon.captureCurrentTarget()
        refresh()
        isInspecting = false
        switch bridgeResult {
        case .success:
            status = snapshot == nil ? "Capture returned no snapshot" : "Element captured"
        case .failure(let error):
            status = "Hammerspoon unavailable: \(error.localizedDescription)"
        }
    }

    func createElementFromCurrentTarget() -> PendingElementCapture? {
        let captured: ElementSnapshot

        if let liveSnapshot {
            captured = liveSnapshot
            snapshot = liveSnapshot
            status = "Element ready"
        } else {
            capture()
            guard let snapshot else { return nil }
            captured = snapshot
        }

        isInspecting = false
        liveSnapshot = nil
        guard let kind = AdapterKind.detect(captured) else {
            status = "Capture a button, menu option, or text field"
            return nil
        }
        selectedAdapter = kind
        copySnapshotToClipboard(captured)
        let app = ensureApp(for: captured)
        let pending = PendingElementCapture(snapshot: captured, appID: app.id, kind: kind)
        pendingCapture = pending
        return pending
    }

    func focus(_ app: MyAppDefinition) {
        status = appLauncher.focus(app) ? "Focused \(app.name)" : "Could not open \(app.name)"
    }

    func updateShortcut(_ shortcut: AppShortcut, for app: MyAppDefinition) {
        guard let index = myApps.firstIndex(where: { $0.id == app.id }) else { return }
        removeDeletedShortcutID(shortcut.id)
        var updated = myApps[index]
        updated.shortcuts.removeAll { $0.id == shortcut.id }
        updated.shortcuts.append(shortcut)
        myApps[index] = updated
        persistApps()
        status = "Saved \(updated.name) shortcut"
    }

    func updateShortcut(_ shortcut: AppShortcut, forAppID appID: String) {
        guard let app = myApps.first(where: { $0.id == appID }) else { return }
        updateShortcut(shortcut, for: app)
    }

    func saveElementShortcut(_ shortcut: AppShortcut, forAppID appID: String, snapshot: ElementSnapshot) {
        guard let app = myApps.first(where: { $0.id == appID }) else { return }
        updateShortcut(shortcut, for: app)

        do {
            try hammerspoon.saveElementAction(app: app, shortcut: shortcut, snapshot: snapshot)
            switch hammerspoon.reloadSavedElementRoutes(actionID: shortcut.id) {
            case .success(let receipt) where receipt.contains("capture-saved-module-required"):
                status = "Saved capture. Add app module test next."
            case .success:
                status = "Saved capture, but no app module owns it"
            case .failure(let error):
                status = "Saved capture, but Hammerspoon did not answer: \(error.localizedDescription)"
            }
        } catch {
            status = "Could not save capture: \(error.localizedDescription)"
        }
    }

    func app(id: String) -> MyAppDefinition? {
        myApps.first(where: { $0.id == id })
    }

    func deleteShortcut(_ shortcut: AppShortcut, from app: MyAppDefinition) {
        do {
            try hammerspoon.deleteElementAction(id: shortcut.id)
            guard let index = myApps.firstIndex(where: { $0.id == app.id }) else { return }
            myApps[index].shortcuts.removeAll { $0.id == shortcut.id }
            addDeletedShortcutID(shortcut.id)
            persistApps()
            _ = hammerspoon.reloadSavedElementRoutes()
            status = "Deleted \(shortcut.action)"
        } catch {
            status = "Could not delete shortcut: \(error.localizedDescription)"
        }
    }

    func deleteApp(_ app: MyAppDefinition) {
        do {
            try hammerspoon.deleteElementActions(for: app)
            myApps.removeAll { $0.id == app.id }
            addDeletedAppID(app.id)
            persistApps()
            _ = hammerspoon.reloadSavedElementRoutes()
            status = "Removed \(app.name)"
        } catch {
            status = "Could not remove app: \(error.localizedDescription)"
        }
    }

    func addAppFromCurrentContext() {
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
        removeDeletedAppID(app.id)
        myApps.append(app)
        persistApps()
        status = "Added \(app.name)"
    }

    private func persistApps() {
        guard let data = try? JSONEncoder().encode(myApps) else { return }
        UserDefaults.standard.set(data, forKey: savedAppsKey)
    }

    private func purgeKnownStaleDefaults() {
        for id in staleShortcutIDs {
            addDeletedShortcutID(id)
        }
        for id in staleAppIDs {
            addDeletedAppID(id)
        }
    }

    private func copySnapshotToClipboard(_ snapshot: ElementSnapshot) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(snapshot),
              let value = String(data: data, encoding: .utf8) else { return }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func ensureApp(for snapshot: ElementSnapshot) -> MyAppDefinition {
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
        myApps.append(app)
        persistApps()
        return app
    }

    private func addDeletedAppID(_ id: String) {
        var ids = Set(UserDefaults.standard.stringArray(forKey: deletedAppIDsKey) ?? [])
        ids.insert(id)
        UserDefaults.standard.set(Array(ids), forKey: deletedAppIDsKey)
    }

    private func removeDeletedAppID(_ id: String) {
        var ids = Set(UserDefaults.standard.stringArray(forKey: deletedAppIDsKey) ?? [])
        ids.remove(id)
        UserDefaults.standard.set(Array(ids), forKey: deletedAppIDsKey)
    }

    private func addDeletedShortcutID(_ id: String) {
        var ids = Set(UserDefaults.standard.stringArray(forKey: deletedShortcutIDsKey) ?? [])
        ids.insert(id)
        UserDefaults.standard.set(Array(ids), forKey: deletedShortcutIDsKey)
    }

    private func removeDeletedShortcutID(_ id: String) {
        var ids = Set(UserDefaults.standard.stringArray(forKey: deletedShortcutIDsKey) ?? [])
        ids.remove(id)
        UserDefaults.standard.set(Array(ids), forKey: deletedShortcutIDsKey)
    }

    private static func mergedApps(
        saved: [MyAppDefinition],
        builtIns: [MyAppDefinition],
        deletedAppIDs: Set<String>,
        deletedShortcutIDs: Set<String>
    ) -> [MyAppDefinition] {
        var merged = saved
            .filter { !deletedAppIDs.contains($0.id) }
            .map { app in
                var app = app
                app.shortcuts.removeAll { deletedShortcutIDs.contains($0.id) }
                return app
            }

        for var builtIn in builtIns where !deletedAppIDs.contains(builtIn.id) {
            builtIn.shortcuts.removeAll { deletedShortcutIDs.contains($0.id) }
            if let index = merged.firstIndex(where: { $0.id == builtIn.id || $0.bundleIdentifier == builtIn.bundleIdentifier }) {
                merged[index].name = builtIn.name
                merged[index].bundleIdentifier = builtIn.bundleIdentifier
                merged[index].icon = builtIn.icon

                for shortcut in builtIn.shortcuts where !merged[index].shortcuts.contains(where: { $0.id == shortcut.id }) {
                    merged[index].shortcuts.append(shortcut)
                }
            } else {
                merged.append(builtIn)
            }
        }

        return merged
    }

    private static func slug(_ value: String) -> String {
        let lowered = value.lowercased()
        let scalars = lowered.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "-" }
        let collapsed = String(scalars).split(separator: "-").joined(separator: "-")
        return collapsed.isEmpty ? UUID().uuidString : collapsed
    }
}
