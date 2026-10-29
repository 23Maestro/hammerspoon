import XCTest
@testable import XSpoonMenu

final class RegistryMigrationTests: XCTestCase {
    func testRemovingAnAppDisablesItsLegacyRoutesAndRemovesItsCapturedActions() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let app = MyAppDefinition(id: "chat", name: "Chat", bundleIdentifier: "test.chat", icon: "app", shortcuts: [
            AppShortcut(id: "search", action: "Search", key: "S", modifierID: "right-command"),
            AppShortcut(id: "copy", action: "Copy", key: "C", modifierID: "right-command")
        ])
        let other = MyAppDefinition(id: "other", name: "Other", bundleIdentifier: "test.other", icon: "app")
        let client = HammerspoonClient(home: home)
        _ = try client.loadRegistry(legacyApps: [app, other])
        try client.saveElementAction(app: app, shortcut: AppShortcut(id: "dictate", action: "Dictate", key: "D", modifierID: "right-command"),
            snapshot: ElementSnapshot(bundleID: app.bundleIdentifier, role: "AXButton", axDescription: "Dictate", actions: ["AXPress"]))
        try client.deleteElementActions(for: app)
        let registry = try HammerspoonClient(home: home).loadRegistry()
        XCTAssertEqual(registry.apps.map(\.id), ["other"])
        XCTAssertTrue(registry.capturedActions.isEmpty)
        XCTAssertEqual(Set(registry.disabledLegacyShortcuts?.map(\.key) ?? []), ["s", "c"])
        XCTAssertTrue(registry.disabledLegacyShortcuts?.allSatisfy { $0.appBundleID == app.bundleIdentifier } == true)
    }

    func testDeletingLegacyShortcutRemovesRowAndPersistsOnlyItsAppScopedDisableRule() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let legacy = AppShortcut(id: "search", action: "Search", key: "S", modifierID: "right-command")
        let app = MyAppDefinition(id: "chat", name: "Chat", bundleIdentifier: "test.chat", icon: "app", shortcuts: [legacy])
        let other = MyAppDefinition(id: "other", name: "Other", bundleIdentifier: "test.other", icon: "app",
            shortcuts: [AppShortcut(id: "other-search", action: "Search", key: "S", modifierID: "right-command")])
        let client = HammerspoonClient(home: home)
        _ = try client.loadRegistry(legacyApps: [app, other])
        try client.deleteElementAction(id: legacy.id)
        let relaunched = try HammerspoonClient(home: home).loadRegistry()
        XCTAssertTrue(relaunched.apps.first(where: { $0.id == app.id })!.actions.isEmpty)
        XCTAssertEqual(relaunched.apps.first(where: { $0.id == other.id })?.actions.first?.id, "other-search")
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(relaunched)) as! [String: Any]
        let rules = try XCTUnwrap(encoded["disabledLegacyShortcuts"] as? [[String: Any]])
        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(rules[0]["appBundleID"] as? String, "test.chat")
        XCTAssertEqual(rules[0]["key"] as? String, "s")
        XCTAssertEqual(rules[0]["modifiers"] as? [String], ["alt", "ctrl"])
    }

    @MainActor
    func testUIReadsSavedActionsAndDeletionDoesNotReimportLegacyCatalog() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let suite = "RegistryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let app = MyAppDefinition(id: "fixture", name: "Fixture", bundleIdentifier: "test.fixture", icon: "app")
        try defaults.set(JSONEncoder().encode([app]), forKey: "XSpoon.myApps")
        let client = HammerspoonClient(home: home, transport: { _ in .success("{\"status\":\"saved-shortcuts-ready\",\"registeredActionIDs\":[\"new-save\"]}") })
        let store = InspectorStore(hammerspoon: client, legacyDefaults: defaults)
        let shortcut = AppShortcut(id: "new-save", action: "Submit", key: "S", modifierID: "right-shift")
        let snapshot = ElementSnapshot(bundleID: app.bundleIdentifier, role: "AXButton", axDescription: "Submit", actions: ["AXPress"])
        XCTAssertTrue(store.saveElementShortcut(shortcut, forAppID: app.id, snapshot: snapshot))
        XCTAssertEqual(store.myApps.first?.shortcuts.first?.id, "new-save")
        XCTAssertEqual(store.myApps.first?.shortcuts.first?.reviewState, "unverified")
        let registryApp = try XCTUnwrap(client.loadRegistry().apps.first)
        XCTAssertEqual(registryApp.definition, store.myApps.first)

        // A stale legacy catalog cannot bring a deleted canonical action back.
        var staleApp = app
        staleApp.shortcuts = [shortcut]
        let staleData = try JSONEncoder().encode([staleApp])
        defaults.set(staleData, forKey: "XSpoon.myApps")
        store.deleteShortcut(shortcut, from: app)
        XCTAssertTrue(try client.readElementActions().isEmpty)
        let relaunched = InspectorStore(hammerspoon: client, legacyDefaults: defaults)
        XCTAssertTrue(relaunched.myApps.first!.shortcuts.isEmpty)
        XCTAssertEqual(defaults.data(forKey: "XSpoon.myApps"), staleData)
        defaults.set(Data("not-json".utf8), forKey: "XSpoon.myApps")
        let ignoresLegacy = InspectorStore(hammerspoon: client, legacyDefaults: defaults)
        XCTAssertEqual(ignoresLegacy.myApps.first?.id, "fixture")
    }

    func testCorruptCanonicalDataIsNotOverwrittenOrReplacedByLegacyData() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let directory = home.appendingPathComponent(".hammerspoon")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let raw = Data("not-json".utf8)
        let canonical = directory.appendingPathComponent("xspoon_registry.json")
        try raw.write(to: canonical)
        try Data("[]".utf8).write(to: directory.appendingPathComponent("browser_element_actions.json"))
        let client = HammerspoonClient(home: home)
        XCTAssertThrowsError(try client.readElementActions())
        XCTAssertThrowsError(try client.loadRegistry())
        XCTAssertEqual(try Data(contentsOf: canonical), raw)
    }

    func testNewSaveWritesCanonicalRecordWithoutRewritingLegacyFile() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let directory = home.appendingPathComponent(".hammerspoon")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let legacy = directory.appendingPathComponent("browser_element_actions.json")
        try Data("[]".utf8).write(to: legacy)
        let app = MyAppDefinition(id: "fixture", name: "Fixture", bundleIdentifier: "test.fixture", icon: "app")
        let shortcut = AppShortcut(id: "saved-once", action: "Submit", key: "S", modifierID: "right-shift")
        let snapshot = ElementSnapshot(bundleID: app.bundleIdentifier, role: "AXButton", axDescription: "Submit", actions: ["AXPress"])
        let client = HammerspoonClient(home: home)
        try client.saveElementAction(app: app, shortcut: shortcut, snapshot: snapshot)
        let store = ActionRegistryStore(directory: directory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url.path))
        XCTAssertEqual(try Data(contentsOf: legacy), Data("[]".utf8))
        XCTAssertEqual(try store.load().apps.first?.actions.first?.shortcut.id, "saved-once")
        XCTAssertEqual(try HammerspoonClient(home: home).readElementActions().map(\.id), ["saved-once"])
    }

    func testMigrationPreservesWorkingActionAndFlagsOldAttempts() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let directory = home.appendingPathComponent(".hammerspoon")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let shortcut = AppShortcut(id: "system-settings-492E530A-4951-4AA7-B2D0-FDEFAF62E860", action: "Click Keyboard Shortcuts…", key: "S", modifierID: "right-shift")
        let settings = MyAppDefinition(id: "system-settings", name: "System Settings", bundleIdentifier: "com.apple.systempreferences", icon: "gearshape", shortcuts: [shortcut])
        let working = ElementAction(app: settings, shortcut: shortcut, snapshot: ElementSnapshot(bundleID: settings.bundleIdentifier, role: "AXButton", axDescription: "Keyboard Shortcuts…", actions: ["AXPress"]))
        let premiere = MyAppDefinition(id: "premiere", name: "Premiere Pro", bundleIdentifier: "com.adobe.PremierePro.26", icon: "film")
        let conflict = ElementAction(app: premiere, shortcut: AppShortcut(id: "old-y", action: "Y Value", key: "E", modifierID: "right-command"), snapshot: ElementSnapshot(bundleID: premiere.bundleIdentifier, role: "AXTextField", axDescription: "UI_HotText"))
        let finder = MyAppDefinition(id: "finder", name: "Finder", bundleIdentifier: "com.apple.finder", icon: "folder", shortcuts: [AppShortcut(id: "legacy-context", action: "Open Context Menu", key: "M", modifierID: "right-command")])
        let original = try JSONEncoder().encode([working, conflict])
        let oldFile = directory.appendingPathComponent("browser_element_actions.json")
        try original.write(to: oldFile)
        let store = ActionRegistryStore(directory: directory)
        let imported = try store.loadOrMigrate(legacyApps: [settings, premiere, finder])
        XCTAssertEqual(imported.apps.count, 3)
        let saved = try XCTUnwrap(imported.apps.first(where: { $0.id == settings.id })?.actions.first)
        XCTAssertEqual(saved.payload, working)
        XCTAssertEqual(saved.review.state, .verified)
        XCTAssertEqual(imported.apps.first(where: { $0.id == premiere.id })?.actions.first?.review.state, .needsRecapture)
        XCTAssertEqual(imported.apps.first(where: { $0.id == finder.id })?.actions.first?.origin, "legacyCommand")
        XCTAssertEqual(try Data(contentsOf: oldFile), original)
        XCTAssertNotNil(imported.migrationBackup)
        XCTAssertEqual(try store.load(), imported)
    }

    func testCanonicalRegistryTakesPrecedenceOverLegacyActions() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let directory = home.appendingPathComponent(".hammerspoon")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let app = MyAppDefinition(id: "fixture", name: "Fixture", bundleIdentifier: "test.fixture", icon: "app")
        let snapshot = ElementSnapshot(bundleID: "test.fixture", role: "AXButton", axDescription: "Submit", actions: ["AXPress"])
        let legacy = ElementAction(app: app, shortcut: AppShortcut(id: "obsolete-file", action: "Old", key: "A", modifierID: "right-shift"), snapshot: snapshot)
        let canonical = ElementAction(app: app, shortcut: AppShortcut(id: "canonical-action", action: "Submit", key: "B", modifierID: "right-shift"), snapshot: snapshot)
        try JSONEncoder().encode([legacy]).write(to: directory.appendingPathComponent("browser_element_actions.json"))
        let payload = try JSONSerialization.jsonObject(with: JSONEncoder().encode(canonical))
        let registry: [String: Any] = ["schemaVersion": 1, "apps": [[
            "id": "fixture", "name": "Fixture", "bundleIdentifier": "test.fixture", "icon": "app", "actions": [[
                "payload": payload, "modifierID": "right-shift", "origin": "capture",
                "review": ["state": "unverified", "reason": "Imported capture"]
            ]]
        ]]]
        try JSONSerialization.data(withJSONObject: registry).write(to: directory.appendingPathComponent("xspoon_registry.json"))
        XCTAssertEqual(try HammerspoonClient(home: home).readElementActions().map(\.id), ["canonical-action"])
    }
}
