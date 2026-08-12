import CoreGraphics
import Foundation
import PrismCore
import Testing
@testable import PrismNative

@Suite("Selector metrics")
struct SelectorMetricsTests {
    @Test(arguments: [0, 1, 3])
    func upToThreeBrowsersUseTheFigmaThreeColumnGeometry(count: Int) {
        #expect(SelectorMetrics.itemWidth(browserCount: count) == 130)
        #expect(SelectorMetrics.itemGap(browserCount: count) == 5)
        #expect(SelectorMetrics.viewportLeadingInset == 6)
        #expect(SelectorMetrics.viewportTrailingInset == 6)
    }

    @Test(arguments: [4, 5, 9, 10])
    func fourOrMoreBrowsersUseTheConfirmedScrollingGeometry(count: Int) {
        #expect(abs(SelectorMetrics.itemWidth(browserCount: count) - 109.14285714285714) < 0.000_001)
        #expect(SelectorMetrics.itemGap(browserCount: count) == 8)
    }

    @Test func threeBrowserCentersAndInsetsMatchFigma() {
        #expect(SelectorMetrics.headerURLWidth == 248)
        #expect(SelectorMetrics.browserCenterX(index: 0, browserCount: 3) == 71)
        #expect(SelectorMetrics.browserCenterX(index: 1, browserCount: 3) == 206)
        #expect(SelectorMetrics.browserCenterX(index: 2, browserCount: 3) == 341)
        #expect(SelectorMetrics.contentWidth(browserCount: 3) == 412)
    }

    @Test func fourBrowserInitialViewportShowsExactlyHalfOfTheFourthCard() {
        let width = SelectorMetrics.itemWidth(browserCount: 4)
        let gap = SelectorMetrics.itemGap(browserCount: 4)
        let fourthStart = SelectorMetrics.viewportLeadingInset + (3 * (width + gap))
        let visible = SelectorMetrics.viewportSize.width - fourthStart

        #expect(abs(visible - width / 2) < 0.000_001)
        #expect(SelectorMetrics.maxOffset(browserCount: 4) > 0)
    }

    @Test func scrollOffsetClampsAtBothBounds() {
        let maximum = SelectorMetrics.maxOffset(browserCount: 5)
        #expect(SelectorMetrics.clampedOffset(-24, browserCount: 5) == 0)
        #expect(SelectorMetrics.clampedOffset(maximum + 24, browserCount: 5) == maximum)
        #expect(SelectorMetrics.clampedOffset(12, browserCount: 3) == 0)
    }

    @Test func keyboardRevealUsesTheMinimumOffsetThatFullyShowsTheCard() {
        let width = SelectorMetrics.itemWidth(browserCount: 5)
        let expectedFourthOffset = SelectorMetrics.viewportLeadingInset
            + 3 * (width + SelectorMetrics.itemGap(browserCount: 5))
            + width
            - SelectorMetrics.viewportSize.width
        #expect(abs(SelectorMetrics.revealOffset(
            browserIndex: 3,
            browserCount: 5,
            currentOffset: 0
        ) - expectedFourthOffset) < 0.000_001)
        #expect(SelectorMetrics.revealOffset(
            browserIndex: 2,
            browserCount: 5,
            currentOffset: 0
        ) == 0)
        #expect(SelectorMetrics.revealOffset(
            browserIndex: 0,
            browserCount: 5,
            currentOffset: 120
        ) == SelectorMetrics.viewportLeadingInset)
    }

    @Test func recoveryLayoutFitsStatusAndFullCardsInsideTheFixedViewport() {
        #expect(
            SelectorMetrics.recoveryStatusHeight + SelectorMetrics.recoveryStripHeight
                == SelectorMetrics.viewportSize.height
        )
        #expect(SelectorMetrics.recoveryItemHeight + 12 == SelectorMetrics.recoveryStripHeight)
    }
}

@Suite("Selector input mapping")
struct SelectorInputMappingTests {
    @Test func preciseHorizontalTrackpadInputRemainsNative() {
        #expect(ScrollInputMapper.map(
            deltaX: 7,
            deltaY: 2,
            isPrecise: true,
            pointerInsideViewport: true
        ) == .native)
    }

    @Test func preciseVerticalOnlyTrackpadInputRemainsVerticalAndNative() {
        #expect(ScrollInputMapper.map(
            deltaX: 0,
            deltaY: -12,
            isPrecise: true,
            pointerInsideViewport: true
        ) == .native)
    }

    @Test func ConventionalWheelConvertsVerticalLinesOnlyInsideViewport() {
        #expect(ScrollInputMapper.map(
            deltaX: 0,
            deltaY: -2,
            isPrecise: false,
            pointerInsideViewport: true
        ) == .horizontal(points: 48))
        #expect(ScrollInputMapper.map(
            deltaX: 0,
            deltaY: -2,
            isPrecise: false,
            pointerInsideViewport: false
        ) == .native)
    }

    @Test func clickDragBeginsAtFivePointsAndSuppressesOnlyTheDraggedClick() {
        var tracker = HorizontalDragTracker()
        tracker.begin(at: CGPoint(x: 10, y: 10))

        #expect(tracker.update(to: CGPoint(x: 13, y: 13)) == .clickCandidate)
        #expect(tracker.end() == .activateClick)

        tracker.begin(at: CGPoint(x: 10, y: 10))
        #expect(tracker.update(to: CGPoint(x: 15, y: 10)) == .dragging(horizontalDelta: 5))
        #expect(tracker.end() == .suppressClick)
    }

    @Test func overlayCapturesOnlyLeftDragAndConventionalWheelInput() {
        #expect(SelectorScrollOverlayHitPolicy.captures(
            eventType: .leftMouseDown,
            hasPreciseScrollingDeltas: { false }
        ))
        #expect(SelectorScrollOverlayHitPolicy.captures(
            eventType: .scrollWheel,
            hasPreciseScrollingDeltas: { false }
        ))
        #expect(!SelectorScrollOverlayHitPolicy.captures(
            eventType: .scrollWheel,
            hasPreciseScrollingDeltas: { true }
        ))
        #expect(!SelectorScrollOverlayHitPolicy.captures(
            eventType: .rightMouseDown,
            hasPreciseScrollingDeltas: { false }
        ))
        #expect(!SelectorScrollOverlayHitPolicy.captures(
            eventType: .otherMouseDown,
            hasPreciseScrollingDeltas: { false }
        ))
    }

    @Test func overlayNeverReadsScrollPrecisionFromANonScrollEvent() {
        var didReadPrecision = false

        let captures = SelectorScrollOverlayHitPolicy.captures(
            eventType: .cursorUpdate,
            hasPreciseScrollingDeltas: {
                didReadPrecision = true
                return false
            }
        )

        #expect(!captures)
        #expect(!didReadPrecision)
    }
}

@Suite("Selector model")
@MainActor
struct SelectorViewModelTests {
    @Test func arrowsWrapAndNumericShortcutsRevealInstalledBrowsersOnly() {
        let fixture = SelectorFixture(browserCount: 10)
        let model = fixture.model

        model.selectPrevious()
        #expect(model.selectedIndex == 9)
        #expect(model.revealBrowserID == fixture.browsers[9].id)

        model.selectNext()
        #expect(model.selectedIndex == 0)
        model.selectShortcut(9)
        #expect(model.selectedIndex == 8)
        #expect(model.revealBrowserID == fixture.browsers[8].id)
        model.selectShortcut(0)
        model.selectShortcut(10)
        #expect(model.selectedIndex == 8)
        #expect(model.shortcut(forBrowserAt: 8) == 9)
        #expect(model.shortcut(forBrowserAt: 9) == nil)
    }

    @Test func enterEscapeAndMouseActionsUseExactRequestAndNeverDismissDirectly() async {
        let fixture = SelectorFixture(browserCount: 3)
        let model = fixture.model

        await model.activateSelected()
        await model.cancel()
        await model.activateBrowser(id: fixture.browsers[2].id)

        #expect(fixture.routing.calls == [
            .select(browserID: fixture.browsers[0].id, requestID: fixture.request.id),
            .cancel(requestID: fixture.request.id),
            .select(browserID: fixture.browsers[2].id, requestID: fixture.request.id)
        ])
        #expect(model.requestID == fixture.request.id)
    }

    @Test func pendingBadgeReadsLiveCountAndAppearsOnlyFromTwo() async {
        let pending = MutablePendingCountProvider(count: 1)
        let fixture = SelectorFixture(browserCount: 3, pendingCountProvider: pending)

        fixture.model.startPendingCountMonitoring()
        await pending.waitUntilSubscribed()
        await waitUntilPendingCount(1, in: fixture.model)
        #expect(fixture.model.pendingBadgeText == nil)
        #expect(fixture.model.pendingAccessibilityValue == nil)

        pending.send(4)
        await waitUntilPendingCount(4, in: fixture.model)
        #expect(fixture.model.pendingBadgeText == "4")
        #expect(fixture.model.pendingAccessibilityValue == "4 links waiting")
        fixture.model.stopPendingCountMonitoring()
    }

    @Test func stoppingPendingMonitoringReleasesTheModelWithoutAnotherStreamValue() async throws {
        let pending = MutablePendingCountProvider(count: 1)
        var fixture: SelectorFixture? = SelectorFixture(browserCount: 3, pendingCountProvider: pending)
        weak var weakModel = fixture?.model

        fixture?.model.startPendingCountMonitoring()
        await pending.waitUntilSubscribed()
        await waitUntilPendingCount(1, in: try #require(fixture?.model))
        fixture?.model.stopPendingCountMonitoring()
        await pending.waitUntilTerminated()
        fixture = nil

        #expect(weakModel == nil)
    }

    @Test func launchFailureRetriesSameBrowserAndSelectsAnother() async {
        let fixture = SelectorFixture(browserCount: 3, context: .launchFailed(
            browserID: BrowserID("browser-1"),
            message: "The browser did not accept the link."
        ))

        await fixture.model.activateBrowser(id: fixture.browsers[1].id)
        await fixture.model.activateBrowser(id: fixture.browsers[2].id)

        #expect(fixture.routing.calls == [
            .retry(browserID: fixture.browsers[1].id, requestID: fixture.request.id),
            .select(browserID: fixture.browsers[2].id, requestID: fixture.request.id)
        ])
        #expect(fixture.model.failedBrowserID == fixture.browsers[1].id)
        #expect(fixture.model.accessibleFailureMessage == "The browser did not accept the link.")
    }

    @Test func uncertainOutcomeKnownBrowserRetriesItAndAllowsCompletionOrCancellation() async {
        let fixture = SelectorFixture(
            browserCount: 3,
            context: .outcomeUnknown(browserID: BrowserID("browser-2"))
        )

        await fixture.model.retryRecovery()
        await fixture.model.markCompleted()
        await fixture.model.cancel()

        #expect(fixture.routing.calls == [
            .retry(browserID: fixture.browsers[2].id, requestID: fixture.request.id),
            .markCompleted(requestID: fixture.request.id),
            .cancel(requestID: fixture.request.id)
        ])
    }

    @Test func uncertainOutcomeUnavailableOrNilRequiresExplicitAvailableChoice() async {
        let unavailable = SelectorFixture(
            browserCount: 2,
            context: .outcomeUnknown(browserID: BrowserID("missing"))
        )
        await unavailable.model.retryRecovery()
        #expect(unavailable.routing.calls.isEmpty)
        #expect(unavailable.model.requiresExplicitRecoveryBrowser)
        await unavailable.model.retryRecovery(browserID: unavailable.browsers[1].id)
        #expect(unavailable.routing.calls == [
            .retry(browserID: unavailable.browsers[1].id, requestID: unavailable.request.id)
        ])

        let unknown = SelectorFixture(browserCount: 2, context: .outcomeUnknown(browserID: nil))
        await unknown.model.retryRecovery()
        #expect(unknown.routing.calls.isEmpty)
        #expect(unknown.model.requiresExplicitRecoveryBrowser)
    }

    @Test func storageUnavailableNeverClaimsSuccessAndUsesCoordinatorRetry() async {
        let fixture = SelectorFixture(browserCount: 2, context: .storageUnavailable)
        await fixture.model.retryRecovery(browserID: fixture.browsers[1].id)

        #expect(fixture.routing.calls == [
            .retry(browserID: fixture.browsers[1].id, requestID: fixture.request.id)
        ])
        #expect(fixture.model.canMarkCompleted == false)
    }

    @Test func noBrowserRescanAndManagementPreserveTheActiveRequest() async {
        let catalog = MutableBrowserCatalog(results: [.success([]), .success(makeBrowsers(count: 2))])
        let fixture = SelectorFixture(
            browserCount: 0,
            context: .noAvailableBrowsers,
            browserCatalog: catalog
        )

        await fixture.model.rescan()
        #expect(fixture.model.browsers.count == 0)
        #expect(fixture.model.scanFailureMessage == nil)
        await fixture.model.rescan()
        #expect(fixture.model.browsers.count == 2)
        fixture.model.openBrowserManagement()

        #expect(fixture.navigation.browserManagementOpenCount == 1)
        #expect(fixture.routing.calls.isEmpty)
        #expect(fixture.model.requestID == fixture.request.id)
    }

    @Test func scanFailureIsRecoverableAndNeverLooksLikeSuccessfulEmptyState() async {
        let catalog = MutableBrowserCatalog(results: [.failure(SelectorTestError.scanFailed)])
        let fixture = SelectorFixture(
            browserCount: 0,
            context: .noAvailableBrowsers,
            browserCatalog: catalog
        )

        await fixture.model.rescan()

        #expect(fixture.model.browsers.isEmpty)
        #expect(fixture.model.scanFailureMessage != nil)
        #expect(fixture.model.canRescan)
    }

    @Test func ruleIntentsUseExactHostAndGateSourceByConfidenceAndEligibility() {
        let confirmed = SourceApplication(
            bundleIdentifier: "com.example.eligible",
            displayName: "Eligible Source",
            confidence: .confirmed
        )
        let fixture = SelectorFixture(
            browserCount: 2,
            source: confirmed,
            eligibleSourceBundleIDs: ["com.example.eligible"]
        )

        fixture.model.openDomainRule(browserID: fixture.browsers[0].id)
        fixture.model.openSourceRule(browserID: fixture.browsers[1].id)

        #expect(fixture.navigation.rulePrefills == [
            .domain(host: "private.example", browserID: fixture.browsers[0].id),
            .source(
                bundleIdentifier: "com.example.eligible",
                displayName: "Eligible Source",
                browserID: fixture.browsers[1].id
            )
        ])
        #expect(fixture.routing.calls.isEmpty)
    }

    @Test(arguments: [SourceConfidence.low, .unknown])
    func unconfirmedSourceNeverOffersSourceRule(confidence: SourceConfidence) {
        let source = SourceApplication(
            bundleIdentifier: "com.example.eligible",
            displayName: "Source",
            confidence: confidence
        )
        let fixture = SelectorFixture(
            browserCount: 1,
            source: source,
            eligibleSourceBundleIDs: ["com.example.eligible"]
        )

        #expect(fixture.model.canCreateSourceRule == false)
        fixture.model.openSourceRule(browserID: fixture.browsers[0].id)
        #expect(fixture.navigation.rulePrefills.isEmpty)
    }
}

@Suite("Selector production graph")
@MainActor
struct SelectorProductionGraphTests {
    @Test func compositionInjectsRetainedRealFactoryBeforeWindowCoordination() {
        let composition = ProductionAppComposition.makeForTesting(
            modelContainerFactory: { try ModelContainerFactory.make(inMemory: true) },
            recoveryStoreFactory: { SelectorTestRecoveryStore() }
        )

        #expect(composition.windowCoordinator.contentProvider === composition.selectorSessionFactory)
        #expect(composition.selectorSessionFactory.browserCatalog === composition.browserCatalog)
        #expect(composition.selectorSessionFactory.routingCoordinator === composition.linkRoutingCoordinator)
        #expect(composition.selectorSessionFactory.pendingCountProvider.queue === composition.recoveryQueue)
        #expect(composition.selectorSessionFactory.sourceManifest == composition.sourceManifest)
        #expect(composition.selectorSessionFactory.operatingSystemVersion.majorVersion
            == composition.operatingSystemVersion.majorVersion)
        #expect(composition.selectorSessionFactory.operatingSystemVersion.minorVersion
            == composition.operatingSystemVersion.minorVersion)
        #expect(composition.selectorSessionFactory.operatingSystemVersion.patchVersion
            == composition.operatingSystemVersion.patchVersion)
    }
}

@MainActor
private struct SelectorFixture {
    let request: LinkRequest
    let browsers: [BrowserDescriptor]
    let routing: RecordingRoutingCoordinator
    let navigation: RecordingSelectorNavigationHandler
    let model: SelectorViewModel

    init(
        browserCount: Int,
        context: SelectorPresentationContext = .normal,
        source: SourceApplication = .unknown,
        eligibleSourceBundleIDs: Set<String> = [],
        browserCatalog: MutableBrowserCatalog? = nil,
        pendingCountProvider: MutablePendingCountProvider? = nil
    ) {
        let request = LinkRequest(
            id: UUID(),
            url: URL(string: "https://private.example/path?secret=not-for-logs")!,
            receivedAt: Date(timeIntervalSince1970: 100),
            source: source,
            state: .presenting
        )
        let browsers = makeBrowsers(count: browserCount)
        let routing = RecordingRoutingCoordinator()
        let navigation = RecordingSelectorNavigationHandler()
        self.request = request
        self.browsers = browsers
        self.routing = routing
        self.navigation = navigation
        model = SelectorViewModel(
            request: request,
            context: context,
            browsers: browsers,
            browserCatalog: browserCatalog ?? MutableBrowserCatalog(results: [.success(browsers)]),
            routingCoordinator: routing,
            pendingCountProvider: pendingCountProvider ?? MutablePendingCountProvider(count: 1),
            navigationHandler: navigation,
            eligibleSourceBundleIDs: eligibleSourceBundleIDs
        )
    }
}

@MainActor
private final class RecordingRoutingCoordinator: LinkRoutingCoordinating {
    enum Call: Equatable {
        case select(browserID: BrowserID, requestID: UUID)
        case retry(browserID: BrowserID, requestID: UUID)
        case markCompleted(requestID: UUID)
        case cancel(requestID: UUID)
    }

    private(set) var calls: [Call] = []

    func processNext(
        while _: @escaping @MainActor () -> Bool
    ) async -> LinkRoutingPassDisposition {
        .drained
    }

    func select(browserID: BrowserID, for requestID: UUID) async {
        calls.append(.select(browserID: browserID, requestID: requestID))
    }

    func retry(browserID: BrowserID, for requestID: UUID) async {
        calls.append(.retry(browserID: browserID, requestID: requestID))
    }

    func markUncertainAttemptCompleted(requestID: UUID) async {
        calls.append(.markCompleted(requestID: requestID))
    }

    func cancel(requestID: UUID) async {
        calls.append(.cancel(requestID: requestID))
    }
}

@MainActor
private final class MutableBrowserCatalog: BrowserCataloging {
    private var results: [Result<[BrowserDescriptor], Error>]

    init(results: [Result<[BrowserDescriptor], Error>]) {
        self.results = results
    }

    func scan() async throws -> [BrowserDescriptor] {
        guard !results.isEmpty else { return [] }
        return try results.removeFirst().get()
    }
}

@MainActor
private final class MutablePendingCountProvider: SelectorPendingCountProviding {
    var count: Int
    private var continuation: AsyncStream<Int>.Continuation?
    private var subscriptionWaiters: [CheckedContinuation<Void, Never>] = []
    private var didTerminate = false
    private var terminationWaiters: [CheckedContinuation<Void, Never>] = []

    init(count: Int) {
        self.count = count
    }

    func pendingCountUpdates() async -> AsyncStream<Int> {
        let (stream, continuation) = AsyncStream<Int>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        self.continuation = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.didTerminate = true
                let waiters = self.terminationWaiters
                self.terminationWaiters.removeAll()
                waiters.forEach { $0.resume() }
            }
        }
        continuation.yield(count)
        let waiters = subscriptionWaiters
        subscriptionWaiters.removeAll()
        waiters.forEach { $0.resume() }
        return stream
    }

    func send(_ count: Int) {
        self.count = count
        continuation?.yield(count)
    }

    func waitUntilSubscribed() async {
        if continuation != nil { return }
        await withCheckedContinuation { continuation in
            subscriptionWaiters.append(continuation)
        }
    }


    func waitUntilTerminated() async {
        if didTerminate { return }
        await withCheckedContinuation { continuation in
            terminationWaiters.append(continuation)
        }
    }
}

@MainActor
private final class RecordingSelectorNavigationHandler: SelectorNavigationHandling {
    private(set) var browserManagementOpenCount = 0
    private(set) var rulePrefills: [SelectorRulePrefill] = []

    func openBrowserManagement() {
        browserManagementOpenCount += 1
    }

    func openRuleEditor(prefill: SelectorRulePrefill) {
        rulePrefills.append(prefill)
    }
}

private enum SelectorTestError: Error {
    case scanFailed
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
        "Timed out waiting for pending count \(expected); received \(model.pendingCount)",
        sourceLocation: sourceLocation
    )
}

private actor SelectorTestRecoveryStore: PendingRequestStore, PersistenceWarningSource {
    private var snapshot = PendingRequestSnapshot(pendingRequests: [], terminalRecords: [])

    func load() async throws -> PendingRequestSnapshot { snapshot }

    func save(_ snapshot: PendingRequestSnapshot) async throws {
        self.snapshot = snapshot
    }

    func drainPersistenceWarnings() async -> [PersistenceWarning] { [] }
}

private func makeBrowsers(count: Int) -> [BrowserDescriptor] {
    (0 ..< count).map { index in
        BrowserDescriptor(
            id: BrowserID("browser-\(index)"),
            bundleIdentifier: "com.example.browser-\(index)",
            displayName: "Browser \(index + 1)",
            applicationURL: URL(fileURLWithPath: "/Applications/Browser\(index + 1).app"),
            securityScopedBookmark: nil,
            origin: .system,
            availability: .available,
            selectorOrder: index
        )
    }
}
