import AppKit
import PrismCore
import SwiftUI

struct SelectorView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    @State private var model: SelectorViewModel
    @State private var scrollPosition = ScrollPosition(idType: BrowserID.self)
    @State private var scrollOffset: CGFloat = 0
    @State private var showsFailureHelp = false
    @FocusState private var hasKeyboardFocus: Bool

    private let iconProvider: any ApplicationIconProviding

    init(model: SelectorViewModel, iconProvider: any ApplicationIconProviding) {
        _model = State(initialValue: model)
        self.iconProvider = iconProvider
    }

    var body: some View {
        VStack(spacing: 5) {
            header
                .frame(height: SelectorMetrics.headerHeight)
            browserViewport
                .frame(width: SelectorMetrics.viewportSize.width, height: SelectorMetrics.viewportSize.height)
                .background(SelectorPalette.field)
                .clipShape(RoundedRectangle(cornerRadius: SelectorMetrics.cardRadius))
        }
        .padding(.top, SelectorMetrics.outerInset)
        .padding(.leading, SelectorMetrics.outerInset)
        .padding(.trailing, SelectorMetrics.outerTrailingInset)
        .padding(.bottom, 6)
        .frame(width: SelectorMetrics.panelSize.width, height: SelectorMetrics.panelSize.height)
        .background(SelectorPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: SelectorMetrics.outerRadius))
        .focusable()
        .focused($hasKeyboardFocus)
        .focusEffectDisabled()
        .onAppear {
            hasKeyboardFocus = true
        }
        .onKeyPress(.leftArrow) {
            model.selectPrevious()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            model.selectNext()
            return .handled
        }
        .onKeyPress(.return) {
            Task { await model.activateSelected() }
            return .handled
        }
        .onKeyPress(.escape) {
            Task { await model.cancel() }
            return .handled
        }
        .onKeyPress(characters: .decimalDigits) { keyPress in
            guard let character = keyPress.characters.first,
                  let number = character.wholeNumberValue,
                  hasKeyboardFocus,
                  model.canActivateShortcut(number)
            else { return .ignored }
            Task { await model.activateShortcut(number) }
            return .handled
        }
        .onChange(of: model.revealBrowserID) { _, browserID in
            guard let browserID else { return }
            reveal(browserID)
        }
        .task {
            await model.prepareForPresentation()
        }
    }

    private var header: some View {
        HStack(spacing: SelectorMetrics.headerGap) {
            sourceField
                .frame(width: SelectorMetrics.sourceWidth)
            urlField
                .frame(maxWidth: .infinity)
            Button {
                Task { await model.cancel() }
            } label: {
                Text(String(localized: "selector.cancel", defaultValue: "Cancel"))
                    .foregroundStyle(SelectorPalette.primaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(.plain)
            .frame(width: SelectorMetrics.cancelWidth)
            .selectorHeaderField(contrast: contrast)
            .accessibilityIdentifier("selector.cancel")
        }
    }

    private var sourceField: some View {
        HStack(spacing: 7) {
            Image(nsImage: sourceIcon)
                .resizable()
                .scaledToFit()
                .frame(width: 19, height: 19)
                .accessibilityHidden(true)
            Text(model.source.displayName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SelectorPalette.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 9)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .selectorHeaderField(contrast: contrast)
        .overlay(alignment: .topTrailing) {
            if let badge = model.pendingBadgeText {
                Text(badge)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(SelectorPalette.badgeForeground)
                    .frame(minWidth: 14, minHeight: 14)
                    .background(SelectorPalette.badgeBackground, in: Circle())
                    .offset(x: 4, y: -4)
                    .accessibilityLabel(model.pendingAccessibilityValue ?? "")
                    .accessibilityIdentifier("selector.pendingBadge")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "selector.source", defaultValue: "Source"))
        .accessibilityValue(model.pendingAccessibilityValue.map {
            "\(model.source.displayName), \($0)"
        } ?? model.source.displayName)
        .accessibilityIdentifier("selector.source")
    }

    private var urlField: some View {
        HStack(spacing: 7) {
            if model.accessibleFailureMessage != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(SelectorPalette.error)
                    .accessibilityHidden(true)
            }
            Text(model.url.absoluteString)
                .font(.system(size: 12))
                .foregroundStyle(SelectorPalette.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            if let failureMessage = model.accessibleFailureMessage {
                Button {
                    showsFailureHelp.toggle()
                } label: {
                    Image(systemName: "questionmark.circle")
                        .accessibilityLabel(String(localized: "selector.failure.help", defaultValue: "Failure details"))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showsFailureHelp) {
                    Text(failureMessage)
                        .font(.callout)
                        .padding()
                        .frame(width: 260)
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .selectorHeaderField(contrast: contrast, failure: model.accessibleFailureMessage != nil)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "selector.url", defaultValue: "Link"))
        .accessibilityValue(model.accessibleFailureMessage ?? model.url.absoluteString)
        .accessibilityIdentifier("selector.url")
    }

    @ViewBuilder
    private var browserViewport: some View {
        if model.browsers.isEmpty {
            SelectorEmptyStateView(
                isLoading: model.isLoading,
                failureMessage: model.scanFailureMessage,
                onRescan: { Task { await model.rescan() } },
                onOpenBrowserManagement: model.openBrowserManagement
            )
        } else {
            VStack(spacing: 0) {
                if model.presentationContext.isRecovery {
                    recoveryStatusBar
                        .frame(height: SelectorMetrics.recoveryStatusHeight)
                }
                browserScrollView
                    .frame(height: browserStripHeight)
            }
        }
    }

    private var browserScrollView: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: SelectorMetrics.itemGap(browserCount: model.browsers.count)) {
                ForEach(Array(model.browsers.enumerated()), id: \.element.id) { index, browser in
                    browserChoice(browser: browser, index: index)
                        .id(browser.id)
                }
            }
            .scrollTargetLayout()
            .padding(.leading, SelectorMetrics.viewportLeadingInset)
            .padding(.trailing, SelectorMetrics.viewportTrailingInset)
        }
        .scrollIndicators(.hidden)
        .scrollPosition($scrollPosition)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.x
        } action: { _, newValue in
            scrollOffset = SelectorMetrics.clampedOffset(newValue, browserCount: model.browsers.count)
        }
        .overlay {
            HorizontalScrollBridge(
                browserHitTargets: browserHitTargets,
                currentOffset: scrollOffset,
                onHorizontalWheel: { points in setOffset(scrollOffset + points) },
                onDrag: setOffset,
                onActivateBrowser: { rawID in
                    Task { await model.activateBrowser(id: BrowserID(rawID)) }
                }
            )
        }
        .accessibilityIdentifier("selector.browserViewport")
    }

    private func browserChoice(browser: BrowserDescriptor, index: Int) -> some View {
        BrowserChoiceView(
            browser: browser,
            icon: iconProvider.icon(for: browser.applicationURL),
            width: SelectorMetrics.itemWidth(browserCount: model.browsers.count),
            height: browserItemHeight,
            shortcut: model.shortcut(forBrowserAt: index),
            isSelected: model.selectedIndex == index,
            isFailed: model.failedBrowserID == browser.id,
            accessibilityLabel: model.browserAccessibilityLabel(at: index),
            onActivate: {
                Task { await model.activateBrowser(id: browser.id) }
            }
        )
        .contextMenu {
            if model.canCreateDomainRule {
                Button(String(
                    localized: "selector.rule.domain",
                    defaultValue: "Always open this domain in \(browser.displayName)"
                )) {
                    model.openDomainRule(browserID: browser.id)
                }
            }
            if model.canCreateSourceRule {
                Button(String(
                    localized: "selector.rule.source",
                    defaultValue: "Always open links from \(model.source.displayName) in \(browser.displayName)"
                )) {
                    model.openSourceRule(browserID: browser.id)
                }
            }
        }
    }

    private var recoveryStatusBar: some View {
        HStack(spacing: 8) {
            Text(model.accessibleFailureMessage ?? "")
                .font(.caption2)
                .foregroundStyle(SelectorPalette.secondaryText)
                .lineLimit(1)
            Spacer(minLength: 0)
            if !model.requiresExplicitRecoveryBrowser {
                Button(String(localized: "selector.retry", defaultValue: "Retry")) {
                    Task { await model.retryRecovery() }
                }
            }
            if model.canMarkCompleted {
                Button(String(localized: "selector.markCompleted", defaultValue: "Mark Completed")) {
                    Task { await model.markCompleted() }
                }
            }
            Button(String(localized: "selector.cancel", defaultValue: "Cancel")) {
                Task { await model.cancel() }
            }
        }
        .controlSize(.mini)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("selector.recovery")
    }

    private var sourceIcon: NSImage {
        guard let bundleIdentifier = model.source.bundleIdentifier,
              let icon = iconProvider.icon(bundleIdentifier: bundleIdentifier)
        else {
            return NSImage(systemSymbolName: "link", accessibilityDescription: nil) ?? NSImage()
        }
        return icon
    }

    private func setOffset(_ proposed: CGFloat) {
        let clamped = SelectorMetrics.clampedOffset(proposed, browserCount: model.browsers.count)
        scrollPosition.scrollTo(x: clamped)
        scrollOffset = clamped
    }

    private func reveal(_ browserID: BrowserID) {
        guard let index = model.browsers.firstIndex(where: { $0.id == browserID }) else { return }
        let offset = SelectorMetrics.revealOffset(
            browserIndex: index,
            browserCount: model.browsers.count,
            currentOffset: scrollOffset
        )
        if reduceMotion {
            setOffset(offset)
        } else {
            withAnimation(.snappy(duration: 0.18)) {
                setOffset(offset)
            }
        }
    }

    private var browserHitTargets: [HorizontalScrollBridge.BrowserHitTarget] {
        let count = model.browsers.count
        let width = SelectorMetrics.itemWidth(browserCount: count)
        let gap = SelectorMetrics.itemGap(browserCount: count)
        return model.browsers.enumerated().map { index, browser in
            HorizontalScrollBridge.BrowserHitTarget(
                id: browser.id.rawValue,
                frame: CGRect(
                    x: SelectorMetrics.viewportLeadingInset + CGFloat(index) * (width + gap),
                    y: 6,
                    width: width,
                    height: browserItemHeight
                )
            )
        }
    }

    private var browserStripHeight: CGFloat {
        model.presentationContext.isRecovery
            ? SelectorMetrics.recoveryStripHeight
            : SelectorMetrics.viewportSize.height
    }

    private var browserItemHeight: CGFloat {
        model.presentationContext.isRecovery
            ? SelectorMetrics.recoveryItemHeight
            : SelectorMetrics.itemHeight
    }
}

private extension SelectorPresentationContext {
    var isRecovery: Bool {
        switch self {
        case .outcomeUnknown, .storageUnavailable:
            true
        case .normal, .launchFailed, .noAvailableBrowsers:
            false
        }
    }
}

private extension View {
    func selectorHeaderField(contrast: ColorSchemeContrast, failure: Bool = false) -> some View {
        background(SelectorPalette.field, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        failure
                            ? SelectorPalette.error
                            : (contrast == .increased
                                ? SelectorPalette.highContrastBorder
                                : SelectorPalette.border),
                        lineWidth: contrast == .increased ? 1 : 0.5
                    )
            }
    }
}
