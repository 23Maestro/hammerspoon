import Foundation

enum ActionReviewState: String, Codable {
    case verified, unverified, blocked, needsRecapture, inherited

    var label: String {
        switch self {
        case .verified: "Verified"
        case .unverified: "Unverified"
        case .blocked: "Blocked"
        case .needsRecapture: "Needs Recapture"
        case .inherited: "Legacy Script"
        }
    }
}

struct ActionReview: Codable, Equatable {
    var state: ActionReviewState
    var reason: String
    var verifiedAt: String?
}

struct RegistryAction: Codable, Equatable, Identifiable {
    var payload: ElementAction?
    var legacyShortcut: AppShortcut?
    var modifierID: String?
    var origin: String
    var review: ActionReview

    var id: String { payload?.id ?? legacyShortcut?.id ?? "" }
    var runnable: Bool {
        payload != nil && review.state != .blocked && review.state != .needsRecapture
    }

    var shortcut: AppShortcut {
        if let payload {
            let preset = modifierID ?? ModifierCatalog.all.first {
                $0.hammerspoonModifiers.sorted() == payload.hotkey.modifiers.sorted()
            }?.id ?? "custom"
            return AppShortcut(id: payload.id, action: payload.name, key: payload.hotkey.key.uppercased(), modifierID: preset,
                reviewState: review.state.rawValue, reviewReason: review.reason, origin: origin)
        }
        var shortcut = legacyShortcut ?? AppShortcut(id: "", action: "Missing record", key: "", modifierID: "custom")
        shortcut.reviewState = review.state.rawValue
        shortcut.reviewReason = review.reason
        shortcut.origin = origin
        return shortcut
    }
}

struct RegistryApp: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var bundleIdentifier: String
    var icon: String
    var actions: [RegistryAction]

    var definition: MyAppDefinition {
        MyAppDefinition(id: id, name: name, bundleIdentifier: bundleIdentifier, icon: icon, shortcuts: actions.map(\.shortcut))
    }
}

struct DisabledLegacyShortcut: Codable, Equatable {
    var id: String
    var appBundleID: String
    var modifiers: [String]
    var key: String
}

struct ActionRegistry: Codable, Equatable {
    var schemaVersion = 1
    var apps: [RegistryApp] = []
    var migrationBackup: String?
    var disabledLegacyShortcuts: [DisabledLegacyShortcut]?

    var capturedActions: [ElementAction] { apps.flatMap { $0.actions.compactMap(\.payload) } }
    var runnableActions: [ElementAction] { apps.flatMap { $0.actions.filter(\.runnable).compactMap(\.payload) } }
}

struct ActionRegistryStore {
    let directory: URL
    var url: URL { directory.appendingPathComponent("xspoon_registry.json") }

    func loadOrMigrate(legacyApps: [MyAppDefinition] = [], deletedAppIDs: Set<String> = [], deletedShortcutIDs: Set<String> = [], legacyCatalogData: Data? = nil) throws -> ActionRegistry {
        if FileManager.default.fileExists(atPath: url.path) { return try load() }
        let legacyURL = directory.appendingPathComponent("browser_element_actions.json")
        let oldData = FileManager.default.fileExists(atPath: legacyURL.path) ? try Data(contentsOf: legacyURL) : nil
        let captured = try oldData.map { try JSONDecoder().decode([ElementAction].self, from: $0) } ?? []
        var registry = ActionRegistry()
        for app in legacyApps where !deletedAppIDs.contains(app.id) {
            if registry.apps.contains(where: { $0.bundleIdentifier == app.bundleIdentifier }) { continue }
            registry.apps.append(RegistryApp(id: app.id, name: app.name, bundleIdentifier: app.bundleIdentifier, icon: app.icon, actions: []))
        }
        for payload in captured {
            let bundleID = payload.appBundleID ?? ""
            var index = registry.apps.firstIndex { $0.bundleIdentifier == bundleID }
            if index == nil {
                let builtIn = MyAppsCatalog.all.first { $0.bundleIdentifier == bundleID }
                registry.apps.append(RegistryApp(id: builtIn?.id ?? (bundleID.isEmpty ? "unassigned" : bundleID),
                    name: payload.appName ?? builtIn?.name ?? "Unassigned", bundleIdentifier: bundleID,
                    icon: builtIn?.icon ?? "app", actions: []))
                index = registry.apps.count - 1
            }
            let parent = index!
            guard !registry.apps[parent].actions.contains(where: { $0.id == payload.id }) else {
                throw RegistryError("Duplicate legacy capture ID; migration stopped without changing source data")
            }
            let legacyShortcut = legacyApps.flatMap(\.shortcuts).first { $0.id == payload.id }
            let preset = legacyShortcut.flatMap { shortcut in
                ModifierCatalog.preset(shortcut.modifierID).hammerspoonModifiers.sorted() == payload.hotkey.modifiers.sorted() ? shortcut.modifierID : nil
            }
            var review = Self.initialReview(payload)
            if deletedShortcutIDs.contains(payload.id) || deletedAppIDs.contains(registry.apps[parent].id) {
                review = ActionReview(state: .blocked, reason: "Previously removed; retained for review, not registered")
            }
            registry.apps[parent].actions.append(RegistryAction(payload: payload, modifierID: preset, origin: "capture", review: review))
        }
        for app in legacyApps where !deletedAppIDs.contains(app.id) {
            guard let index = registry.apps.firstIndex(where: { $0.bundleIdentifier == app.bundleIdentifier }) else { continue }
            for shortcut in app.shortcuts where !deletedShortcutIDs.contains(shortcut.id) {
                guard !registry.apps[index].actions.contains(where: { $0.id == shortcut.id }) else { continue }
                registry.apps[index].actions.append(RegistryAction(legacyShortcut: shortcut, origin: "legacyCommand",
                    review: ActionReview(state: .inherited, reason: "Inherited script command; not a captured action in XSpoon")))
            }
        }
        Self.flagDuplicates(&registry)
        let backup = directory.appendingPathComponent("backups/xspoon-registry-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if let oldData { try oldData.write(to: backup.appendingPathComponent("browser_element_actions.json")) }
        try (legacyCatalogData ?? JSONEncoder().encode(legacyApps)).write(to: backup.appendingPathComponent("legacy-catalog.json"))
        let deleted = ["apps": Array(deletedAppIDs).sorted(), "shortcuts": Array(deletedShortcutIDs).sorted()]
        try JSONEncoder().encode(deleted).write(to: backup.appendingPathComponent("legacy-deletions.json"))
        registry.migrationBackup = backup.path
        try save(registry)
        return registry
    }

    func save(_ registry: ActionRegistry) throws {
        try validate(registry)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoder.encode(registry).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func isReserved(_ hotkey: ElementAction.Hotkey) -> Bool {
        hotkey.modifiers.sorted() == ["alt", "ctrl"] && Set(["i", "o", "0", "m", "p", "r", "c", "s", "v"]).contains(hotkey.key.lowercased())
    }

    static func initialReview(_ action: ElementAction) -> ActionReview {
        if isReserved(action.hotkey) {
            return ActionReview(state: .blocked, reason: "Reserved global shortcut; choose a different key or modifier")
        }
        guard action.appBundleID?.isEmpty == false else {
            return ActionReview(state: .blocked, reason: "Missing target app identity")
        }
        if let evidenceURL = Bundle.module.url(forResource: "RegistryMigrationEvidence", withExtension: "json"),
           let data = try? Data(contentsOf: evidenceURL),
           let evidence = try? JSONDecoder().decode([MigrationEvidence].self, from: data),
           let match = evidence.first(where: { $0.matches(action) }) {
            return ActionReview(state: .verified, reason: match.reason, verifiedAt: match.verifiedAt)
        }
        if action.variant == "browser" {
            if action.selector?.isEmpty != false || action.urlIncludes?.isEmpty != false {
                return ActionReview(state: .needsRecapture, reason: "Browser capture needs a selector and site scope")
            }
        } else if action.axRole?.isEmpty != false
                    || [action.axIdentifier, action.axTitle, action.axDescription].allSatisfy({ $0?.isEmpty != false })
                    || (action.axDescription == "UI_HotText" && action.axIdentifier?.isEmpty != false) {
            return ActionReview(state: .needsRecapture, reason: "Control identity is missing or generic; review and recapture")
        }
        return ActionReview(state: .unverified, reason: "Saved capture; replay has not been verified in this recovery")
    }

    private struct MigrationEvidence: Decodable {
        var id: String
        var bundleID: String
        var role: String
        var description: String
        var hotkey: ElementAction.Hotkey
        var verifiedAt: String
        var reason: String

        func matches(_ action: ElementAction) -> Bool {
            action.id == id && action.appBundleID == bundleID && action.axRole == role
                && action.axDescription == description && action.hotkey.key.lowercased() == hotkey.key
                && action.hotkey.modifiers.sorted() == hotkey.modifiers.sorted()
        }
    }

    private static func flagDuplicates(_ registry: inout ActionRegistry) {
        for index in registry.apps.indices {
            let groups = Dictionary(grouping: registry.apps[index].actions.indices.filter { registry.apps[index].actions[$0].runnable }) { actionIndex in
                let key = registry.apps[index].actions[actionIndex].payload!.hotkey
                return key.modifiers.sorted().joined(separator: "+") + "::" + key.key.lowercased()
            }
            for group in groups.values where group.count > 1 {
                let verified = group.filter { registry.apps[index].actions[$0].review.state == .verified }
                for actionIndex in group where verified.count != 1 || actionIndex != verified[0] {
                    registry.apps[index].actions[actionIndex].review = ActionReview(state: .blocked, reason: "Duplicate shortcut in this app; review before enabling")
                }
            }
        }
    }

    func load() throws -> ActionRegistry {
        let registry = try JSONDecoder().decode(ActionRegistry.self, from: Data(contentsOf: url))
        try validate(registry)
        return registry
    }

    private func validate(_ registry: ActionRegistry) throws {
        guard registry.schemaVersion == 1 else { throw RegistryError("Unsupported XSpoon registry version") }
        for rule in registry.disabledLegacyShortcuts ?? [] {
            guard !rule.id.isEmpty, !rule.appBundleID.isEmpty, !rule.key.isEmpty,
                  Set(rule.modifiers).count == rule.modifiers.count,
                  rule.modifiers.allSatisfy({ ["ctrl", "alt", "cmd", "shift", "fn"].contains($0) }) else {
                throw RegistryError("Invalid deleted legacy shortcut rule")
            }
        }
        guard Set(registry.apps.map(\.bundleIdentifier)).count == registry.apps.count,
              Set(registry.apps.map(\.id)).count == registry.apps.count else {
            throw RegistryError("Duplicate app parents in XSpoon registry")
        }
        for app in registry.apps {
            guard Set(app.actions.map(\.id)).count == app.actions.count else { throw RegistryError("Duplicate action IDs in \(app.name)") }
            for action in app.actions {
                guard !action.id.isEmpty, (action.payload == nil) != (action.legacyShortcut == nil) else {
                    throw RegistryError("Invalid action in \(app.name)")
                }
                if let payload = action.payload, (payload.appBundleID ?? "") != app.bundleIdentifier {
                    throw RegistryError("Action target does not match its parent app")
                }
                guard action.payload == nil
                    ? (action.origin == "legacyCommand" && action.review.state == .inherited)
                    : (action.origin == "capture" && action.review.state != .inherited) else {
                    throw RegistryError("Action origin and review state disagree")
                }
            }
        }
    }
}

struct RegistryError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
