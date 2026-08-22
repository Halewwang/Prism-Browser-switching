import AppKit
import PrismCore
import SwiftUI

enum OnboardingActionID: String, CaseIterable, Equatable, Hashable {
    case continueFromWelcome
    case setAsDefault
    case refreshHandlers
    case openDefaultAppsSettings
    case finishLinkHandlingLater
    case rescanBrowsers
    case addCustomBrowser
    case openApplicationsFolder
    case startTestLink
    case retryTestLink
    case retryCompletionSave
    case finishTestLater
}

enum OnboardingActionEmphasis: Equatable {
    case primary
    case secondary
    case quiet
}

struct OnboardingActionPresentation: Equatable, Identifiable {
    let id: OnboardingActionID
    let title: String
    let accessibilityIdentifier: String
    let accessibilityHint: String
    let emphasis: OnboardingActionEmphasis
    let isEnabled: Bool
}

struct OnboardingStatusRowPresentation: Equatable, Identifiable {
    let id: String
    let title: String
    let statusText: String
    let iconSystemName: String
    let accessibilityIdentifier: String

    var accessibilityLabel: String {
        "\(title): \(statusText)"
    }
}

struct OnboardingBrowserRowPresentation: Equatable, Identifiable {
    let id: String
    let name: String
    let location: String
    let statusText: String
    let accessibilityIdentifier: String

    var accessibilityLabel: String {
        "\(name), \(statusText), \(location)"
    }
}

struct OnboardingAlertPresentation: Equatable {
    let iconSystemName: String
    let title: String
    let message: String
    let accessibilityIdentifier: String
}

struct OnboardingViewPresentation: Equatable {
    let step: OnboardingStep
    let progressText: String
    let progressValue: Double
    let accessibilityIdentifier: String
    let title: String
    let message: String
    let statusRows: [OnboardingStatusRowPresentation]
    let browserRows: [OnboardingBrowserRowPresentation]
    let alert: OnboardingAlertPresentation?
    let activityText: String?
    let actions: [OnboardingActionPresentation]

    var preferredFocusedActionID: OnboardingActionID? {
        actions.first(where: \.isEnabled)?.id
    }

    init(
        step: OnboardingStep,
        alert: OnboardingAlert?,
        httpHandlerIsActive: Bool,
        httpsHandlerIsActive: Bool,
        usableBrowsers: [BrowserDescriptor],
        isTestLinkInProgress: Bool,
        isTestLinkPreparing: Bool = false,
        isRefreshingHandler: Bool = false,
        isScanningBrowsers: Bool = false,
        handlerStatusIsKnown: Bool = true,
        isCheckingHandlers: Bool = false,
        testLinkWasAccepted: Bool = false,
        completionSaveIsPending: Bool = false
    ) {
        self.step = step
        progressText = "Step \(step.rawValue + 1) of \(OnboardingStep.allCases.count)"
        progressValue = Double(step.rawValue + 1) / Double(OnboardingStep.allCases.count)
        self.alert = alert.map(Self.alertPresentation)

        switch step {
        case .welcome:
            accessibilityIdentifier = "onboarding.step.welcome"
            title = "Your links, in the right browser"
            message = "Prism sends each web link to the browser you choose. Your rules and history stay on this Mac."
            statusRows = []
            browserRows = []
            activityText = nil
            actions = [
                Self.action(
                    .continueFromWelcome,
                    title: "Continue",
                    identifier: "onboarding.welcome.continue",
                    hint: "Continue to link handling",
                    emphasis: .primary
                ),
            ]

        case .linkHandling:
            let handlerIsChecking = isRefreshingHandler || isCheckingHandlers
            accessibilityIdentifier = "onboarding.step.linkHandling"
            title = "Let Prism handle web links"
            message = "macOS manages HTTP and HTTPS separately. Prism checks both before continuing."
            statusRows = [
                Self.handlerStatus(
                    id: "http",
                    title: "HTTP links",
                    isActive: httpHandlerIsActive,
                    isKnown: handlerStatusIsKnown,
                    isChecking: handlerIsChecking
                ),
                Self.handlerStatus(
                    id: "https",
                    title: "HTTPS links",
                    isActive: httpsHandlerIsActive,
                    isKnown: handlerStatusIsKnown,
                    isChecking: handlerIsChecking
                ),
            ]
            browserRows = []
            activityText = handlerIsChecking ? "Checking HTTP and HTTPS handlers…" : nil
            var linkActions = [
                Self.action(
                    .setAsDefault,
                    title: "Set as Default",
                    identifier: "onboarding.linkHandling.setDefault",
                    hint: "Ask macOS to use Prism for HTTP and HTTPS links",
                    emphasis: .primary,
                    isEnabled: !handlerIsChecking
                ),
                Self.action(
                    .refreshHandlers,
                    title: "Refresh",
                    identifier: "onboarding.linkHandling.refresh",
                    hint: "Check the current HTTP and HTTPS handlers again",
                    emphasis: .secondary,
                    isEnabled: !handlerIsChecking
                ),
            ]
            if alert == .defaultHandlerIncomplete || alert == .defaultHandlerUnavailable {
                linkActions.append(
                    Self.action(
                        .openDefaultAppsSettings,
                        title: "Open System Settings",
                        identifier: "onboarding.linkHandling.openSettings",
                        hint: "Open the macOS settings for default applications",
                        emphasis: .secondary,
                        isEnabled: !handlerIsChecking
                    )
                )
            }
            linkActions.append(
                Self.action(
                    .finishLinkHandlingLater,
                    title: "Finish Later",
                    identifier: "onboarding.linkHandling.finishLater",
                    hint: "Continue setup without changing the link handler",
                    emphasis: .quiet,
                    isEnabled: !handlerIsChecking
                )
            )
            actions = linkActions

        case .browsers:
            accessibilityIdentifier = "onboarding.step.browsers"
            title = "Choose available browsers"
            message = "Prism needs at least one usable browser before you can test a link."
            statusRows = []
            browserRows = usableBrowsers
                .filter { $0.availability == .available }
                .map {
                    OnboardingBrowserRowPresentation(
                        id: $0.id.rawValue,
                        name: $0.displayName,
                        location: $0.applicationURL.path,
                        statusText: "Ready",
                        accessibilityIdentifier: "onboarding.browsers.browser.\($0.id.rawValue)"
                    )
                }
            activityText = isScanningBrowsers ? "Looking for installed browsers…" : nil
            if browserRows.isEmpty {
                actions = [
                    Self.action(
                        .rescanBrowsers,
                        title: "Rescan",
                        identifier: "onboarding.browsers.rescan",
                        hint: "Look for installed browsers again",
                        emphasis: .primary,
                        isEnabled: !isScanningBrowsers
                    ),
                    Self.action(
                        .addCustomBrowser,
                        title: "Add Custom Browser",
                        identifier: "onboarding.browsers.addCustomBrowser",
                        hint: "Choose another browser application",
                        emphasis: .secondary,
                        isEnabled: !isScanningBrowsers
                    ),
                    Self.action(
                        .openApplicationsFolder,
                        title: "Open Applications Folder",
                        identifier: "onboarding.browsers.openApplicationsFolder",
                        hint: "Show installed applications in Finder",
                        emphasis: .secondary,
                        isEnabled: !isScanningBrowsers
                    ),
                ]
            } else if alert == .settingsNotSaved {
                actions = [
                    Self.action(
                        .rescanBrowsers,
                        title: "Retry Saving Setup",
                        identifier: "onboarding.browsers.retrySave",
                        hint: "Retry saving the browser setup without changing the selected browsers",
                        emphasis: .primary,
                        isEnabled: !isScanningBrowsers
                    ),
                ]
            } else {
                actions = []
            }

        case .testLink:
            accessibilityIdentifier = "onboarding.step.testLink"
            title = "Try Prism with a test link"
            message = "Prism will send a test link through the real selector and confirm that a browser accepts it."
            statusRows = []
            browserRows = []
            if isTestLinkPreparing {
                activityText = "Preparing the test link…"
            } else if isTestLinkInProgress {
                activityText = "Waiting for the browser to accept the test link…"
            } else {
                activityText = nil
            }
            if completionSaveIsPending || testLinkWasAccepted {
                actions = [
                    Self.action(
                        .retryCompletionSave,
                        title: "Retry Saving Setup",
                        identifier: "onboarding.testLink.retryCompletionSave",
                        hint: "Save the completed setup without opening another test link",
                        emphasis: .primary
                    ),
                ]
            } else if isTestLinkInProgress {
                actions = [
                    Self.action(
                        .finishTestLater,
                        title: "Finish Later",
                        identifier: "onboarding.testLink.finishLater",
                        hint: "Cancel the current test and finish setup without confirming it",
                        emphasis: .quiet,
                        isEnabled: !isTestLinkPreparing
                    ),
                ]
            } else {
                let retry = alert == .testLinkFailed
                actions = [
                    Self.action(
                        retry ? .retryTestLink : .startTestLink,
                        title: retry ? "Retry Test Link" : "Test Link",
                        identifier: retry ? "onboarding.testLink.retry" : "onboarding.testLink.start",
                        hint: "Open the real browser selector for a test link",
                        emphasis: .primary
                    ),
                    Self.action(
                        .finishTestLater,
                        title: "Finish Later",
                        identifier: "onboarding.testLink.finishLater",
                        hint: "Finish setup without confirming the test link",
                        emphasis: .quiet
                    ),
                ]
            }
        }
    }

    var visibleText: [String] {
        [progressText, title, message, activityText]
            .compactMap { $0 }
            + statusRows.flatMap { [$0.title, $0.statusText] }
            + browserRows.flatMap { [$0.name, $0.location, $0.statusText] }
            + [alert?.title, alert?.message].compactMap { $0 }
            + actions.map(\.title)
    }

    private static func action(
        _ id: OnboardingActionID,
        title: String,
        identifier: String,
        hint: String,
        emphasis: OnboardingActionEmphasis,
        isEnabled: Bool = true
    ) -> OnboardingActionPresentation {
        OnboardingActionPresentation(
            id: id,
            title: title,
            accessibilityIdentifier: identifier,
            accessibilityHint: hint,
            emphasis: emphasis,
            isEnabled: isEnabled
        )
    }

    private static func handlerStatus(
        id: String,
        title: String,
        isActive: Bool,
        isKnown: Bool,
        isChecking: Bool
    ) -> OnboardingStatusRowPresentation {
        let statusText: String
        let iconSystemName: String
        if isChecking {
            statusText = "Checking…"
            iconSystemName = "arrow.triangle.2.circlepath.circle.fill"
        } else if !isKnown {
            statusText = "Unavailable"
            iconSystemName = "questionmark.circle.fill"
        } else if isActive {
            statusText = "Prism is active"
            iconSystemName = "checkmark.circle.fill"
        } else {
            statusText = "Needs attention"
            iconSystemName = "exclamationmark.circle.fill"
        }
        return OnboardingStatusRowPresentation(
            id: id,
            title: title,
            statusText: statusText,
            iconSystemName: iconSystemName,
            accessibilityIdentifier: "onboarding.linkHandling.\(id)Status"
        )
    }

    private static func alertPresentation(_ alert: OnboardingAlert) -> OnboardingAlertPresentation {
        let iconSystemName: String
        let title: String
        let message: String
        switch alert {
        case .defaultHandlerIncomplete:
            iconSystemName = "exclamationmark.triangle.fill"
            title = "Prism is not handling every web link"
            message = "HTTP and HTTPS must both use Prism. Try again or review the default application in System Settings."
        case .defaultHandlerUnavailable:
            iconSystemName = "questionmark.circle.fill"
            title = "Link handling could not be checked"
            message = "Refresh the status, or open System Settings and confirm the default application manually."
        case .noUsableBrowser:
            iconSystemName = "safari.fill"
            title = "No usable browsers were found"
            message = "Install a browser, add one manually, or rescan after moving it into Applications."
        case .browserScanFailed:
            iconSystemName = "exclamationmark.triangle.fill"
            title = "Browsers could not be scanned"
            message = "Prism could not read the installed applications. Try the scan again."
        case .customBrowserFailed:
            iconSystemName = "exclamationmark.triangle.fill"
            title = "The browser could not be added"
            message = "Choose a valid browser application, or use Rescan to look for installed browsers."
        case .settingsNotSaved:
            iconSystemName = "externaldrive.badge.exclamationmark"
            title = "Your changes could not be saved"
            message = "Keep Prism open and try again. Setup is not complete until the change is saved."
        case .testLinkFailed:
            iconSystemName = "arrow.clockwise.circle.fill"
            title = "The test link did not finish"
            message = "Retry the test, or choose Finish Later to complete setup without a confirmed browser handoff."
        case .testLinkCancellationFailed:
            iconSystemName = "externaldrive.badge.exclamationmark"
            title = "The test link could not be cancelled"
            message = "Prism kept the current test link so it is not duplicated. Try Finish Later again."
        }
        return OnboardingAlertPresentation(
            iconSystemName: iconSystemName,
            title: title,
            message: message,
            accessibilityIdentifier: "onboarding.alert"
        )
    }
}

enum OnboardingExternalAction: String, CaseIterable, Equatable {
    case addCustomBrowser
    case openDefaultAppsSettings
    case openApplicationsFolder
}

enum OnboardingCustomBrowserResult: Equatable, Sendable {
    case added
    case cancelled
    case failed
}

@MainActor
struct OnboardingViewActions {
    private let addCustomBrowserAction: @MainActor () async -> OnboardingCustomBrowserResult
    private let openDefaultAppsSettings: () -> Void
    private let openApplicationsFolder: () -> Void

    init(
        addCustomBrowser: @escaping @MainActor () async -> OnboardingCustomBrowserResult,
        openDefaultAppsSettings: @escaping () -> Void,
        openApplicationsFolder: @escaping () -> Void
    ) {
        addCustomBrowserAction = addCustomBrowser
        self.openDefaultAppsSettings = openDefaultAppsSettings
        self.openApplicationsFolder = openApplicationsFolder
    }

    func addCustomBrowser() async -> OnboardingCustomBrowserResult {
        await addCustomBrowserAction()
    }

    func openSettings() {
        openDefaultAppsSettings()
    }

    func openApplications() {
        openApplicationsFolder()
    }
}

@MainActor
struct OnboardingViewInteractions {
    let model: OnboardingViewModel
    let actions: OnboardingViewActions

    func addCustomBrowser() async {
        switch await actions.addCustomBrowser() {
        case .added:
            await model.advanceFromBrowserScan()
        case .failed:
            model.reportCustomBrowserFailure()
        case .cancelled:
            break
        }
    }
}

@MainActor
struct OnboardingView: View {
    @State private var model: OnboardingViewModel
    let actions: OnboardingViewActions

    @State private var isScanningBrowsers = false
    @State private var isStartingTestLink = false
    @FocusState private var focusedAction: OnboardingActionID?
    private let fillsMinimumWindowSize: Bool

    init(
        model: OnboardingViewModel,
        actions: OnboardingViewActions,
        fillsMinimumWindowSize: Bool = true
    ) {
        _model = State(initialValue: model)
        self.actions = actions
        self.fillsMinimumWindowSize = fillsMinimumWindowSize
    }

    var presentation: OnboardingViewPresentation {
        OnboardingViewPresentation(
            step: model.step,
            alert: model.alert,
            httpHandlerIsActive: model.httpHandlerIsActive,
            httpsHandlerIsActive: model.httpsHandlerIsActive,
            usableBrowsers: model.usableBrowsers,
            isTestLinkInProgress: model.isTestLinkInProgress || isStartingTestLink,
            isTestLinkPreparing: model.isTestLinkPreparing,
            isScanningBrowsers: isScanningBrowsers,
            handlerStatusIsKnown: model.handlerStatusIsKnown,
            isCheckingHandlers: model.isCheckingHandlers,
            testLinkWasAccepted: model.testLinkWasAccepted,
            completionSaveIsPending: model.completionSaveIsPending
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            progressHeader
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    titleBlock
                    stepContent
                    if let alert = presentation.alert {
                        alertView(alert)
                    }
                    if let activityText = presentation.activityText {
                        activityView(activityText)
                    }
                }
                .frame(maxWidth: 600, alignment: .leading)
                .padding(.horizontal, 48)
                .padding(.vertical, 34)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            Divider()
            actionBar
        }
        .frame(
            minWidth: fillsMinimumWindowSize ? 760 : nil,
            minHeight: fillsMinimumWindowSize ? 520 : nil
        )
        .background(Color(nsColor: .windowBackgroundColor))
        .task(id: presentation.preferredFocusedActionID) {
            focusedAction = presentation.preferredFocusedActionID
        }
    }

    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Prism Setup")
                    .font(.headline)
                Spacer()
                Text(presentation.progressText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("onboarding.progress.label")
            }
            ProgressView(value: presentation.progressValue)
                .progressViewStyle(.linear)
                .tint(.accentColor)
                .accessibilityLabel("Setup progress")
                .accessibilityValue(presentation.progressText)
                .accessibilityIdentifier("onboarding.progress")
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedStringKey(presentation.title))
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(presentation.accessibilityIdentifier)
            Text(LocalizedStringKey(presentation.message))
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch presentation.step {
        case .welcome:
            welcomeContent
        case .linkHandling:
            handlerContent
        case .browsers:
            browserContent
        case .testLink:
            testLinkContent
        }
    }

    private var welcomeContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            featureRow(
                icon: "arrow.triangle.branch",
                title: "Route with clarity",
                message: "Choose a browser each time or let a rule decide."
            )
            featureRow(
                icon: "lock.shield",
                title: "Private by design",
                message: "Rules and link history remain on your Mac."
            )
        }
        .accessibilityElement(children: .contain)
    }

    private var handlerContent: some View {
        VStack(spacing: 10) {
            ForEach(presentation.statusRows) { row in
                HStack(spacing: 12) {
                    Image(systemName: row.iconSystemName)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 24)
                        .accessibilityHidden(true)
                    Text(LocalizedStringKey(row.title))
                        .font(.body.weight(.medium))
                    Spacer()
                    Text(LocalizedStringKey(row.statusText))
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(row.accessibilityLabel)
                .accessibilityIdentifier(row.accessibilityIdentifier)
            }
        }
    }

    @ViewBuilder
    private var browserContent: some View {
        if presentation.browserRows.isEmpty {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "safari")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("No browsers are ready yet")
                        .font(.body.weight(.medium))
                    Text("Rescan installed applications or add a browser manually.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("onboarding.browsers.empty")
        } else {
            VStack(spacing: 0) {
                ForEach(Array(presentation.browserRows.enumerated()), id: \.element.id) { index, browser in
                    if index > 0 {
                        Divider()
                    }
                    HStack(spacing: 12) {
                        Image(systemName: "safari.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .frame(width: 24)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(browser.name)
                                .font(.body.weight(.medium))
                            Text(browser.location)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Label(browser.statusText, systemImage: "checkmark.circle.fill")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(browser.accessibilityLabel)
                    .accessibilityIdentifier(browser.accessibilityIdentifier)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            }
        }
    }

    private var testLinkContent: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "link.circle")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text("The selector will open for a safe example link")
                    .font(.body.weight(.medium))
                Text("Choose a browser in the selector. Prism only completes the test after macOS accepts the handoff.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("onboarding.testLink.explanation")
    }

    private func featureRow(icon: String, title: String, message: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func alertView(_ alert: OnboardingAlertPresentation) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: alert.iconSystemName)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(alert.title))
                    .font(.body.weight(.semibold))
                Text(LocalizedStringKey(alert.message))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(alert.accessibilityIdentifier)
    }

    private func activityView(_ text: String) -> some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(LocalizedStringKey(text))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
        .accessibilityIdentifier("onboarding.activity")
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)
            ForEach(presentation.actions) { action in
                actionButton(action)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private func actionButton(_ action: OnboardingActionPresentation) -> some View {
        switch action.emphasis {
        case .primary:
            baseButton(action)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        case .secondary:
            baseButton(action)
                .buttonStyle(.bordered)
        case .quiet:
            baseButton(action)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    private func baseButton(_ action: OnboardingActionPresentation) -> some View {
        Button(LocalizedStringKey(action.title)) {
            perform(action.id)
        }
        .disabled(!action.isEnabled)
        .focused($focusedAction, equals: action.id)
        .accessibilityHint(action.accessibilityHint)
        .accessibilityIdentifier(action.accessibilityIdentifier)
    }

    private func perform(_ action: OnboardingActionID) {
        switch action {
        case .continueFromWelcome:
            Task { await model.advanceFromWelcome() }
        case .setAsDefault:
            Task { await model.setPrismAsDefault() }
        case .refreshHandlers:
            Task { await model.advanceFromLinkHandling() }
        case .openDefaultAppsSettings:
            actions.openSettings()
        case .finishLinkHandlingLater:
            model.finishLater()
        case .rescanBrowsers:
            scanBrowsers()
        case .addCustomBrowser:
            addCustomBrowser()
        case .openApplicationsFolder:
            actions.openApplications()
        case .startTestLink, .retryTestLink:
            startTestLink()
        case .retryCompletionSave:
            Task { await model.retryCompletionSave() }
        case .finishTestLater:
            Task { await model.finishTestLater() }
        }
    }

    private func scanBrowsers() {
        guard !isScanningBrowsers else { return }
        Task { @MainActor in
            isScanningBrowsers = true
            defer { isScanningBrowsers = false }
            await model.advanceFromBrowserScan()
        }
    }

    private func addCustomBrowser() {
        guard !isScanningBrowsers else { return }
        Task { @MainActor in
            isScanningBrowsers = true
            defer { isScanningBrowsers = false }
            await OnboardingViewInteractions(model: model, actions: actions).addCustomBrowser()
        }
    }

    private func startTestLink() {
        guard !isStartingTestLink, !model.isTestLinkInProgress else { return }
        Task { @MainActor in
            isStartingTestLink = true
            defer { isStartingTestLink = false }
            await model.beginTestLink()
        }
    }

}
