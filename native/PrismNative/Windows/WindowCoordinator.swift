import AppKit
import PrismCore
import SwiftUI

@MainActor
final class MainWindowOpening {
    typealias OpenWindow = @MainActor (_ id: String, _ value: MainWindowIdentity) -> Void

    private let updateRoute: @MainActor (AppRoute) -> Void
    private var openWindow: OpenWindow?

    init(updateRoute: @escaping @MainActor (AppRoute) -> Void) {
        self.updateRoute = updateRoute
    }

    func register(openWindow: @escaping OpenWindow) {
        self.openWindow = openWindow
    }

    func open(route: AppRoute) {
        updateRoute(route)
        openWindow?("main", .singleton)
    }
}

@MainActor
final class WindowCoordinator: LinkSelectionPresenting {
    typealias ContentFactory = @MainActor (LinkRequest, SelectorPresentationContext) -> AnyView

    private let mainWindowOpening: MainWindowOpening
    private let panelController: any SelectorPanelControlling
    private let positioner: SelectorPositioner
    private let pointerLocation: @MainActor () -> CGPoint
    private let visibleFrames: @MainActor () -> [CGRect]
    private let contentFactory: ContentFactory
    private(set) var activeRequestID: UUID?

    init(
        mainWindowOpening: MainWindowOpening,
        panelController: any SelectorPanelControlling = SelectorPanelController(),
        positioner: SelectorPositioner = SelectorPositioner(),
        pointerLocation: @escaping @MainActor () -> CGPoint = { NSEvent.mouseLocation },
        visibleFrames: @escaping @MainActor () -> [CGRect] = { NSScreen.screens.map(\.visibleFrame) },
        contentFactory: @escaping ContentFactory = { _, _ in
            AnyView(
                Text("Choose a browser")
                    .frame(width: SelectorPanel.contentSize.width, height: SelectorPanel.contentSize.height)
            )
        }
    ) {
        self.mainWindowOpening = mainWindowOpening
        self.panelController = panelController
        self.positioner = positioner
        self.pointerLocation = pointerLocation
        self.visibleFrames = visibleFrames
        self.contentFactory = contentFactory
    }

    func present(_ request: LinkRequest, context: SelectorPresentationContext) {
        activeRequestID = request.id
        let origin = positioner.origin(
            panelSize: SelectorPanel.contentSize,
            pointer: pointerLocation(),
            visibleFrames: visibleFrames()
        )
        panelController.present(content: contentFactory(request, context), at: origin)
    }

    func dismiss(requestID: UUID) {
        guard activeRequestID == requestID else { return }
        hideSelector()
    }

    func hideSelector() {
        activeRequestID = nil
        panelController.hide()
    }

    func showMainWindow(route: AppRoute) {
        mainWindowOpening.open(route: route)
    }
}
