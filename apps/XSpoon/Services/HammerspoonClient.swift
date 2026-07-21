import Foundation

struct HammerspoonClient {
    private let home = FileManager.default.homeDirectoryForCurrentUser
    private var hammerspoonDirectory: URL {
        home.appendingPathComponent(".hammerspoon")
    }
    private var elementActionsURL: URL {
        hammerspoonDirectory.appendingPathComponent("browser_element_actions.json")
    }

    func latestSnapshot(source: CaptureSource) -> ElementSnapshot? {
        let filename = source == .accessibility ? "local_element_latest.json" : "browser_element_latest.json"
        return snapshot(filename: filename, maxAge: 60)
    }

    func liveSnapshot() -> ElementSnapshot? {
        snapshot(filename: "live_element_latest.json")
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

    func saveElementAction(app: MyAppDefinition, shortcut: AppShortcut, snapshot: ElementSnapshot, menuItemTitle: String? = nil) throws {
        var actions = try readElementActions()
        var action = ElementAction(app: app, shortcut: shortcut, snapshot: snapshot)
        action.menuItemTitle = menuItemTitle
        actions.removeAll { $0.id == action.id }
        actions.append(action)
        try writeElementActions(actions)
    }

    func deleteElementAction(id: String) throws {
        var actions = try readElementActions()
        actions.removeAll { $0.id == id }
        try writeElementActions(actions)
    }

    func deleteElementActions(for app: MyAppDefinition) throws {
        var actions = try readElementActions()
        actions.removeAll {
            let bundleID = $0.appBundleID?.nilIfBlank
            return bundleID == app.bundleIdentifier || (bundleID == nil && $0.appName == app.name)
        }
        try writeElementActions(actions)
    }

    private func writeElementActions(_ actions: [ElementAction]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(actions)
        try data.write(to: elementActionsURL, options: .atomic)
    }

    @discardableResult
    func reloadHammerspoon() -> Result<String, Error> {
        executeHammerspoon("hs.timer.doAfter(0.1, hs.reload); return 'reload-scheduled'")
    }

    @discardableResult
    func reloadSavedElementRoutes(actionID: String) -> Result<String, Error> {
        executeHammerspoon("return __SCRIPTS__.reloadElementActionHotkeys('\(actionID)')")
    }

    @discardableResult
    func reloadSavedElementRoutes() -> Result<String, Error> {
        executeHammerspoon("return __SCRIPTS__.reloadElementActionHotkeys()")
    }

    private func readElementActions() throws -> [ElementAction] {
        guard FileManager.default.fileExists(atPath: elementActionsURL.path) else {
            return []
        }

        let data = try Data(contentsOf: elementActionsURL)
        guard !data.isEmpty else {
            return []
        }

        return try JSONDecoder().decode([ElementAction].self, from: data)
    }

    private func executeHammerspoon(_ lua: String) -> Result<String, Error> {
        let script = """
        tell application "Hammerspoon"
          execute lua code "\(lua)"
        end tell
        """
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = output
        process.standardError = output

        do {
            try process.run()
            process.waitUntilExit()
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
    var captureType: String?
    var menuItemTitle: String?
    var axAction: String?
    var axActions: [String]?
    var axRole: String?
    var axTitle: String?
    var axValue: String?
    var axDescription: String?
    var frame: SnapshotRect?
    var windowFrame: SnapshotRect?
    var selector: String?
    var urlIncludes: String?
    var titleIncludes: String?
    var requiredSelector: String?

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
        windowTitleIncludes = snapshot.windowTitle?.nilIfBlank
        captureType = AdapterKind.detect(snapshot)?.rawValue
        axActions = snapshot.actions
        axAction = Self.replayAction(for: snapshot, captureType: captureType)

        let fallbackButtonLabel = Self.buttonLabel(from: name)
        axRole = snapshot.role?.nilIfBlank ?? (fallbackButtonLabel == nil ? nil : "AXButton")
        axTitle = snapshot.axTitle?.nilIfBlank
        axValue = snapshot.axValue?.nilIfBlank
        axDescription = snapshot.axDescription?.nilIfBlank ?? fallbackButtonLabel
        frame = snapshot.frame
        windowFrame = snapshot.windowFrame

        selector = snapshot.selector?.nilIfBlank
        urlIncludes = snapshot.url?.nilIfBlank
        titleIncludes = snapshot.title?.nilIfBlank
        requiredSelector = nil
    }

    private static func replayAction(for snapshot: ElementSnapshot, captureType: String?) -> String? {
        if captureType == AdapterKind.textField.rawValue {
            return "AXFocus"
        }
        if snapshot.actions?.contains("AXPress") == true {
            return "AXPress"
        }
        return nil
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
