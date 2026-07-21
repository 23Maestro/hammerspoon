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
    var kind: String?
    var captureMethod: String?
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
}

struct PendingElementCapture: Identifiable, Equatable {
    let id = UUID()
    var snapshot: ElementSnapshot
    var appID: String
    var kind: AdapterKind
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

    static let all: [ModifierPreset] = [
        ModifierPreset(id: "right-command", label: "Right Command", badge: "R CMD", color: "red", hammerspoonModifiers: ["ctrl", "alt"]),
        ModifierPreset(id: "right-shift", label: "Right Shift", badge: "R SHFT", color: "blue", hammerspoonModifiers: ["alt", "cmd"]),
        ModifierPreset(id: "tilde", label: "Tilde", badge: "TILDE", color: "orange", hammerspoonModifiers: ["ctrl", "alt", "cmd"]),
        ModifierPreset(id: "right-command-right-control", label: "Right Command", badge: "R CMD/R CTRL", color: "purple", hammerspoonModifiers: ["ctrl", "cmd"]),
        ModifierPreset(id: "right-bracket", label: "Right Bracket", badge: "R BRKT", color: "green", hammerspoonModifiers: ["alt", "shift", "cmd"]),
        ModifierPreset(id: "left-bracket", label: "Left Bracket", badge: "L BRKT", color: "pink", hammerspoonModifiers: ["alt", "shift", "ctrl"]),
        ModifierPreset(id: "right-control-option", label: "Right Control / Option", badge: "R CTRL/OPT", color: "cyan", hammerspoonModifiers: ["ctrl", "cmd"])
    ]

    static func preset(_ id: String) -> ModifierPreset {
        if id == singleKey.id { return singleKey }
        return all.first(where: { $0.id == id }) ?? all[0]
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
