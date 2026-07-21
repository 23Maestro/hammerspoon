import Foundation

protocol ShortcutActionAdapter {
    var kind: AdapterKind { get }
    func detects(label: String) -> Bool
    func fields(for snapshot: ElementSnapshot) -> [String]
}

struct ButtonAdapter: ShortcutActionAdapter {
    let kind: AdapterKind = .button

    func detects(label: String) -> Bool {
        label.localizedCaseInsensitiveContains("button")
    }

    func fields(for snapshot: ElementSnapshot) -> [String] {
        ["The button you captured", "The app it belongs to"]
    }
}

struct MenuOptionAdapter: ShortcutActionAdapter {
    let kind: AdapterKind = .menuOption

    func detects(label: String) -> Bool {
        label.localizedCaseInsensitiveContains("menu")
    }

    func fields(for snapshot: ElementSnapshot) -> [String] {
        ["What opens the menu", "The menu option to click", "A short wait between them"]
    }
}

struct TextFieldAdapter: ShortcutActionAdapter {
    let kind: AdapterKind = .textField

    func detects(label: String) -> Bool {
        label.localizedCaseInsensitiveContains("text")
    }

    func fields(for snapshot: ElementSnapshot) -> [String] {
        ["The text field you captured", "The app it belongs to"]
    }
}

enum AdapterCatalog {
    static func all() -> [any ShortcutActionAdapter] {
        [ButtonAdapter(), MenuOptionAdapter(), TextFieldAdapter()]
    }
}
