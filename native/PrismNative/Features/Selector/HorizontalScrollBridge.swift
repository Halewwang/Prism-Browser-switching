import AppKit
import SwiftUI

enum ScrollInputDisposition: Equatable {
    case native
    case horizontal(points: CGFloat)
}

enum ScrollInputMapper {
    static let conventionalLineStep: CGFloat = 24

    static func map(
        deltaX _: CGFloat,
        deltaY: CGFloat,
        isPrecise: Bool,
        pointerInsideViewport: Bool
    ) -> ScrollInputDisposition {
        guard !isPrecise, pointerInsideViewport, deltaY != 0 else { return .native }
        return .horizontal(points: -deltaY * conventionalLineStep)
    }
}

enum SelectorScrollOverlayHitPolicy {
    static func captures(
        eventType: NSEvent.EventType,
        hasPreciseScrollingDeltas: () -> Bool
    ) -> Bool {
        switch eventType {
        case .leftMouseDown, .leftMouseDragged, .leftMouseUp:
            true
        case .scrollWheel:
            !hasPreciseScrollingDeltas()
        case .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp:
            false
        default:
            false
        }
    }
}

enum HorizontalDragUpdate: Equatable {
    case clickCandidate
    case dragging(horizontalDelta: CGFloat)
}

enum HorizontalDragEnd: Equatable {
    case activateClick
    case suppressClick
}

struct HorizontalDragTracker {
    static let threshold: CGFloat = 5

    private var startPoint: CGPoint?
    private var isDragging = false

    mutating func begin(at point: CGPoint) {
        startPoint = point
        isDragging = false
    }

    mutating func update(to point: CGPoint) -> HorizontalDragUpdate {
        guard let startPoint else { return .clickCandidate }
        let dx = point.x - startPoint.x
        let dy = point.y - startPoint.y
        if !isDragging, hypot(dx, dy) >= Self.threshold {
            isDragging = true
        }
        return isDragging ? .dragging(horizontalDelta: dx) : .clickCandidate
    }

    mutating func end() -> HorizontalDragEnd {
        defer {
            startPoint = nil
            isDragging = false
        }
        return isDragging ? .suppressClick : .activateClick
    }
}

struct HorizontalScrollBridge: NSViewRepresentable {
    struct BrowserHitTarget {
        let id: String
        let frame: CGRect
    }

    let browserHitTargets: [BrowserHitTarget]
    let currentOffset: CGFloat
    let onHorizontalWheel: @MainActor (CGFloat) -> Void
    let onDrag: @MainActor (CGFloat) -> Void
    let onActivateBrowser: @MainActor (String) -> Void

    func makeNSView(context: Context) -> SelectorScrollEventView {
        SelectorScrollEventView()
    }

    func updateNSView(_ nsView: SelectorScrollEventView, context _: Context) {
        nsView.browserHitTargets = browserHitTargets
        nsView.currentOffset = currentOffset
        nsView.onHorizontalWheel = onHorizontalWheel
        nsView.onDrag = onDrag
        nsView.onActivateBrowser = onActivateBrowser
    }

    static func dismantleNSView(_ nsView: SelectorScrollEventView, coordinator _: ()) {
        nsView.resetGesture()
    }
}

@MainActor
final class SelectorScrollEventView: NSView {
    var browserHitTargets: [HorizontalScrollBridge.BrowserHitTarget] = []
    var currentOffset: CGFloat = 0
    var onHorizontalWheel: (@MainActor (CGFloat) -> Void)?
    var onDrag: (@MainActor (CGFloat) -> Void)?
    var onActivateBrowser: (@MainActor (String) -> Void)?

    private var dragTracker = HorizontalDragTracker()
    private var dragStartOffset: CGFloat = 0
    private var mouseDownPoint: CGPoint?

    override var acceptsFirstResponder: Bool { false }

    override func scrollWheel(with event: NSEvent) {
        switch ScrollInputMapper.map(
            deltaX: event.scrollingDeltaX,
            deltaY: event.scrollingDeltaY,
            isPrecise: event.hasPreciseScrollingDeltas,
            pointerInsideViewport: bounds.contains(convert(event.locationInWindow, from: nil))
        ) {
        case .native:
            super.scrollWheel(with: event)
        case let .horizontal(points):
            onHorizontalWheel?(points)
        }
    }

    override func mouseDown(with event: NSEvent) {
        if event.type == .rightMouseDown {
            super.mouseDown(with: event)
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        mouseDownPoint = point
        dragStartOffset = currentOffset
        dragTracker.begin(at: point)
    }

    override func rightMouseDown(with event: NSEvent) {
        super.rightMouseDown(with: event)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let event = NSApp.currentEvent else { return super.hitTest(point) }
        guard SelectorScrollOverlayHitPolicy.captures(
            eventType: event.type,
            hasPreciseScrollingDeltas: { event.hasPreciseScrollingDeltas }
        ) else { return nil }
        return super.hitTest(point)
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard case let .dragging(horizontalDelta) = dragTracker.update(to: point) else { return }
        onDrag?(dragStartOffset - horizontalDelta)
    }

    override func mouseUp(with event: NSEvent) {
        defer { resetGesture() }
        guard dragTracker.end() == .activateClick,
              let point = mouseDownPoint
        else { return }
        let contentPoint = CGPoint(x: point.x + currentOffset, y: point.y)
        guard let target = browserHitTargets.first(where: { $0.frame.contains(contentPoint) }) else { return }
        onActivateBrowser?(target.id)
    }

    func resetGesture() {
        mouseDownPoint = nil
        dragTracker = HorizontalDragTracker()
    }
}
