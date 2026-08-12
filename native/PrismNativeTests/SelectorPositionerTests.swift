import AppKit
import PrismCore
import SwiftUI
import Testing
@testable import PrismNative

@Suite("Selector positioning")
struct SelectorPositionerTests {
    private let panelSize = CGSize(width: 425, height: 200)

    @Test func positionsPanelExactlyTwelvePointsBelowAndRightOfPointer() {
        let frame = CGRect(x: 0, y: 0, width: 1440, height: 900)

        let origin = SelectorPositioner().origin(
            panelSize: panelSize,
            pointer: CGPoint(x: 300, y: 700),
            visibleFrames: [frame]
        )

        #expect(origin == CGPoint(x: 312, y: 488))
    }

    @Test func selectorRemainsInsideLeftDisplayVisibleFrame() {
        let frame = CGRect(x: -1920, y: 24, width: 1920, height: 1056)

        let origin = SelectorPositioner().origin(
            panelSize: panelSize,
            pointer: CGPoint(x: -1900, y: 30),
            visibleFrames: [frame]
        )

        #expect(origin == CGPoint(x: -1888, y: 24))
        #expect(origin.x >= frame.minX)
        #expect(origin.y >= frame.minY)
        #expect(origin.x + panelSize.width <= frame.maxX)
        #expect(origin.y + panelSize.height <= frame.maxY)
    }

    @Test func clampsToLeftEdgeWhenPanelOriginWouldCrossNegativeDisplayBoundary() {
        let frame = CGRect(x: -1920, y: 24, width: 1920, height: 1056)

        let origin = SelectorPositioner().origin(
            panelSize: panelSize,
            pointer: CGPoint(x: -2000, y: 700),
            visibleFrames: [frame]
        )

        #expect(origin == CGPoint(x: -1920, y: 488))
    }

    @Test func usesRightDisplayContainingPointer() {
        let main = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let right = CGRect(x: 1440, y: 40, width: 1920, height: 1040)

        let origin = SelectorPositioner().origin(
            panelSize: panelSize,
            pointer: CGPoint(x: 1800, y: 700),
            visibleFrames: [main, right]
        )

        #expect(origin == CGPoint(x: 1812, y: 488))
    }

    @Test func usesDisplayAboveMainDisplay() {
        let main = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let above = CGRect(x: -200, y: 900, width: 1728, height: 1117)

        let origin = SelectorPositioner().origin(
            panelSize: panelSize,
            pointer: CGPoint(x: 500, y: 1600),
            visibleFrames: [main, above]
        )

        #expect(origin == CGPoint(x: 512, y: 1388))
    }

    @Test func choosesNearestDisplayEdgeRatherThanNearestDisplayCenterWhenPointerIsInGap() {
        let largeLeft = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        let smallRight = CGRect(x: 1050, y: 490, width: 100, height: 20)

        let origin = SelectorPositioner().origin(
            panelSize: CGSize(width: 100, height: 100),
            pointer: CGPoint(x: 1010, y: 500),
            visibleFrames: [largeLeft, smallRight]
        )

        #expect(origin == CGPoint(x: 900, y: 388))
    }

    @Test func clampsRightAndBottomEdgesToVisibleFrame() {
        let frame = CGRect(x: 100, y: 50, width: 900, height: 600)

        let origin = SelectorPositioner().origin(
            panelSize: panelSize,
            pointer: CGPoint(x: 990, y: 60),
            visibleFrames: [frame]
        )

        #expect(origin == CGPoint(x: 575, y: 50))
    }

    @Test func oversizedPanelUsesDeterministicVisibleFrameOrigin() {
        let frame = CGRect(x: -500, y: 75, width: 300, height: 150)

        let origin = SelectorPositioner().origin(
            panelSize: panelSize,
            pointer: CGPoint(x: -300, y: 100),
            visibleFrames: [frame]
        )

        #expect(origin == frame.origin)
    }

    @Test func emptyVisibleFramesFallsBackToUnclampedPointerOffset() {
        let origin = SelectorPositioner().origin(
            panelSize: panelSize,
            pointer: CGPoint(x: -25, y: 75),
            visibleFrames: []
        )

        #expect(origin == CGPoint(x: -13, y: -137))
    }
}

@Suite("Selector panel")
@MainActor
struct SelectorPanelTests {
    @Test func panelUsesFixedNonactivatingConfigurationAndCanReceiveKeyboardFocus() {
        let panel = SelectorPanel(contentRect: CGRect(x: 40, y: 60, width: 10, height: 10))

        #expect(panel.canBecomeKey)
        #expect(panel.canBecomeMain == false)
        #expect(panel.styleMask.contains(.borderless))
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(panel.contentRect(forFrameRect: panel.frame).size == CGSize(width: 425, height: 200))
        #expect(panel.contentMinSize == SelectorPanel.contentSize)
        #expect(panel.contentMaxSize == SelectorPanel.contentSize)
        #expect(panel.hasShadow)
        #expect(panel.level == .floating)
        #expect(panel.collectionBehavior.contains(NSWindow.CollectionBehavior.canJoinAllSpaces))
        #expect(panel.collectionBehavior.contains(NSWindow.CollectionBehavior.fullScreenAuxiliary))
        #expect(panel.isOpaque == false)
        #expect(panel.backgroundColor == .clear)
    }

    @Test func controllerInstallsHostingViewAndInitialFirstResponderBeforeShowing() {
        var responderWasInstalledBeforeOrdering = false
        let controller = SelectorPanelController(orderFront: { panel in
            responderWasInstalledBeforeOrdering = panel.initialFirstResponder === panel.contentView
                && panel.firstResponder === panel.contentView
        })

        controller.present(content: AnyView(Text("Choose a browser")), at: CGPoint(x: 80, y: 90))

        let hostingView = controller.panel.contentView as? NSHostingView<AnyView>
        #expect(hostingView != nil)
        #expect(controller.panel.initialFirstResponder === hostingView)
        #expect(controller.panel.firstResponder === hostingView)
        #expect(responderWasInstalledBeforeOrdering)
        #expect(controller.panel.frame.origin == CGPoint(x: 80, y: 90))
        #expect(controller.panel.frame.size == CGSize(width: 425, height: 200))

        let firstHostingView = hostingView
        controller.present(content: AnyView(Text("Try another browser")), at: CGPoint(x: 100, y: 120))
        #expect(controller.panel.contentView === firstHostingView)
    }
}

@Suite("Window coordination")
@MainActor
struct WindowCoordinatorTests {
    @Test func repeatedPresentationReusesOnePanelAndStaleDismissDoesNothing() {
        let panelController = SpySelectorPanelController()
        let opening = MainWindowOpening(updateRoute: { _ in })
        var contentInputs: [(UUID, SelectorPresentationContext)] = []
        let coordinator = WindowCoordinator(
            mainWindowOpening: opening,
            panelController: panelController,
            pointerLocation: { CGPoint(x: 600, y: 500) },
            visibleFrames: { [CGRect(x: 0, y: 0, width: 1200, height: 800)] },
            contentFactory: { request, context in
                contentInputs.append((request.id, context))
                return AnyView(Text(request.url.absoluteString))
            }
        )
        let first = LinkRequest.fixture(id: UUID(), url: "https://first.example")
        let second = LinkRequest.fixture(id: UUID(), url: "https://second.example")

        coordinator.present(first, context: .normal)
        coordinator.present(second, context: .noAvailableBrowsers)
        coordinator.dismiss(requestID: first.id)

        #expect(panelController.presentCount == 2)
        #expect(panelController.hideCount == 0)
        #expect(coordinator.activeRequestID == second.id)
        #expect(panelController.origins == [CGPoint(x: 612, y: 288), CGPoint(x: 612, y: 288)])
        #expect(contentInputs.map(\.0) == [first.id, second.id])
        #expect(contentInputs.map(\.1) == [.normal, .noAvailableBrowsers])

        coordinator.dismiss(requestID: second.id)

        #expect(panelController.hideCount == 1)
        #expect(coordinator.activeRequestID == nil)
    }

    @Test func showMainWindowUpdatesSharedRouteBeforeInvokingSingletonOpenAction() {
        var events: [String] = []
        let opening = MainWindowOpening(updateRoute: { route in
            events.append("route:\(route)")
        })
        var openedID: String?
        var openedValue: MainWindowIdentity?
        opening.register { id, value in
            openedID = id
            openedValue = value
            events.append("open")
        }
        let coordinator = WindowCoordinator(
            mainWindowOpening: opening,
            panelController: SpySelectorPanelController(),
            contentFactory: { _, _ in AnyView(EmptyView()) }
        )

        coordinator.showMainWindow(route: .history)

        #expect(events == ["route:history", "open"])
        #expect(openedID == "main")
        #expect(openedValue == .singleton)
    }
}

@MainActor
private final class SpySelectorPanelController: SelectorPanelControlling {
    let panel = SelectorPanel(contentRect: CGRect(origin: .zero, size: SelectorPanel.contentSize))
    private(set) var presentCount = 0
    private(set) var hideCount = 0
    private(set) var origins: [CGPoint] = []

    func present(content _: AnyView, at origin: CGPoint) {
        presentCount += 1
        origins.append(origin)
    }

    func hide() {
        hideCount += 1
    }
}
