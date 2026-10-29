import XCTest
@testable import XSpoonMenu

final class CaptureLoopTests: XCTestCase {
    func testAppScopedDictateChordRejectsAConflictButCanBeReusedInAnotherApp() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let client = HammerspoonClient(home: home)
        let app = MyAppDefinition(id: "chat", name: "Chat", bundleIdentifier: "test.chat", icon: "app")
        let snapshot = ElementSnapshot(bundleID: app.bundleIdentifier, role: "AXButton", axTitle: "Dictate", axDescription: "Dictate", actions: ["AXPress"])
        let shortcut = AppShortcut(id: "dictate", action: "Dictate", key: "D", modifierID: "right-command")
        let original = try client.saveElementAction(app: app, shortcut: shortcut, snapshot: snapshot)
        var differentControl = snapshot
        differentControl.axTitle = "Different control"
        differentControl.axDescription = "Different control"
        XCTAssertThrowsError(try client.saveElementAction(app: app,
            shortcut: AppShortcut(id: "conflict", action: "Different control", key: "D", modifierID: "right-command"), snapshot: differentControl))
        XCTAssertEqual(try HammerspoonClient(home: home).readElementActions(), [original])
        let otherApp = MyAppDefinition(id: "other", name: "Other", bundleIdentifier: "test.other", icon: "app")
        var otherSnapshot = snapshot
        otherSnapshot.bundleID = otherApp.bundleIdentifier
        let reused = try client.saveElementAction(app: otherApp,
            shortcut: AppShortcut(id: "other-dictate", action: "Dictate", key: "D", modifierID: "right-command"), snapshot: otherSnapshot)
        XCTAssertEqual(reused.hotkey, original.hotkey)
        let relaunched = HammerspoonClient(home: home)
        XCTAssertEqual(try relaunched.readElementActions().count, 2)
        XCTAssertEqual(try relaunched.loadRegistry().apps.first?.actions.first?.payload, original)
    }

    @MainActor
    func testRegistrationFailurePreservesItsErrorAndSavedRecordForRetry() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let suite = "XSpoonTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let app = MyAppDefinition(id: "fixture", name: "Fixture", bundleIdentifier: "test.fixture", icon: "app")
        defaults.set(try JSONEncoder().encode([app]), forKey: "XSpoon.myApps")
        let client = HammerspoonClient(home: home, transport: { _ in
            .success("{\"status\":\"error\",\"message\":\"Fixture runtime registration rejected\"}")
        })
        let store = InspectorStore(hammerspoon: client, legacyDefaults: defaults)
        let snapshot = ElementSnapshot(bundleID: app.bundleIdentifier, role: "AXButton", axDescription: "Export", actions: ["AXPress"])
        XCTAssertFalse(store.saveElementShortcut(AppShortcut(id: "retry", action: "Export", key: "E", modifierID: "right-command"), forAppID: app.id, snapshot: snapshot))
        XCTAssertTrue(store.status.contains("Fixture runtime registration rejected"), store.status)
        XCTAssertEqual(try client.readElementActions().map(\.id), ["retry"])
    }

    func testRightCommandECanBeSavedForAnAppControl() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".hammerspoon"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let app = MyAppDefinition(id: "fixture", name: "Fixture", bundleIdentifier: "test.fixture", icon: "app")
        let snapshot = ElementSnapshot(bundleID: app.bundleIdentifier, role: "AXButton", axDescription: "Export", actions: ["AXPress"])
        let client = HammerspoonClient(home: home)
        let saved = try client.saveElementAction(app: app,
            shortcut: AppShortcut(id: "export", action: "Export", key: "E", modifierID: "right-command"), snapshot: snapshot)
        XCTAssertEqual(saved.hotkey.modifiers.sorted(), ["alt", "ctrl"])
        XCTAssertEqual(try client.readElementActions().map(\.id), [saved.id])
    }

    func testRecapturingSameControlUpdatesItsEvidenceWithoutDuplicateShortcut() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".hammerspoon"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let client = HammerspoonClient(home: home)
        let app = MyAppDefinition(id: "settings", name: "System Settings", bundleIdentifier: "com.apple.systempreferences", icon: "gearshape")
        var capture = ElementSnapshot(bundleID: app.bundleIdentifier, role: "AXButton", axDescription: "Keyboard Shortcuts…", actions: ["AXPress"], frame: SnapshotRect(x: 10, y: 20, w: 100, h: 25))
        try client.saveElementAction(app: app, shortcut: AppShortcut(id: "first", action: "Keyboard Shortcuts", key: "S", modifierID: "right-shift"), snapshot: capture)
        capture.frame = SnapshotRect(x: 110, y: 120, w: 100, h: 25)
        try client.saveElementAction(app: app, shortcut: AppShortcut(id: "recapture", action: "Keyboard Shortcuts", key: "S", modifierID: "right-shift"), snapshot: capture)
        let saved = try HammerspoonClient(home: home).readElementActions()
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.id, "first")
        XCTAssertEqual(saved.first?.frame?.x, 110)
    }

    @MainActor
    func testFailedCaptureCannotReuseAnOlderLiveTarget() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let suite = "XSpoonTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let client = HammerspoonClient(home: home, transport: { _ in .failure(NSError(domain: "probe", code: 1)) })
        let store = InspectorStore(hammerspoon: client, legacyDefaults: defaults)
        store.liveSnapshot = ElementSnapshot(captureID: "old-capture", bundleID: "com.apple.systempreferences", role: "AXButton", axDescription: "Keyboard Shortcuts…", actions: ["AXPress"])
        XCTAssertNil(store.createElementFromCurrentTarget())
        XCTAssertNil(store.pendingCapture)
    }

    func testCaptureReportsRuntimeErrorEvenWhenAppleScriptExitsSuccessfully() {
        let client = HammerspoonClient(transport: { _ in .success("{\"status\":\"error\",\"message\":\"No control under the pointer\"}") })
        switch client.captureCurrentTarget() {
        case .success: XCTFail("A runtime error must not be reported as capture success")
        case .failure(let error): XCTAssertTrue(error.localizedDescription.contains("No control under the pointer"))
        }
    }

    func testCaptureCannotBeAssignedToADifferentApp() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".hammerspoon"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let app = MyAppDefinition(id: "finder", name: "Finder", bundleIdentifier: "com.apple.finder", icon: "folder")
        let capture = ElementSnapshot(bundleID: "com.apple.systempreferences", role: "AXButton", axDescription: "Keyboard Shortcuts…", actions: ["AXPress"])
        let shortcut = AppShortcut(id: "wrong-app", action: "Keyboard Shortcuts", key: "S", modifierID: "right-shift")
        XCTAssertThrowsError(try HammerspoonClient(home: home).saveElementAction(app: app, shortcut: shortcut, snapshot: capture))
    }

    func testTabPresetUsesTheCanonicalHoldModifier() {
        XCTAssertEqual(ModifierCatalog.preset("tab").label, "Tab")
        XCTAssertEqual(ModifierCatalog.preset("tab").hammerspoonModifiers, ["ctrl"])
    }

    func testMenuChordCannotBeSavedOverGlobalMenuShortcut() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".hammerspoon"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let app = MyAppDefinition(id: "settings", name: "System Settings", bundleIdentifier: "com.apple.systempreferences", icon: "gearshape")
        let capture = ElementSnapshot(bundleID: app.bundleIdentifier, role: "AXButton", axDescription: "Keyboard Shortcuts…", actions: ["AXPress"])
        let shortcut = AppShortcut(id: "reserved", action: "Keyboard Shortcuts", key: "I", modifierID: "right-command")
        XCTAssertThrowsError(try HammerspoonClient(home: home).saveElementAction(app: app, shortcut: shortcut, snapshot: capture))
    }

    func testSavedButtonIsNotLockedToTransientWindowTitle() {
        let app = MyAppDefinition(id: "system-settings", name: "System Settings", bundleIdentifier: "com.apple.systempreferences", icon: "gearshape")
        let shortcut = AppShortcut(id: "keyboard-shortcuts", action: "Keyboard Shortcuts", key: "K", modifierID: "right-shift")
        let snapshot = ElementSnapshot(appName: "System Settings", bundleID: app.bundleIdentifier, windowTitle: "Keyboard", role: "AXButton", axDescription: "Keyboard Shortcuts…", actions: ["AXPress"])
        let action = ElementAction(app: app, shortcut: shortcut, snapshot: snapshot)
        XCTAssertNil(action.windowTitleIncludes)
        XCTAssertEqual(action.appBundleID, "com.apple.systempreferences")
        XCTAssertEqual(action.axDescription, "Keyboard Shortcuts…")
        XCTAssertEqual(action.replayIntent, "press")
        XCTAssertEqual(action.hotkey.modifiers.sorted(), ["alt", "cmd"])
    }
}
