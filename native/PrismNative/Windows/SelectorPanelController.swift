import AppKit
import SwiftUI

@MainActor
protocol SelectorPanelControlling: AnyObject {
    func present(content: AnyView, at origin: CGPoint)
    func hide()
}

@MainActor
private final class SelectorHostingView: NSHostingView<AnyView> {
    override var acceptsFirstResponder: Bool { true }
}

@MainActor
final class SelectorPanelController: SelectorPanelControlling {
    typealias OrderFront = @MainActor (SelectorPanel) -> Void

    let panel: SelectorPanel
    private let hostingView: NSHostingView<AnyView>
    private let orderFront: OrderFront

    init(
        panel: SelectorPanel = SelectorPanel(
            contentRect: CGRect(origin: .zero, size: SelectorPanel.contentSize)
        ),
        orderFront: @escaping OrderFront = { $0.makeKeyAndOrderFront(nil) }
    ) {
        self.panel = panel
        self.orderFront = orderFront
        let hostingView = SelectorHostingView(rootView: AnyView(EmptyView()))
        hostingView.frame = CGRect(origin: .zero, size: SelectorPanel.contentSize)
        hostingView.autoresizingMask = [.width, .height]
        self.hostingView = hostingView
        panel.contentView = hostingView
    }

    func present(content: AnyView, at origin: CGPoint) {
        hostingView.rootView = AnyView(EmptyView())
        hostingView.layoutSubtreeIfNeeded()
        hostingView.rootView = content
        hostingView.layoutSubtreeIfNeeded()
        panel.setFrameOrigin(origin)
        panel.initialFirstResponder = hostingView
        panel.makeFirstResponder(hostingView)
#if DEBUG
        if DebugUITestConfiguration.isEnabled {
            let supported: [NSAppearance.Name] = [.darkAqua, .aqua]
            let panelAppearance = panel.effectiveAppearance.bestMatch(from: supported)?.rawValue ?? "unknown"
            let hostingAppearance = hostingView.effectiveAppearance.bestMatch(from: supported)?.rawValue ?? "unknown"
            panel.setAccessibilityValue("panel=\(panelAppearance);hosting=\(hostingAppearance)")
        }
#endif
        orderFront(panel)
    }

    func hide() {
        hostingView.rootView = AnyView(EmptyView())
        hostingView.layoutSubtreeIfNeeded()
        panel.orderOut(nil)
    }
}
