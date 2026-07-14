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

            Section("Inspect Sources") {
                ForEach(CaptureSource.allCases) { source in
                    Label(source.rawValue, systemImage: sourceIcon(source))
                        .foregroundStyle(source == store.context.source ? .primary : .secondary)
                }
            }

            Section("Shortcut Adapters") {
                ForEach(AdapterKind.allCases) { adapter in
                    Button {
                        store.selectedAdapter = adapter
                    } label: {
                        Label(adapter.rawValue, systemImage: adapter == store.selectedAdapter ? "checkmark.circle.fill" : "circle")
                    }
                    .buttonStyle(.plain)
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
