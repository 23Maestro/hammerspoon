import Foundation

protocol ShortcutActionAdapter {
    var kind: AdapterKind { get }
    func detects(label: String) -> Bool
    func fields(for snapshot: ElementSnapshot) -> [String]
}

struct SetVariableAdapter: ShortcutActionAdapter {
    let kind: AdapterKind = .setVariable

    func detects(label: String) -> Bool {
        label.localizedCaseInsensitiveContains("Set variable")
    }

    func fields(for snapshot: ElementSnapshot) -> [String] {
        ["Editable variable field", "Input token after ‘to’", "Current value", "Variable validation"]
    }
}

struct ChooseFromMenuAdapter: ShortcutActionAdapter {
    let kind: AdapterKind = .chooseFromMenu

    func detects(label: String) -> Bool {
        label.localizedCaseInsensitiveContains("Choose from menu with")
    }

    func fields(for snapshot: ElementSnapshot) -> [String] {
        ["Prompt", "Menu items", "Edit item text", "Add or remove item"]
    }
}

struct AskForInputAdapter: ShortcutActionAdapter {
    let kind: AdapterKind = .askForInput

    func detects(label: String) -> Bool {
        label.localizedCaseInsensitiveContains("Ask for")
    }

    func fields(for snapshot: ElementSnapshot) -> [String] {
        ["Input type", "Prompt", "Editable prompt"]
    }
}

enum AdapterCatalog {
    static func all() -> [any ShortcutActionAdapter] {
        [SetVariableAdapter(), ChooseFromMenuAdapter(), AskForInputAdapter()]
    }
}
