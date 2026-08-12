import AppKit

@MainActor
final class SelectorPanel: NSPanel {
    static let contentSize = CGSize(width: 425, height: 200)

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(contentRect: CGRect) {
        super.init(
            contentRect: CGRect(origin: contentRect.origin, size: Self.contentSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        hasShadow = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentMinSize = Self.contentSize
        contentMaxSize = Self.contentSize
        isOpaque = false
        backgroundColor = .clear
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        setAccessibilityIdentifier("selector.panel")
        setAccessibilityTitle(String(
            localized: "selector.panel.accessibilityTitle",
            defaultValue: "Browser selector"
        ))
    }
}
