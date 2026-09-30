import AppKit
import PrismCore
import SwiftUI

@MainActor
final class AppSelectorNavigationHandler: SelectorNavigationHandling {
    private weak var environment: AppEnvironment?
    private let mainWindowOpening: MainWindowOpening

    init(environment: AppEnvironment, mainWindowOpening: MainWindowOpening) {
        self.environment = environment
        self.mainWindowOpening = mainWindowOpening
    }

    func openBrowserManagement() {
        environment?.stageBrowserManagement()
        mainWindowOpening.open(route: .settings)
    }

    func openRuleEditor(prefill: SelectorRulePrefill) {
        environment?.stageSelectorRulePrefill(prefill)
        mainWindowOpening.open(route: .rules)
    }
}

@MainActor
final class SelectorSession {
    let requestID: UUID
    let content: AnyView
    private var monitoringTask: Task<Void, Never>?
    private var cancelAction: (@MainActor () -> Void)?

    init(
        requestID: UUID,
        content: AnyView,
        monitoringTask: Task<Void, Never>? = nil,
        cancelAction: @escaping @MainActor () -> Void = {}
    ) {
        self.requestID = requestID
        self.content = content
        self.monitoringTask = monitoringTask
        self.cancelAction = cancelAction
    }

    func cancel() {
        monitoringTask?.cancel()
        monitoringTask = nil
        cancelAction?()
        cancelAction = nil
    }

    deinit {
        monitoringTask?.cancel()
        if let cancelAction {
            Task { @MainActor in
                cancelAction()
            }
        }
    }
}

@MainActor
protocol SelectorContentProviding: AnyObject {
    func makeSession(request: LinkRequest, context: SelectorPresentationContext) -> SelectorSession
}

@MainActor
final class SelectorSessionFactory: SelectorContentProviding {
    let browserCatalog: any BrowserCataloging
    let routingCoordinator: any LinkRoutingCoordinating
    let pendingCountProvider: RecoveryQueuePendingCountProvider
    let sourceManifest: SourceSupportManifest
    let operatingSystemVersion: OperatingSystemVersion

    private let navigationHandler: any SelectorNavigationHandling
    private let iconProvider: any ApplicationIconProviding

    init(
        browserCatalog: any BrowserCataloging,
        routingCoordinator: any LinkRoutingCoordinating,
        pendingCountProvider: RecoveryQueuePendingCountProvider,
        navigationHandler: any SelectorNavigationHandling,
        iconProvider: any ApplicationIconProviding,
        sourceManifest: SourceSupportManifest,
        operatingSystemVersion: OperatingSystemVersion
    ) {
        self.browserCatalog = browserCatalog
        self.routingCoordinator = routingCoordinator
        self.pendingCountProvider = pendingCountProvider
        self.navigationHandler = navigationHandler
        self.iconProvider = iconProvider
        self.sourceManifest = sourceManifest
        self.operatingSystemVersion = operatingSystemVersion
    }

    func makeSession(request: LinkRequest, context: SelectorPresentationContext) -> SelectorSession {
        let model = SelectorViewModel(
            request: request,
            context: context,
            browserCatalog: browserCatalog,
            routingCoordinator: routingCoordinator,
            pendingCountProvider: pendingCountProvider,
            navigationHandler: navigationHandler,
            eligibleSourceBundleIDs: sourceManifest.eligibleBundleIDs(for: operatingSystemVersion)
        )
        let monitoringTask = model.startPendingCountMonitoring()
        return SelectorSession(
            requestID: request.id,
            content: AnyView(SelectorView(model: model, iconProvider: iconProvider)),
            monitoringTask: monitoringTask,
            cancelAction: { [weak model] in
                model?.stopPendingCountMonitoring()
            }
        )
    }
}
