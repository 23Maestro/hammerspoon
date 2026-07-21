import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var store: InspectorStore
    @State private var tab = 0
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $tab) {
                Text("Inspector").tag(0)
                Text("My Apps").tag(1)
                Text("Settings").tag(2)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 18)
            .padding(.top, 14)

            Group {
                switch tab {
                case 1: MyAppsSettingsView(store: store)
                case 2: XSpoonSettingsView()
                default:
                    NavigationSplitView(columnVisibility: $sidebarVisibility) {
                        SidebarView(store: store)
                            .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
                    } detail: {
                        InspectorDetailView(store: store)
                    }
                    .toolbar {
                        ToolbarItemGroup(placement: .primaryAction) {
                            Button {
                                store.toggleInspecting()
                            } label: {
                                Label(store.isInspecting ? "Stop" : "Inspect", systemImage: store.isInspecting ? "stop.circle" : "scope")
                            }
                            .keyboardShortcut("i", modifiers: [.control, .option])
                            .help(store.isInspecting ? "Stop inspecting" : "Inspect")

                        }
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .xspoonToggleInspectorSidebar)) { _ in
            toggleSidebar()
        }
        .sheet(item: $store.pendingCapture) { pending in
            CreateElementSheet(pending: pending, store: store)
                .frame(width: 520, height: 520)
        }
        .task { store.refresh() }
    }

    private func toggleSidebar() {
        sidebarVisibility = sidebarVisibility == .detailOnly ? .all : .detailOnly
    }
}

struct MyAppsSettingsView: View {
    @ObservedObject var store: InspectorStore
    @State private var selectedAppID = MyAppsCatalog.all.first?.id ?? "finder"
    @State private var showingEditor = false
    @State private var shortcutPendingDeletion: AppShortcut?
    @State private var appPendingDeletion: MyAppDefinition?

    private var selectedApp: MyAppDefinition? { store.myApps.first(where: { $0.id == selectedAppID }) }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(store.myApps, selection: $selectedAppID) { app in
                    Label(app.name, systemImage: app.icon).tag(app.id)
                }
                Divider()
                HStack {
                    Button {
                        store.addAppFromCurrentContext()
                        selectedAppID = store.myApps.last?.id ?? selectedAppID
                    } label: {
                        Label("Add Current App", systemImage: "plus")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Spacer()
                    Button {
                        appPendingDeletion = selectedApp
                    } label: {
                        Image(systemName: "minus")
                    }
                    .disabled(selectedApp == nil)
                }
                .buttonStyle(.borderless)
                .padding(10)
            }
            .frame(width: 230)
            Divider()
            ScrollView {
                if let app = selectedApp {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            Label(app.name, systemImage: app.icon).font(.title2.bold())
                            Spacer()
                            Button { store.focus(app) } label: { Label("Focus", systemImage: "scope") }
                        }
                        Text("Shortcuts")
                            .font(.headline)
                        if app.shortcuts.isEmpty {
                            Text("No shortcuts saved for this app.")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 8)
                        } else {
                            ForEach(app.shortcuts) { shortcut in
                                ShortcutCard(shortcut: shortcut) {
                                    shortcutPendingDeletion = shortcut
                                }
                            }
                        }
                        Button { showingEditor = true } label: {
                            Label("Add Shortcut", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(24)
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            ShortcutEditorView(app: selectedApp, store: store)
                .frame(width: 460, height: 430)
        }
        .alert("Delete shortcut?", isPresented: Binding(
            get: { shortcutPendingDeletion != nil },
            set: { if !$0 { shortcutPendingDeletion = nil } }
        ), presenting: shortcutPendingDeletion) { shortcut in
            Button("Delete", role: .destructive) {
                guard let app = selectedApp else { return }
                store.deleteShortcut(shortcut, from: app)
                shortcutPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                shortcutPendingDeletion = nil
            }
        } message: { shortcut in
            Text("Delete “\(shortcut.action)” from \(selectedApp?.name ?? "this app")?")
        }
        .alert("Remove app?", isPresented: Binding(
            get: { appPendingDeletion != nil },
            set: { if !$0 { appPendingDeletion = nil } }
        ), presenting: appPendingDeletion) { app in
            Button("Remove", role: .destructive) {
                store.deleteApp(app)
                selectedAppID = store.myApps.first?.id ?? ""
                appPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                appPendingDeletion = nil
            }
        } message: { app in
            Text("Remove \(app.name) and all of its saved shortcuts?")
        }
    }
}

struct ShortcutCard: View {
    let shortcut: AppShortcut
    let onDelete: () -> Void
    private var modifier: ModifierPreset { ModifierCatalog.preset(shortcut.modifierID) }
    private var shortcutLabel: String {
        modifier.hammerspoonModifiers.isEmpty ? shortcut.key : "+ \(shortcut.key)"
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(modifier.badge)
                .font(.caption.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.accentColor.opacity(0.18), in: Capsule())
            Text(shortcutLabel).font(.headline.monospaced())
            Text(shortcut.action).foregroundStyle(.secondary)
            Spacer()
            Button(action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete shortcut")
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct ShortcutEditorView: View {
    let app: MyAppDefinition?
    @ObservedObject var store: InspectorStore
    @Environment(\.dismiss) private var dismiss
    @State private var action = "Open Context Menu"
    @State private var key = ""
    @State private var modifierID = ModifierCatalog.all[0].id
    @State private var readingKey = false
    @State private var monitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Shortcut").font(.title2.bold())
            Text(app?.name ?? "App").foregroundStyle(.secondary)
            TextField("Action", text: $action)
                .textFieldStyle(.roundedBorder)
            Text("Modifier")
            ScrollView(.horizontal) {
                HStack {
                    ForEach(ModifierCatalog.all) { modifier in
                        Button {
                            modifierID = modifier.id
                        } label: {
                            Text(modifier.badge)
                                .font(.caption.bold())
                                .padding(10)
                                .background(modifierID == modifier.id ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            HStack {
                Text(key.isEmpty ? "Press one key" : "Key: \(key)")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(readingKey ? "Listening..." : "Read Key") { toggleKeyReader() }
            }
            Spacer()
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save") {
                    guard let app else { return }
                    store.updateShortcut(AppShortcut(id: "\(app.id)-\(UUID().uuidString)", action: action, key: key.uppercased(), modifierID: modifierID), for: app)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(key.isEmpty)
            }
        }
        .padding(24)
        .onDisappear { stopKeyReader() }
    }

    private func toggleKeyReader() {
        readingKey ? stopKeyReader() : startKeyReader()
    }

    private func startKeyReader() {
        readingKey = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stopKeyReader(); return nil }
            key = event.charactersIgnoringModifiers?.uppercased() ?? ""
            stopKeyReader()
            return nil
        }
    }

    private func stopKeyReader() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        readingKey = false
    }
}

struct CreateElementSheet: View {
    let pending: PendingElementCapture
    @ObservedObject var store: InspectorStore
    @Environment(\.dismiss) private var dismiss
    @State private var appID: String
    @State private var action: String
    @State private var key = ""
    @State private var modifierID = ModifierCatalog.all[0].id
    @State private var readingKey = false
    @State private var monitor: Any?
    @State private var selectedMenuItem: String?
    private var canSave: Bool {
        if pending.kind == .menuOption {
            return selectedMenuItem != nil && !key.isEmpty
        }
        return !key.isEmpty
    }

    init(pending: PendingElementCapture, store: InspectorStore) {
        self.pending = pending
        self.store = store
        _appID = State(initialValue: pending.appID)
        _action = State(initialValue: "\(Self.actionVerb(for: pending.kind)) \(pending.snapshot.displayTitle)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(pending.kind.rawValue, systemImage: "target")
                    .font(.title2.bold())
                Spacer()
                Text(pending.snapshot.captureMethod ?? "capture")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.secondary.opacity(0.14), in: Capsule())
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(pending.snapshot.displayTitle)
                    .font(.headline)
                    .lineLimit(1)
                Text(elementSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if pending.kind == .menuOption && store.menuItems.isEmpty {
                    Text("Right-click the element to read its menu")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))

            if pending.kind == .menuOption && !store.menuItems.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Choose a menu option").font(.headline)
                    ForEach(store.menuItems.filter(\.enabled)) { item in
                        Button {
                            selectedMenuItem = item.title
                            action = "Choose \(item.title)"
                        } label: {
                            HStack {
                                Text(item.title)
                                Spacer()
                                if selectedMenuItem == item.title {
                                    Image(systemName: "checkmark")
                                }
                            }
                            .padding(8)
                            .background(selectedMenuItem == item.title ? Color.accentColor.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Picker("App", selection: $appID) {
                ForEach(store.myApps) { app in
                    Text(app.name).tag(app.id)
                }
            }

            TextField("Action", text: $action)
                .textFieldStyle(.roundedBorder)

            Text("Modifier")
                .font(.headline)
            ScrollView(.horizontal) {
                HStack {
                    ForEach(ModifierCatalog.all) { modifier in
                        Button {
                            modifierID = modifier.id
                        } label: {
                            VStack(spacing: 4) {
                                Text(modifier.badge)
                                    .font(.caption.bold())
                                Text(modifier.label)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(10)
                            .frame(width: 92)
                            .background(modifierID == modifier.id ? Color.accentColor.opacity(0.26) : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack {
                Text(key.isEmpty ? "Press one key to pair" : "\(ModifierCatalog.preset(modifierID).badge) + \(key)")
                    .font(.headline.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(readingKey ? "Listening..." : "Read Key") { toggleKeyReader() }
            }

            Spacer()

            HStack {
                Button("Cancel") {
                    store.pendingCapture = nil
                    dismiss()
                }
                Spacer()
                Button("Save Shortcut") {
                    let shortcut = AppShortcut(
                        id: "\(appID)-\(UUID().uuidString)",
                        action: action.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? pending.snapshot.displayTitle : action,
                        key: key.uppercased(),
                        modifierID: modifierID
                    )
                    store.saveElementShortcut(shortcut, forAppID: appID, snapshot: pending.snapshot, menuItemTitle: selectedMenuItem)
                    store.pendingCapture = nil
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
            }
        }
        .padding(24)
        .onDisappear { stopKeyReader() }
    }

    private var elementSummary: String {
        let app = store.app(id: appID)?.name ?? pending.snapshot.appDisplayName
        return "\(pending.kind.rawValue) in \(app)"
    }

    private static func actionVerb(for kind: AdapterKind) -> String {
        switch kind {
        case .button: "Click"
        case .menuOption: "Choose"
        case .textField: "Focus"
        }
    }

    private func toggleKeyReader() {
        readingKey ? stopKeyReader() : startKeyReader()
    }

    private func startKeyReader() {
        readingKey = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stopKeyReader(); return nil }
            key = event.charactersIgnoringModifiers?.uppercased() ?? ""
            stopKeyReader()
            return nil
        }
    }

    private func stopKeyReader() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        readingKey = false
    }
}

struct XSpoonSettingsView: View {
    var body: some View {
        Form {
            Section("Global shortcuts") {
                LabeledContent("Toggle menu", value: "⌃⌥O")
                LabeledContent("Inspect current app", value: "⌃⌥I")
                LabeledContent("Capture item", value: "⌃⌥E")
                LabeledContent("Open inspector", value: "⌃⌥0")
            }
            Section("Hammerspoon") {
                Text("XSpoon reads and edits the shortcut catalog while Hammerspoon remains the action engine.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct MenuBarView: View {
    @ObservedObject var store: InspectorStore
    let onInspect: () -> Void
    let onOpenInspector: () -> Void

    init(
        store: InspectorStore,
        onInspect: @escaping () -> Void = {},
        onOpenInspector: @escaping () -> Void = {}
    ) {
        self.store = store
        self.onInspect = onInspect
        self.onOpenInspector = onOpenInspector
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Rectangle()
                    .fill(XSpoonTheme.red)
                    .frame(width: 3, height: 34)
                MenuBarIcon(size: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.context.appName)
                        .font(.headline)
                        .lineLimit(1)
                    StatusBadge(store: store)
                }
            }
            Divider()
            Button {
                onInspect()
            } label: {
                Label("Inspect Current App", systemImage: "scope")
            }
            .buttonStyle(HammerMenuButtonStyle(accent: XSpoonTheme.red))
            Button { onOpenInspector() } label: {
                Label("Open Inspector", systemImage: "macwindow")
            }
            .buttonStyle(HammerMenuButtonStyle(accent: .secondary))
            HStack(spacing: 8) {
                Menu("My Apps", systemImage: "square.grid.2x2") {
                    ForEach(store.myApps) { app in
                        Button {
                            store.focus(app)
                        } label: {
                            Label(app.name, systemImage: app.icon)
                        }
                    }
                }
                Text(activeAppLabel)
                    .font(.caption.bold())
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(XSpoonTheme.cyan.opacity(0.16), in: Capsule())
                    .foregroundStyle(.primary)
                    .help(store.context.bundleIdentifier)
                Spacer(minLength: 0)
            }
            Divider()
            Button { NSApplication.shared.terminate(nil) } label: {
                Label("Quit", systemImage: "power")
            }
            .buttonStyle(HammerMenuButtonStyle(accent: .secondary))
        }
        .padding(12)
        .frame(width: 270)
        .tint(XSpoonTheme.cyan)
    }

    private var activeAppLabel: String {
        let name = store.context.appName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty || name == "Unknown App" ? "No App" : name
    }
}

enum XSpoonTheme {
    static let red = Color(red: 0.82, green: 0.16, blue: 0.13)
    static let cyan = Color(red: 0.05, green: 0.62, blue: 0.82)
}

struct HammerMenuButtonStyle: ButtonStyle {
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(accent)
                .frame(width: 2, height: 18)
            configuration.label
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 14, weight: .medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(configuration.isPressed ? Color.secondary.opacity(0.18) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        )
        .contentShape(Rectangle())
    }
}

struct MenuBarIcon: View {
    @Environment(\.colorScheme) private var colorScheme
    let size: CGFloat

    var body: some View {
        Image(colorScheme == .dark ? "InspectorIconDark" : "InspectorIconLight", bundle: .module)
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
    }
}

struct StatusBadge: View {
    @ObservedObject var store: InspectorStore

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(store.isInspecting ? Color.orange : (store.snapshot == nil ? Color.secondary : Color.green))
                .frame(width: 6, height: 6)
            Text(store.isInspecting ? "Inspecting" : store.status)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .animation(.easeInOut(duration: 0.18), value: store.isInspecting)
    }
}
