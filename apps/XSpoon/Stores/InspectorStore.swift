import Foundation

@MainActor
final class InspectorStore: ObservableObject {
    static let shared = InspectorStore()

    @Published var context = AppContext()
    @Published var snapshot: ElementSnapshot?
    @Published var isInspecting = false
    @Published var selectedAdapter: AdapterKind = .setVariable
    @Published var status = "Ready"
    @Published var myApps = MyAppsCatalog.all
    @Published var liveSnapshot: ElementSnapshot?
    @Published var pendingCapture: PendingElementCapture?

    private let contextReader = AccessibilityContextReader()
    private let hammerspoon = HammerspoonClient()
    private let appLauncher = AppLauncher()

    private let savedAppsKey = "XSpoon.myApps"

    init() {
        if let data = UserDefaults.standard.data(forKey: savedAppsKey),
           let saved = try? JSONDecoder().decode([MyAppDefinition].self, from: data) {
            myApps = Self.mergedApps(saved: saved, builtIns: MyAppsCatalog.all)
            persistApps()
        } else {
            myApps = MyAppsCatalog.all
        }
    }

    func refresh() {
        context = contextReader.read()
        snapshot = hammerspoon.latestSnapshot(source: context.source)
        status = snapshot == nil ? "No captured element" : "Latest capture loaded"
    }

    func toggleInspecting() {
        isInspecting ? stopInspecting() : startInspecting()
    }

    func startInspecting() {
        refresh()
        isInspecting = true
        status = "Inspecting"
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
        self.status = "Hovering \(snapshot.displayTitle)"
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
        let app = ensureApp(for: captured)
        let pending = PendingElementCapture(snapshot: captured, appID: app.id)
        pendingCapture = pending
        return pending
    }

    func focus(_ app: MyAppDefinition) {
        status = appLauncher.focus(app) ? "Focused \(app.name)" : "Could not open \(app.name)"
    }

    func updateShortcut(_ shortcut: AppShortcut, for app: MyAppDefinition) {
        guard let index = myApps.firstIndex(where: { $0.id == app.id }) else { return }
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

    func app(id: String) -> MyAppDefinition? {
        myApps.first(where: { $0.id == id })
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
        myApps.append(app)
        persistApps()
        status = "Added \(app.name)"
    }

    private func persistApps() {
        guard let data = try? JSONEncoder().encode(myApps) else { return }
        UserDefaults.standard.set(data, forKey: savedAppsKey)
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

    private static func mergedApps(saved: [MyAppDefinition], builtIns: [MyAppDefinition]) -> [MyAppDefinition] {
        var merged = saved

        for builtIn in builtIns {
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
