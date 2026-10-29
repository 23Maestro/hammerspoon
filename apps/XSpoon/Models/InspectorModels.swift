import Foundation

enum CaptureSource: String, CaseIterable, Identifiable {
    case accessibility = "App control"
    case dom = "Web page"
    case webView = "Selected item"

    var id: String { rawValue }

    var explanation: String {
        switch self {
        case .accessibility: "XSpoon can see the controls shared with macOS."
        case .dom: "XSpoon can see the controls inside the web page."
        case .webView: "XSpoon can see the selected item before opening its menu."
        }
    }
}

struct AppContext: Equatable {
    var appName: String = "Unknown App"
    var bundleIdentifier: String = ""
    var windowTitle: String = ""
    var source: CaptureSource = .accessibility
}

struct ElementSnapshot: Codable, Equatable {
    var captureID: String?
    var capturedAt: String?
    var kind: String?
    var captureMethod: String?
    var surface: String?
    var captureButton: String?
    var replayIntent: String?
    var selector: String?
    var url: String?
    var title: String?
    var text: String?
    var tag: String?
    var id: String?
    var className: String?
    var appName: String?
    var appPath: String?
    var bundleID: String?
    var windowTitle: String?
    var role: String?
    var subrole: String?
    var axTitle: String?
    var axValue: String?
    var axDescription: String?
    var axPlaceholder: String?
    var axHelp: String?
    var axIdentifier: String?
    var actions: [String]?
    var frame: SnapshotRect?
    var windowFrame: SnapshotRect?

    var displayTitle: String {
        let candidates: [String?] = [axTitle, text, axValue, title, axDescription, axPlaceholder, axHelp]
        return candidates.compactMap { value -> String? in
            guard let value else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }.first ?? "Captured element"
    }

    var appDisplayName: String {
        appName?.isEmpty == false ? appName! : "Unknown App"
    }

    var appBundleIdentifier: String {
        bundleID?.isEmpty == false ? bundleID! : ""
    }

    var captureSource: CaptureSource {
        if kind == "hammerspoon-browser-element" || selector?.isEmpty == false {
            return .dom
        }
        return .accessibility
    }

    var effectiveSurface: String {
        if let surface, !surface.isEmpty {
            return surface
        }
        if kind == "hammerspoon-browser-element" || selector?.isEmpty == false {
            return "website"
        }
        switch bundleID {
        case "com.openai.codex", "tw.ogdesign.eagle", "com.eagle.cool", "notion.id", "com.canva.CanvaDesktop":
            return "webApp"
        case "com.google.Chrome":
            return "website"
        default:
            return "osApp"
        }
    }

    var effectiveCaptureButton: String {
        captureButton?.isEmpty == false ? captureButton! : "left"
    }

    var effectiveReplayIntent: String {
        if let replayIntent, !replayIntent.isEmpty {
            return replayIntent
        }
        if effectiveCaptureButton == "right" {
            return "openContextMenu"
        }
        if AdapterKind.detect(self) == .textField {
            return "focus"
        }
        if effectiveSurface == "website" {
            return AdapterKind.detect(self) == .textField ? "focus" : "domClick"
        }
        if effectiveSurface == "webApp", AdapterKind.detect(self) == .button {
            return "physicalClick"
        }
        if actions?.contains("AXPress") == true {
            return "press"
        }
        return "unresolved"
    }

    var xRole: String {
        let value = role ?? tag ?? "Element"
        let names = [
            "AXButton": "XButton",
            "AXMenu": "XMenu",
            "AXMenuItem": "XMenuOption",
            "AXPopUpButton": "XPopupMenu",
            "AXTextField": "XTextField",
            "AXTextArea": "XTextField",
            "AXCheckBox": "XCheckbox",
            "AXRadioButton": "XChoice",
            "AXLink": "XLink",
            "AXStaticText": "XText",
            "AXImage": "XImage",
            "AXRow": "XRow",
            "AXCell": "XCell",
            "AXGroup": "XArea",
            "AXScrollArea": "XScrollArea",
            "AXWindow": "XWindow"
        ]
        if let name = names[value] { return name }
        if value.hasPrefix("AX") { return "X" + value.dropFirst(2) }
        if value.hasPrefix("X") { return value }
        return "X" + value.prefix(1).uppercased() + value.dropFirst()
    }

    var xActions: [String] {
        let names = [
            "AXPress": "Click",
            "AXShowMenu": "Open menu",
            "AXConfirm": "Confirm",
            "AXCancel": "Cancel",
            "AXIncrement": "Increase",
            "AXDecrement": "Decrease",
            "AXRaise": "Bring forward",
            "AXShowDefaultUI": "Show default"
        ]
        return (actions ?? []).map { action in
            if let name = names[action] { return name }
            if action.hasPrefix("AX") { return String(action.dropFirst(2)) }
            return action
        }
    }
}

struct SnapshotRect: Codable, Equatable {
    var x: Double
    var y: Double
    var w: Double
    var h: Double
}

struct MenuItemSnapshot: Codable, Identifiable {
    var id: String { title }
    let role: String
    let title: String
    let value: String?
    let description: String?
    let enabled: Bool
}

struct ShortcutAction: Identifiable, Equatable {
    let id: String
    let name: String
    let source: CaptureSource
    let status: String
}

struct MyAppDefinition: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var bundleIdentifier: String
    var icon: String
    var shortcuts: [AppShortcut] = []
}

struct AppShortcut: Identifiable, Codable, Equatable {
    var id: String
    var action: String
    var key: String
    var modifierID: String
    var reviewState: String?
    var reviewReason: String?
    var origin: String?
}

struct PendingElementCapture: Identifiable, Equatable {
    let id = UUID()
    var snapshot: ElementSnapshot
    var appID: String
    var kind: AdapterKind
    var selectedMenuItem: String?
}

struct ModifierPreset: Identifiable, Hashable {
    let id: String
    let label: String
    let badge: String
    let color: String
    let hammerspoonModifiers: [String]
}

enum ModifierCatalog {
    static let singleKey = ModifierPreset(id: "single-key", label: "Single key", badge: "KEY", color: "gray", hammerspoonModifiers: [])

    private struct LedgerEntry: Decodable {
        var id: String
        var label: String
        var hammerspoonModifiers: [String]
        var physicalInput: PhysicalInput
        struct PhysicalInput: Decodable { var modifiers: InputModifiers? }
        struct InputModifiers: Decodable { var mandatory: [String]? }
    }

    static let all: [ModifierPreset] = {
        guard let url = Bundle.module.url(forResource: "ModifierLedger", withExtension: "jsonl"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        let presentation: [String: (String, String, String)] = [
            "right_command": ("right-command", "R CMD", "red"),
            "right_shift": ("right-shift", "R SHFT", "blue"),
            "right_option": ("right-option", "R OPT", "cyan"),
            "grave_accent_and_tilde": ("tilde", "TILDE", "orange"),
            "close_bracket": ("right-bracket", "R BRKT", "green"),
            "open_bracket": ("left-bracket", "L BRKT", "pink"),
            "caps_lock": ("hyper", "HYPER", "purple"),
            "tab": ("tab", "TAB", "blue"),
            "backslash": ("backslash", "BACKSLASH", "orange"),
            "left_control": ("left-control", "L CTRL", "cyan")
        ]
        return text.split(separator: "\n").compactMap { line in
            guard let entry = try? decoder.decode(LedgerEntry.self, from: Data(line.utf8)),
                  entry.physicalInput.modifiers?.mandatory?.isEmpty != false,
                  let (id, badge, color) = presentation[entry.id] else { return nil }
            return ModifierPreset(id: id, label: entry.label, badge: badge, color: color, hammerspoonModifiers: entry.hammerspoonModifiers)
        }.sorted { lhs, rhs in
            let order = ["right-command", "right-shift", "tab", "tilde", "right-bracket", "left-bracket", "right-option", "hyper", "backslash", "left-control"]
            return (order.firstIndex(of: lhs.id) ?? 99) < (order.firstIndex(of: rhs.id) ?? 99)
        }
    }()

    static func preset(_ id: String) -> ModifierPreset {
        if id == singleKey.id { return singleKey }
        let resolvedID = id == "right-control-option" ? "right-option" : id
        return all.first(where: { $0.id == resolvedID })
            ?? ModifierPreset(id: id, label: "Unknown modifier", badge: "?", color: "gray", hammerspoonModifiers: [])
    }
}

enum MyAppsCatalog {
    static let all: [MyAppDefinition] = [
        MyAppDefinition(id: "eagle", name: "Eagle", bundleIdentifier: "tw.ogdesign.eagle", icon: "photo.on.rectangle", shortcuts: [
            AppShortcut(id: "eagle-context", action: "Open Context Menu", key: "M", modifierID: "right-command")
        ]),
        MyAppDefinition(id: "finder", name: "Finder", bundleIdentifier: "com.apple.finder", icon: "folder", shortcuts: [
            AppShortcut(id: "finder-context", action: "Open Context Menu", key: "M", modifierID: "right-command")
        ]),
        MyAppDefinition(id: "notion", name: "Notion", bundleIdentifier: "notion.id", icon: "note.text", shortcuts: [
            AppShortcut(id: "notion-shortcut-s", action: "Toggle Script", key: "S", modifierID: "right-command"),
            AppShortcut(id: "notion-voicemail", action: "Toggle Voice Mail", key: "V", modifierID: "right-command")
        ]),
        MyAppDefinition(id: "canva", name: "Canva", bundleIdentifier: "com.canva.CanvaDesktop", icon: "square.on.square", shortcuts: [
            AppShortcut(id: "canva-context", action: "Open Context Menu", key: "M", modifierID: "right-command")
        ]),
        MyAppDefinition(id: "chrome", name: "Chrome", bundleIdentifier: "com.google.Chrome", icon: "globe", shortcuts: [
            AppShortcut(id: "chrome-shortcut-s", action: "Click Save", key: "S", modifierID: "right-command")
        ]),
        MyAppDefinition(id: "obsidian", name: "Obsidian", bundleIdentifier: "md.obsidian", icon: "diamond"),
        MyAppDefinition(id: "chatgpt", name: "ChatGPT", bundleIdentifier: "com.openai.codex", icon: "bubble.left.and.bubble.right", shortcuts: [
            AppShortcut(id: "chatgpt-shortcut-s", action: "Focus Shortcut Search", key: "S", modifierID: "single-key")
        ]),
        MyAppDefinition(id: "system-settings", name: "System Settings", bundleIdentifier: "com.apple.systempreferences", icon: "gearshape"),
        MyAppDefinition(id: "keyboard-maestro", name: "Keyboard Maestro", bundleIdentifier: "com.stairways.keyboardmaestro.editor", icon: "keyboard", shortcuts: [
            AppShortcut(id: "keyboard-maestro-copy", action: "Copy Shell Script Line", key: "C", modifierID: "right-command"),
            AppShortcut(id: "keyboard-maestro-shortcut-s", action: "Copy Shell Script Line", key: "S", modifierID: "right-command")
        ]),
        MyAppDefinition(id: "premiere-pro", name: "Premiere Pro", bundleIdentifier: "com.adobe.PremierePro.26", icon: "film")
    ]
}

enum AdapterKind: String, CaseIterable, Identifiable {
    case button = "Button"
    case menuOption = "Menu option"
    case textField = "Text field"

    var id: String { rawValue }

    static func detect(_ snapshot: ElementSnapshot) -> AdapterKind? {
        switch snapshot.role {
        case "AXMenuItem":
            return .menuOption
        case "AXTextField", "AXTextArea", "AXSearchField":
            return .textField
        case "AXButton", "AXPopUpButton":
            return .button
        default:
            break
        }

        switch snapshot.tag?.lowercased() {
        case "textarea":
            return .textField
        case "input":
            return .textField
        case "button":
            return .button
        default:
            return nil
        }
    }
}
