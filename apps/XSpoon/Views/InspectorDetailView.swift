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
                KeyValueRow(label: "Type", value: snapshot.xRole)
                KeyValueRow(label: "Title", value: snapshot.axTitle ?? snapshot.title ?? "Unavailable")
                KeyValueRow(label: "Value", value: snapshot.axValue ?? snapshot.text ?? "Unavailable")
                KeyValueRow(label: "Description", value: snapshot.axDescription ?? "Unavailable")
                if let selector = snapshot.selector {
                    KeyValueRow(label: "Page target", value: selector)
                }
            } else {
                Text("No item captured")
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
        case .button: "Save this button so one shortcut can click it later."
        case .menuOption: "Save what opens the menu, wait a moment, then save the option to click."
        case .textField: "Save this text field so one shortcut can place your cursor here later."
        }
    }

    private var actionSection: some View {
        InspectorSection(title: "Next Action", icon: "bolt") {
            Button { _ = store.createElementFromCurrentTarget() } label: {
                Label("Capture", systemImage: "square.and.arrow.down")
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
