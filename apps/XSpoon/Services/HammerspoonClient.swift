import Foundation

struct HammerspoonClient {
    private let home: URL
    private let transport: ((String) -> Result<String, Error>)?

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser, transport: ((String) -> Result<String, Error>)? = nil) {
        self.home = home
        self.transport = transport
    }
    private var hammerspoonDirectory: URL {
        home.appendingPathComponent(".hammerspoon")
    }
    var hasCanonicalRegistry: Bool {
        FileManager.default.fileExists(atPath: ActionRegistryStore(directory: hammerspoonDirectory).url.path)
    }

    func loadRegistry(legacyApps: [MyAppDefinition] = [], deletedAppIDs: Set<String> = [], deletedShortcutIDs: Set<String> = [], legacyCatalogData: Data? = nil) throws -> ActionRegistry {
        try ActionRegistryStore(directory: hammerspoonDirectory).loadOrMigrate(legacyApps: legacyApps,
            deletedAppIDs: deletedAppIDs, deletedShortcutIDs: deletedShortcutIDs, legacyCatalogData: legacyCatalogData)
    }

    func addRegistryApp(_ app: MyAppDefinition) throws {
        var registry = try loadRegistry()
        guard !registry.apps.contains(where: { $0.bundleIdentifier == app.bundleIdentifier }) else { return }
        registry.apps.append(RegistryApp(id: app.id, name: app.name, bundleIdentifier: app.bundleIdentifier, icon: app.icon, actions: []))
        try ActionRegistryStore(directory: hammerspoonDirectory).save(registry)
    }

    func latestSnapshot(source: CaptureSource) -> ElementSnapshot? {
        let filename = source == .accessibility ? "local_element_latest.json" : "browser_element_latest.json"
        return snapshot(filename: filename, maxAge: 60)
    }

    func liveSnapshot() -> ElementSnapshot? {
        snapshot(filename: "live_element_latest.json", maxAge: 60)
    }

    func inspectionActive() -> Bool {
        let url = hammerspoonDirectory.appendingPathComponent("xspoon_inspection_state.json")
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return state["active"] as? Bool == true
    }

    @discardableResult
    func stopLiveInspector() -> Result<String, Error> {
        executeHammerspoon("return __SCRIPTS__.stopLiveInspector()")
    }

    @discardableResult
    func toggleLiveInspector() -> Result<String, Error> {
        executeHammerspoon("return __SCRIPTS__.toggleLiveInspector()")
    }

    private func snapshot(filename: String, maxAge: TimeInterval? = nil) -> ElementSnapshot? {
        let url = home.appendingPathComponent(".hammerspoon").appendingPathComponent(filename)
        if let maxAge,
           let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
           let modified = values.contentModificationDate,
           Date().timeIntervalSince(modified) > maxAge {
            return nil
        }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ElementSnapshot.self, from: data)
    }

    func captureCurrentTarget() -> Result<String, Error> {
        executeHammerspoon("return __SCRIPTS__.captureCurrentTarget()")
    }

    @discardableResult
    func saveElementAction(app: MyAppDefinition, shortcut: AppShortcut, snapshot: ElementSnapshot, menuItemTitle: String? = nil) throws -> ElementAction {
        guard snapshot.bundleID == app.bundleIdentifier else {
            throw HammerspoonClientError("The captured control belongs to a different app")
        }
        guard ModifierCatalog.all.contains(where: { $0.id == shortcut.modifierID }),
              shortcut.key.count == 1, shortcut.key.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) }) else {
            throw HammerspoonClientError("Choose a known modifier and one letter or number")
        }
        var registry = try loadRegistry()
        let actions = registry.capturedActions
        var action = ElementAction(app: app, shortcut: shortcut, snapshot: snapshot)
        action.setMenuItemTitle(menuItemTitle)
        if let existing = actions.first(where: {
            $0.appBundleID == action.appBundleID && $0.hotkey.key == action.hotkey.key
                && $0.hotkey.modifiers.sorted() == action.hotkey.modifiers.sorted()
                && $0.targetsSameControl(as: action)
        }) {
            action.id = existing.id
        }
        try validateHotkey(action, against: actions)
        var review = ActionRegistryStore.initialReview(action)
        if let previous = registry.apps.flatMap(\.actions).first(where: { $0.id == action.id }),
           let payload = previous.payload, previous.review.state == .verified,
           payload.targetsSameControl(as: action), payload.hotkey == action.hotkey {
            review = previous.review
        }
        guard review.state != .blocked && review.state != .needsRecapture else { throw RegistryError(review.reason) }
        if !registry.apps.contains(where: { $0.bundleIdentifier == app.bundleIdentifier }) {
            registry.apps.append(RegistryApp(id: app.id, name: app.name, bundleIdentifier: app.bundleIdentifier, icon: app.icon, actions: []))
        }
        let index = registry.apps.firstIndex { $0.bundleIdentifier == app.bundleIdentifier }!
        registry.apps[index].actions.removeAll { $0.id == action.id }
        registry.apps[index].actions.append(RegistryAction(payload: action, modifierID: shortcut.modifierID, origin: "capture", review: review))
        try ActionRegistryStore(directory: hammerspoonDirectory).save(registry)
        return action
    }

    func deleteElementAction(id: String) throws {
        var registry = try loadRegistry()
        for app in registry.apps {
            for record in app.actions where record.id == id {
                if let shortcut = record.legacyShortcut {
                    try disableLegacyShortcut(shortcut, bundleID: app.bundleIdentifier, in: &registry)
                }
            }
        }
        for index in registry.apps.indices { registry.apps[index].actions.removeAll { $0.id == id } }
        try ActionRegistryStore(directory: hammerspoonDirectory).save(registry)
    }

    func deleteElementActions(for app: MyAppDefinition) throws {
        var registry = try loadRegistry()
        for parent in registry.apps where parent.bundleIdentifier == app.bundleIdentifier {
            for record in parent.actions {
                if let shortcut = record.legacyShortcut {
                    try disableLegacyShortcut(shortcut, bundleID: parent.bundleIdentifier, in: &registry)
                }
            }
        }
        registry.apps.removeAll { $0.bundleIdentifier == app.bundleIdentifier }
        try ActionRegistryStore(directory: hammerspoonDirectory).save(registry)
    }

    private func disableLegacyShortcut(_ shortcut: AppShortcut, bundleID: String, in registry: inout ActionRegistry) throws {
        let preset = ModifierCatalog.preset(shortcut.modifierID)
        guard !bundleID.isEmpty, !shortcut.key.isEmpty,
              !preset.hammerspoonModifiers.isEmpty || preset.id == ModifierCatalog.singleKey.id else {
            throw RegistryError("Cannot safely disable this legacy shortcut: missing app, key or modifier")
        }
        var rules = registry.disabledLegacyShortcuts ?? []
        let modifiers = preset.hammerspoonModifiers.sorted()
        let key = shortcut.key.lowercased()
        if !rules.contains(where: { $0.appBundleID == bundleID && $0.modifiers.sorted() == modifiers && $0.key == key }) {
            rules.append(DisabledLegacyShortcut(id: shortcut.id, appBundleID: bundleID, modifiers: modifiers, key: key))
        }
        registry.disabledLegacyShortcuts = rules
    }

    private func validateHotkey(_ action: ElementAction, against actions: [ElementAction]) throws {
        let key = action.hotkey.key.lowercased()
        let modifiers = action.hotkey.modifiers.sorted()
        if ActionRegistryStore.isReserved(action.hotkey) {
            throw HammerspoonClientError("\(key.uppercased()) is reserved by a global Hammerspoon shortcut")
        }

        if let conflict = actions.first(where: {
            $0.id != action.id
                && $0.appBundleID == action.appBundleID
                && $0.hotkey.key.lowercased() == key
                && $0.hotkey.modifiers.sorted() == modifiers
        }) {
            throw HammerspoonClientError("This app already uses that shortcut for \(conflict.name)")
        }
    }

    @discardableResult
    func refreshSavedShortcuts(actionID: String? = nil) -> Result<String, Error> {
        let result = executeHammerspoon("return hs.json.encode(xspoonRuntime:start():status())")
        guard let actionID else { return result }
        return result.flatMap { text in
            guard let data = text.data(using: .utf8),
                  let receipt = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let ids = receipt["registeredActionIDs"] as? [String], ids.contains(actionID) else {
                return .failure(HammerspoonClientError("Saved shortcut was not registered by Hammerspoon"))
            }
            return .success(text)
        }
    }

    func readElementActions() throws -> [ElementAction] {
        try loadRegistry().capturedActions
    }

    private func executeHammerspoon(_ lua: String) -> Result<String, Error> {
        let result = transport?(lua) ?? runAppleScript(lua)
        return result.flatMap { text in
            guard let data = text.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
                  let receipt = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .failure(HammerspoonClientError("Hammerspoon returned an invalid response"))
            }
            if receipt["error"] != nil || receipt["status"] as? String == "error" {
                return .failure(HammerspoonClientError(receipt["message"] as? String ?? receipt["error"] as? String ?? "Hammerspoon action failed"))
            }
            return .success(text)
        }
    }

    private func runAppleScript(_ lua: String) -> Result<String, Error> {
        let escaped = lua.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Hammerspoon"
          execute lua code "\(escaped)"
        end tell
        """
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = output
        process.standardError = output
        let completed = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in completed.signal() }

        do {
            try process.run()
            guard completed.wait(timeout: .now() + 5) == .success else {
                process.terminate()
                process.waitUntilExit()
                return .failure(HammerspoonClientError("Hammerspoon request timed out"))
            }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let result = String(data: data, encoding: .utf8) ?? ""
            guard process.terminationStatus == 0 else {
                return .failure(NSError(domain: "Hammerspoon", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: result]))
            }
            return .success(result)
        } catch {
            return .failure(error)
        }
    }
}

private struct HammerspoonClientError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct ElementAction: Codable, Equatable {
    struct Hotkey: Codable, Equatable {
        var modifiers: [String]
        var key: String
    }

    var id: String
    var name: String
    var variant: String
    var template: String
    var semanticAction: String
    var hotkey: Hotkey
    var appName: String?
    var appBundleID: String?
    var appPath: String?
    var windowTitleIncludes: String?
    var surface: String?
    var captureButton: String?
    var replayIntent: String?
    var captureType: String?
    var menuItemTitle: String?
    var axAction: String?
    var axActions: [String]?
    var axRole: String?
    var axTitle: String?
    var axValue: String?
    var axDescription: String?
    var axIdentifier: String?
    var frame: SnapshotRect?
    var windowFrame: SnapshotRect?
    var selector: String?
    var urlIncludes: String?
    var titleIncludes: String?
    var requiredSelector: String?

    func targetsSameControl(as other: ElementAction) -> Bool {
        guard appBundleID == other.appBundleID, variant == other.variant else { return false }
        if variant == "browser" {
            return selector != nil && selector == other.selector && urlIncludes == other.urlIncludes
        }
        let hasIdentity = axIdentifier != nil || axTitle != nil || axDescription != nil
        return hasIdentity && axRole == other.axRole && axIdentifier == other.axIdentifier
            && axTitle == other.axTitle && axDescription == other.axDescription
            && menuItemTitle == other.menuItemTitle
    }

    init(app: MyAppDefinition, shortcut: AppShortcut, snapshot: ElementSnapshot) {
        let modifier = ModifierCatalog.preset(shortcut.modifierID)
        let trimmedAction = shortcut.action.trimmingCharacters(in: .whitespacesAndNewlines)
        let isBrowser = snapshot.kind == "hammerspoon-browser-element" || snapshot.selector?.isEmpty == false

        id = shortcut.id
        name = trimmedAction.isEmpty ? snapshot.displayTitle : trimmedAction
        variant = isBrowser ? "browser" : "local"
        template = "single"
        semanticAction = Self.semanticAction(for: shortcut)
        hotkey = Hotkey(modifiers: modifier.hammerspoonModifiers, key: shortcut.key.lowercased())

        appName = snapshot.appName?.nilIfBlank ?? app.name
        appBundleID = snapshot.bundleID?.nilIfBlank ?? app.bundleIdentifier
        appPath = snapshot.appPath?.nilIfBlank
        // Window titles are observed context, not stable native-control identity.
        windowTitleIncludes = nil
        surface = snapshot.effectiveSurface
        captureButton = snapshot.effectiveCaptureButton
        replayIntent = Self.replayIntent(for: snapshot, captureType: AdapterKind.detect(snapshot)?.rawValue)
        captureType = AdapterKind.detect(snapshot)?.rawValue
        axActions = snapshot.actions
        axAction = Self.replayAction(for: replayIntent)

        let fallbackButtonLabel = Self.buttonLabel(from: name)
        axRole = snapshot.role?.nilIfBlank ?? (fallbackButtonLabel == nil ? nil : "AXButton")
        axTitle = snapshot.axTitle?.nilIfBlank
        axValue = snapshot.axValue?.nilIfBlank
        axDescription = snapshot.axDescription?.nilIfBlank ?? fallbackButtonLabel
        axIdentifier = snapshot.axIdentifier?.nilIfBlank
        frame = snapshot.frame
        windowFrame = snapshot.windowFrame

        selector = snapshot.selector?.nilIfBlank
        urlIncludes = snapshot.url?.nilIfBlank
        titleIncludes = snapshot.title?.nilIfBlank
        requiredSelector = nil
    }

    mutating func setMenuItemTitle(_ title: String?) {
        menuItemTitle = title
        if title?.nilIfBlank != nil {
            replayIntent = "menuItem"
            axAction = nil
        }
    }

    private static func replayIntent(for snapshot: ElementSnapshot, captureType: String?) -> String {
        if let replayIntent = snapshot.replayIntent?.nilIfBlank {
            return replayIntent
        }
        if snapshot.effectiveCaptureButton == "right" {
            return "openContextMenu"
        }
        if captureType == AdapterKind.textField.rawValue {
            return "focus"
        }
        if snapshot.effectiveSurface == "website" {
            return captureType == AdapterKind.textField.rawValue ? "focus" : "domClick"
        }
        if snapshot.effectiveSurface == "webApp", captureType == AdapterKind.button.rawValue {
            return "physicalClick"
        }
        if snapshot.actions?.contains("AXPress") == true {
            return "press"
        }
        return "unresolved"
    }

    private static func replayAction(for replayIntent: String?) -> String? {
        switch replayIntent {
        case "focus":
            return "AXFocus"
        case "press":
            return "AXPress"
        default:
            return nil
        }
    }

    private static func semanticAction(for shortcut: AppShortcut) -> String {
        switch shortcut.key.lowercased() {
        case "c": "copy"
        case "m", "o": "secondary"
        case "p": "primary"
        case "r": "search"
        case "s": "shortcutS"
        case "v": "voicemail"
        default: shortcut.action
        }
    }

    private static func buttonLabel(from actionName: String) -> String? {
        let trimmed = actionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.localizedCaseInsensitiveContains("click ") else { return nil }

        let parts = trimmed.split(separator: " ", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }

        let label = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        return label.isEmpty ? nil : label
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
