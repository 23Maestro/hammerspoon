import AppKit
import SwiftUI

@MainActor
final class CaptureOverlayController {
    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?
    private let model = CaptureOverlayModel()

    func show(snapshot: ElementSnapshot?, context: AppContext, status: String, autoDismiss: Bool = true, anchorAtMouse: Bool = false) {
        dismissTask?.cancel()

        model.update(snapshot: snapshot, context: context, status: status)
        let size = NSSize(width: 264, height: 108)
        let origin = anchorAtMouse ? offsetFromMouse(size: size) : overlayOrigin(for: snapshot?.frame, size: size)

        let panel = self.panel ?? makePanel()
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
        self.panel = panel

        if autoDismiss {
            dismissTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(2.2))
                await MainActor.run {
                    self?.panel?.orderOut(nil)
                }
            }
        }
    }

    func hide() {
        dismissTask?.cancel()
        dismissTask = nil
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 264, height: 108),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.contentViewController = NSHostingController(rootView: CaptureOverlayView(model: model))
        return panel
    }

    private func overlayOrigin(for rect: SnapshotRect?, size: NSSize) -> NSPoint {
        guard let rect else {
            return offsetFromMouse(size: size)
        }

        let point = NSPoint(x: CGFloat(rect.x + (rect.w / 2)), y: CGFloat(rect.y + (rect.h / 2)))
        let converted = cocoaPoint(fromAccessibilityPoint: point)
        return clampedOrigin(near: converted, size: size)
    }

    private func offsetFromMouse(size: NSSize) -> NSPoint {
        clampedOrigin(near: NSEvent.mouseLocation, size: size)
    }

    private func cocoaPoint(fromAccessibilityPoint point: NSPoint) -> NSPoint {
        for screen in NSScreen.screens {
            let frame = screen.frame
            let convertedY = frame.maxY - point.y
            if point.x >= frame.minX, point.x <= frame.maxX, convertedY >= frame.minY, convertedY <= frame.maxY {
                return NSPoint(x: point.x, y: convertedY)
            }
        }

        guard let screen = NSScreen.main else { return point }
        return NSPoint(x: point.x, y: screen.frame.maxY - point.y)
    }

    private func clampedOrigin(near point: NSPoint, size: NSSize) -> NSPoint {
        let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let proposed = NSPoint(x: point.x + 14, y: point.y - size.height - 12)

        return NSPoint(
            x: min(max(proposed.x, visible.minX + 12), visible.maxX - size.width - 12),
            y: min(max(proposed.y, visible.minY + 12), visible.maxY - size.height - 12)
        )
    }
}

@MainActor
private final class CaptureOverlayModel: ObservableObject {
    @Published private(set) var snapshot: ElementSnapshot?
    @Published private(set) var context = AppContext()
    @Published private(set) var status = "Inspecting"

    func update(snapshot: ElementSnapshot?, context: AppContext, status: String) {
        self.snapshot = snapshot
        self.context = context
        self.status = status
    }
}

private struct CaptureOverlayView: View {
    @ObservedObject var model: CaptureOverlayModel

    private var title: String {
        let candidates: [String?] = [
            model.snapshot?.displayTitle,
            model.snapshot?.axPlaceholder,
            model.snapshot?.axHelp
        ]

        return candidates.compactMap { value -> String? in
            guard let value else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }.first ?? "Captured element"
    }

    private var subtitle: String {
        let role = model.snapshot?.xRole ?? "XElement"
        let app = model.snapshot?.appName ?? model.context.appName
        return "\(role) - \(app)"
    }

    private var metadata: String {
        let actions = model.snapshot?.xActions.prefix(2).joined(separator: ", ") ?? ""
        if !actions.isEmpty {
            return "Can: \(actions)"
        }

        return model.snapshot?.captureSource.rawValue ?? model.context.source.rawValue
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "scope")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.cyan)
                .frame(width: 28, height: 28)
                .background(.white.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                Text(model.status == "Inspecting" ? "XSpoon live" : "XSpoon caught")
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(metadata)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if model.status != "Inspecting" {
                    Text(model.status)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: 264, height: 108)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.white.opacity(0.16), lineWidth: 1)
        )
    }
}
