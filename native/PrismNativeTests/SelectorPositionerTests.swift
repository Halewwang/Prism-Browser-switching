import AppKit
@_spi(Testing) import PrismCore
import SwiftUI
import Testing
@testable import PrismNative

@Suite("Selector appearance")
struct SelectorAppearanceTests {
    @Test func lightPalettePreservesTheApprovedFigmaSurfaces() throws {
        let aqua = try #require(NSAppearance(named: .aqua))

        #expect(try rgb255(SelectorPalette.fieldNSColor, appearance: aqua) == [248, 248, 248])
        #expect(try rgb255(SelectorPalette.selectedNSColor, appearance: aqua) == [238, 238, 238])
        #expect(try rgb255(SelectorPalette.borderNSColor, appearance: aqua) == [225, 225, 225])
        #expect(try rgb255(SelectorPalette.selectionBorderNSColor, appearance: aqua) == [225, 225, 225])
    }

    @Test func darkPaletteResolvesToDarkSurfacesInsteadOfFixedLightGray() throws {
        let aqua = try #require(NSAppearance(named: .aqua))
        let darkAqua = try #require(NSAppearance(named: .darkAqua))

        let dynamicRoles = [
            SelectorPalette.fieldNSColor,
            SelectorPalette.selectedNSColor,
            SelectorPalette.borderNSColor,
            SelectorPalette.selectionBorderNSColor,
            SelectorPalette.highContrastBorderNSColor,
            SelectorPalette.primaryTextNSColor,
            SelectorPalette.secondaryTextNSColor,
            SelectorPalette.shortcutBackgroundNSColor,
            SelectorPalette.badgeBackgroundNSColor,
            SelectorPalette.badgeForegroundNSColor,
            SelectorPalette.errorNSColor,
        ]
        for role in dynamicRoles {
            #expect(try rgb255(role, appearance: aqua) != rgb255(role, appearance: darkAqua))
        }
        #expect(try relativeLuminance(SelectorPalette.fieldNSColor, appearance: darkAqua) < 0.08)
    }

    @Test func everySmallTextAndBadgeRoleMeetsContrastThresholdsInBothAppearances() throws {
        let aqua = try #require(NSAppearance(named: .aqua))
        let darkAqua = try #require(NSAppearance(named: .darkAqua))

        for appearance in [aqua, darkAqua] {
            #expect(try contrast(
                SelectorPalette.primaryTextNSColor,
                SelectorPalette.fieldNSColor,
                appearance: appearance
            ) >= 4.5)
            #expect(try contrast(
                SelectorPalette.secondaryTextNSColor,
                SelectorPalette.fieldNSColor,
                appearance: appearance
            ) >= 4.5)
            #expect(try contrast(
                SelectorPalette.primaryTextNSColor,
                SelectorPalette.selectedNSColor,
                appearance: appearance
            ) >= 4.5)
            #expect(try contrast(
                SelectorPalette.secondaryTextNSColor,
                SelectorPalette.shortcutBackgroundNSColor,
                appearance: appearance
            ) >= 4.5)
            #expect(try contrast(
                SelectorPalette.badgeForegroundNSColor,
                SelectorPalette.badgeBackgroundNSColor,
                appearance: appearance
            ) >= 4.5)
            #expect(try contrast(
                SelectorPalette.errorNSColor,
                SelectorPalette.fieldNSColor,
                appearance: appearance
            ) >= 3)
            #expect(try contrast(
                SelectorPalette.highContrastBorderNSColor,
                SelectorPalette.fieldNSColor,
                appearance: appearance
            ) >= 3)
        }
    }

    @Test func criticalDarkModeBoundariesMeetNonTextContrastThresholds() throws {
        let darkAqua = try #require(NSAppearance(named: .darkAqua))

        #expect(try contrast(
            SelectorPalette.borderNSColor,
            SelectorPalette.fieldNSColor,
            appearance: darkAqua
        ) >= 3)
        #expect(try contrast(
            SelectorPalette.selectionBorderNSColor,
            SelectorPalette.selectedNSColor,
            appearance: darkAqua
        ) >= 3)
    }

    private func rgb255(_ color: NSColor, appearance: NSAppearance) throws -> [Int] {
        let resolved = try components(color, appearance: appearance)
        return resolved.map { Int(($0 * 255).rounded()) }
    }

    private func contrast(
        _ foreground: NSColor,
        _ background: NSColor,
        appearance: NSAppearance
    ) throws -> Double {
        let foregroundLuminance = try relativeLuminance(foreground, appearance: appearance)
        let backgroundLuminance = try relativeLuminance(background, appearance: appearance)
        let lighter = max(foregroundLuminance, backgroundLuminance)
        let darker = min(foregroundLuminance, backgroundLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private func relativeLuminance(_ color: NSColor, appearance: NSAppearance) throws -> Double {
        let values = try components(color, appearance: appearance).map { component in
            let value = Double(component)
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * values[0] + 0.7152 * values[1] + 0.0722 * values[2]
    }

    private func components(_ color: NSColor, appearance: NSAppearance) throws -> [CGFloat] {
        var values: [CGFloat]?
        appearance.performAsCurrentDrawingAppearance {
            guard let srgb = color.usingColorSpace(NSColorSpace.sRGB) else { return }
            values = [srgb.redComponent, srgb.greenComponent, srgb.blueComponent]
        }
        return try #require(values)
    }
}

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

    @Test func existingPanelAndHostingViewRepaintWhenTheSystemAppearanceChanges() throws {
        let panel = SelectorPanel(
            contentRect: CGRect(origin: .zero, size: SelectorPanel.contentSize)
        )
        let controller = SelectorPanelController(panel: panel, orderFront: { _ in })
        panel.appearance = try #require(NSAppearance(named: .aqua))
        controller.present(
            content: AnyView(Rectangle().fill(SelectorPalette.field)),
            at: .zero
        )

        let lightColor = try centerColor(in: try #require(panel.contentView))

        panel.appearance = try #require(NSAppearance(named: .darkAqua))
        panel.contentView?.needsLayout = true
        panel.contentView?.needsDisplay = true
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.contentView?.displayIfNeeded()
        let darkColor = try centerColor(in: try #require(panel.contentView))

        #expect(lightColor.brightnessComponent > 0.8)
        #expect(darkColor.brightnessComponent < 0.3)
        #expect(lightColor.brightnessComponent - darkColor.brightnessComponent > 0.5)
    }

    private func centerColor(in view: NSView) throws -> NSColor {
        let representation = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: representation)
        let color = try #require(representation.colorAt(
            x: representation.pixelsWide / 2,
            y: representation.pixelsHigh / 2
        ))
        return try #require(color.usingColorSpace(.sRGB))
    }
}

@Suite("Window coordination")
@MainActor
struct WindowCoordinatorTests {
    @Test func repeatedPresentationReusesOnePanelAndStaleDismissDoesNothing() {
        let panelController = SpySelectorPanelController()
        let opening = MainWindowOpening(updateRoute: { _ in })
        let contentProvider = RecordingSelectorContentProvider()
        let coordinator = WindowCoordinator(
            mainWindowOpening: opening,
            panelController: panelController,
            pointerLocation: { CGPoint(x: 600, y: 500) },
            visibleFrames: { [CGRect(x: 0, y: 0, width: 1200, height: 800)] },
            contentProvider: contentProvider
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
        #expect(contentProvider.inputs.map(\.0) == [first.id, second.id])
        #expect(contentProvider.inputs.map(\.1) == [.normal, .noAvailableBrowsers])

        coordinator.dismiss(requestID: second.id)

        #expect(panelController.hideCount == 1)
        #expect(coordinator.activeRequestID == nil)
    }

    @Test func replacingAndMatchingDismissCancelExactlyTheOwnedSession() {
        let panelController = SpySelectorPanelController()
        let contentProvider = SessionLifecycleContentProvider()
        let coordinator = WindowCoordinator(
            mainWindowOpening: MainWindowOpening(updateRoute: { _ in }),
            panelController: panelController,
            contentProvider: contentProvider
        )
        let first = LinkRequest.fixture(id: UUID(), url: "https://first.example")
        let second = LinkRequest.fixture(id: UUID(), url: "https://second.example")

        coordinator.present(first, context: .normal)
        coordinator.present(second, context: .normal)
        #expect(contentProvider.cancelCounts[first.id] == 1)
        #expect(contentProvider.cancelCounts[second.id] == 0)

        coordinator.dismiss(requestID: first.id)
        #expect(contentProvider.cancelCounts[second.id] == 0)
        #expect(coordinator.activeRequestID == second.id)

        coordinator.dismiss(requestID: second.id)
        #expect(contentProvider.cancelCounts[second.id] == 1)
        #expect(coordinator.activeRequestID == nil)
    }

    @Test func replacingStaleDismissAndHideOwnExactlyOneLiveQueueSubscription() async throws {
        let store = SelectorSessionPendingStore()
        let queue = LinkRequestQueue(store: store)
        let first = LinkRequest.fixture(id: UUID(), url: "https://first.example")
        let second = LinkRequest.fixture(id: UUID(), url: "https://second.example")
        #expect(try await queue.enqueue(first))
        #expect(try await queue.enqueue(second))
        let contentProvider = QueueMonitoringContentProvider(queue: queue)
        let panelController = SelectorPanelController(orderFront: { _ in })
        let coordinator = WindowCoordinator(
            mainWindowOpening: MainWindowOpening(updateRoute: { _ in }),
            panelController: panelController,
            contentProvider: contentProvider
        )

        coordinator.present(first, context: .normal)
        var firstModel: SelectorViewModel? = try #require(contentProvider.model(for: first.id))
        weak var weakFirstModel = firstModel
        await waitUntilPendingCount(2, in: try #require(firstModel))
        #expect(await queue.pendingCountSubscriberCountForTesting() == 1)

        coordinator.present(second, context: .normal)
        var secondModel: SelectorViewModel? = try #require(contentProvider.model(for: second.id))
        weak var weakSecondModel = secondModel
        await waitUntilPendingCount(2, in: try #require(secondModel))
        await waitUntilSubscriberCount(1, in: queue)
        firstModel = nil
        #expect(weakFirstModel == nil)

        coordinator.dismiss(requestID: first.id)
        #expect(coordinator.activeRequestID == second.id)
        #expect(await queue.pendingCountSubscriberCountForTesting() == 1)

        let third = LinkRequest.fixture(id: UUID(), url: "https://third.example")
        #expect(try await queue.enqueue(third))
        await waitUntilPendingCount(3, in: try #require(secondModel))
        #expect(secondModel?.pendingCount == 3)

        secondModel = nil
        coordinator.hideSelector()
        await waitUntilSubscriberCount(0, in: queue)
        #expect(weakSecondModel == nil)
        #expect(await queue.pendingCountSubscriberCountForTesting() == 0)
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
            contentProvider: EmptySelectorContentProvider()
        )

        coordinator.showMainWindow(route: .history)

        #expect(events == ["route:history", "open"])
        #expect(openedID == "main")
        #expect(openedValue == .singleton)
    }
}

@MainActor
private final class EmptySelectorContentProvider: SelectorContentProviding {
    func makeSession(request: LinkRequest, context _: SelectorPresentationContext) -> SelectorSession {
        SelectorSession(requestID: request.id, content: AnyView(EmptyView()))
    }
}

@MainActor
private final class RecordingSelectorContentProvider: SelectorContentProviding {
    private(set) var inputs: [(UUID, SelectorPresentationContext)] = []

    func makeSession(request: LinkRequest, context: SelectorPresentationContext) -> SelectorSession {
        inputs.append((request.id, context))
        return SelectorSession(
            requestID: request.id,
            content: AnyView(Text(request.url.absoluteString))
        )
    }
}

@MainActor
private final class SessionLifecycleContentProvider: SelectorContentProviding {
    private(set) var cancelCounts: [UUID: Int] = [:]

    func makeSession(request: LinkRequest, context _: SelectorPresentationContext) -> SelectorSession {
        cancelCounts[request.id] = 0
        return SelectorSession(
            requestID: request.id,
            content: AnyView(EmptyView()),
            cancelAction: { [weak self] in
                self?.cancelCounts[request.id, default: 0] += 1
            }
        )
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

private actor SelectorSessionPendingStore: PendingRequestStore {
    private var snapshot = PendingRequestSnapshot(pendingRequests: [], terminalRecords: [])

    func load() async throws -> PendingRequestSnapshot { snapshot }

    func save(_ snapshot: PendingRequestSnapshot) async throws {
        self.snapshot = snapshot
    }
}

@MainActor
private final class QueueMonitoringContentProvider: SelectorContentProviding {
    private let queue: LinkRequestQueue
    private let catalog = QueueMonitoringBrowserCatalog()
    private let routing = QueueMonitoringRoutingCoordinator()
    private let navigation = QueueMonitoringNavigationHandler()
    private var models: [UUID: WeakSelectorModelBox] = [:]

    init(queue: LinkRequestQueue) {
        self.queue = queue
    }

    func makeSession(request: LinkRequest, context: SelectorPresentationContext) -> SelectorSession {
        let model = SelectorViewModel(
            request: request,
            context: context,
            browsers: [],
            browserCatalog: catalog,
            routingCoordinator: routing,
            pendingCountProvider: RecoveryQueuePendingCountProvider(queue: queue),
            navigationHandler: navigation,
            eligibleSourceBundleIDs: []
        )
        models[request.id] = WeakSelectorModelBox(model)
        let task = model.startPendingCountMonitoring()
        return SelectorSession(
            requestID: request.id,
            content: AnyView(SelectorModelRetainer(model: model)),
            monitoringTask: task,
            cancelAction: { [weak model] in model?.stopPendingCountMonitoring() }
        )
    }

    func model(for requestID: UUID) -> SelectorViewModel? {
        models[requestID]?.value
    }
}

@MainActor
private final class WeakSelectorModelBox {
    weak var value: SelectorViewModel?

    init(_ value: SelectorViewModel) {
        self.value = value
    }
}

private struct SelectorModelRetainer: View {
    let model: SelectorViewModel

    var body: some View {
        EmptyView()
    }
}

@MainActor
private final class QueueMonitoringBrowserCatalog: BrowserCataloging {
    func scan() async throws -> [BrowserDescriptor] { [] }
}

@MainActor
private final class QueueMonitoringRoutingCoordinator: LinkRoutingCoordinating {
    func processNext(while _: @escaping @MainActor () -> Bool) async -> LinkRoutingPassDisposition { .drained }
    func select(browserID _: BrowserID, for _: UUID) async {}
    func retry(browserID _: BrowserID, for _: UUID) async {}
    func markUncertainAttemptCompleted(requestID _: UUID) async {}
    func cancel(requestID _: UUID) async {}
}

@MainActor
private final class QueueMonitoringNavigationHandler: SelectorNavigationHandling {
    func openBrowserManagement() {}
    func openRuleEditor(prefill _: SelectorRulePrefill) {}
}

@MainActor
private func waitUntilPendingCount(
    _ expected: Int,
    in model: SelectorViewModel,
    sourceLocation: SourceLocation = #_sourceLocation
) async {
    for _ in 0 ..< 1_000 {
        if model.pendingCount == expected { return }
        await Task.yield()
    }
    Issue.record(
        "Timed out waiting for selector pending count \(expected)",
        sourceLocation: sourceLocation
    )
}

private func waitUntilSubscriberCount(
    _ expected: Int,
    in queue: LinkRequestQueue,
    sourceLocation: SourceLocation = #_sourceLocation
) async {
    for _ in 0 ..< 1_000 {
        if await queue.pendingCountSubscriberCountForTesting() == expected { return }
        await Task.yield()
    }
    Issue.record(
        "Timed out waiting for queue subscriber count \(expected)",
        sourceLocation: sourceLocation
    )
}
