import SwiftUI

struct SidebarView: View {
    @ObservedObject var store: InspectorStore

    var body: some View {
        List {
            Section("Current Focus") {
                Label(store.context.appName, systemImage: "app")
                if !store.context.windowTitle.isEmpty {
                    Text(store.context.windowTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Section("How XSpoon found it") {
                Label(store.context.source.rawValue, systemImage: sourceIcon(store.context.source))
                Text(store.context.source.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Captured as") {
                if let snapshot = store.snapshot, let kind = AdapterKind.detect(snapshot) {
                    Label(kind.rawValue, systemImage: "checkmark.circle.fill")
                } else {
                    Label("Unsupported item", systemImage: "xmark.circle")
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Inspector")
    }

    private func sourceIcon(_ source: CaptureSource) -> String {
        switch source {
        case .accessibility: "accessibility"
        case .dom: "globe"
        case .webView: "rectangle.on.rectangle"
        }
    }
}
