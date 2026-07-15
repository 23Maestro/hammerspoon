import SwiftUI

struct InspectorDetailView: View {
    @ObservedObject var store: InspectorStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                contextSection
                captureSection
                adapterSection
                actionSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("")
        .tint(XSpoonTheme.cyan)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Rectangle()
                        .fill(XSpoonTheme.red)
                        .frame(width: 4, height: 28)
                    Text(store.snapshot?.text ?? "Element Inspector")
                        .font(.title.bold())
                }
                HStack(spacing: 8) {
                    StatusBadge(store: store)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(store.context.source.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    private var contextSection: some View {
        InspectorSection(title: "Current Focus", icon: "scope") {
            KeyValueRow(label: "Application", value: store.context.appName)
            KeyValueRow(label: "Bundle ID", value: store.context.bundleIdentifier)
            KeyValueRow(label: "Window", value: store.context.windowTitle.isEmpty ? "Unavailable" : store.context.windowTitle)
            KeyValueRow(label: "Source", value: store.context.source.rawValue)
        }
    }

    private var captureSection: some View {
        InspectorSection(title: "Captured Element", icon: "target") {
            if let snapshot = store.snapshot {
                KeyValueRow(label: "Role", value: snapshot.role ?? snapshot.tag ?? "Unavailable")
                KeyValueRow(label: "Title", value: snapshot.axTitle ?? snapshot.title ?? "Unavailable")
                KeyValueRow(label: "Value", value: snapshot.axValue ?? snapshot.text ?? "Unavailable")
                KeyValueRow(label: "Description", value: snapshot.axDescription ?? "Unavailable")
                if let selector = snapshot.selector {
                    KeyValueRow(label: "Selector", value: selector)
                }
            } else {
                Text("Arm Inspect, focus an element, then capture it through Hammerspoon.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var adapterSection: some View {
        let adapter = AdapterCatalog.all().first { $0.kind == store.selectedAdapter }
        return InspectorSection(title: store.selectedAdapter.rawValue, icon: "slider.horizontal.3") {
            Text(adapterDescription)
                .foregroundStyle(.secondary)
            ForEach(adapter?.fields(for: store.snapshot ?? ElementSnapshot()) ?? [], id: \.self) { field in
                Label(field, systemImage: "checkmark")
                    .font(.callout)
            }
        }
    }

    private var adapterDescription: String {
        switch store.selectedAdapter {
        case .setVariable: "Detect the action, locate the editable variable field, read the input after ‘to’, and validate the variable."
        case .chooseFromMenu: "Read the prompt and menu items, then expose editable item controls when Shortcuts provides them."
        case .askForInput: "Detect the action, read its input type, and expose the prompt as an editable field."
        }
    }

    private var actionSection: some View {
        InspectorSection(title: "Next Action", icon: "bolt") {
            HStack {
                Button { store.status = "Save action is ready for Hammerspoon bridge" } label: {
                    Label("Save Element Action", systemImage: "square.and.arrow.down")
                }
                Button { store.status = "Preset creation is ready for TypeScript compiler bridge" } label: {
                    Label("Create App Preset", systemImage: "keyboard")
                }
            }
        }
    }
}

struct InspectorSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(.tint)
                Text(title)
                    .font(.headline)
                Spacer()
            }
            VStack(alignment: .leading, spacing: 8, content: { content })
                .padding(14)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.quaternary, lineWidth: 1)
                )
        }
    }
}

struct KeyValueRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            Text(value.isEmpty ? "Unavailable" : value)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
