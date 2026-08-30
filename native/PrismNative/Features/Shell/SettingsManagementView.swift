import PrismCore
import SwiftUI

struct SettingsManagementView: View {
    @Environment(AppEnvironment.self) private var environment

    let browserCatalog: any BrowserCataloging
    let openDefaultAppsSettings: () -> Void
    let restart: () -> Void

    @State private var browsers: [BrowserDescriptor] = []
    @State private var defaultHandlerState: DefaultHandlerState?
    @State private var loginItemState: LoginItemState?
    @State private var isUpdatingDefaultHandler = false
    @State private var isUpdatingLoginItem = false
    @State private var actionMessage: String?
    @State private var languageRestartRequired = false

    var body: some View {
        VStack(spacing: 0) {
            WorkspacePageHeader(
                title: "Settings",
                headingIdentifier: "appShell.page.settings.heading"
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    WorkspaceSegmentedTrack(selection: unmatchedBehavior, options: [
                        (value: .alwaysAsk, title: WorkspaceCopy.unmatchedSegmentTitle(for: .alwaysAsk)),
                        (value: .preferredBrowser, title: WorkspaceCopy.unmatchedSegmentTitle(for: .preferredBrowser)),
                        (value: .lastUsedBrowser, title: WorkspaceCopy.unmatchedSegmentTitle(for: .lastUsedBrowser)),
                    ])

                    Text(WorkspaceCopy.unmatchedDescription(for: environment.settings.unmatchedBehavior))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    WorkspacePreviewCard {
                        unmatchedPreview
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        languageSentence
                        menuBarSentence
                        automaticRulesSentence
                        if environment.settings.unmatchedBehavior == .preferredBrowser {
                            preferredBrowserSentence
                        }
                        launchAtLoginSentence
                        updatesSentence
                        historySentence
                        defaultHandlerSentence
                    }
                    .accessibilityIdentifier("settings.sentences")

                    if loginItemState == .requiresApproval {
                        Text("macOS needs approval before Prism can open at login.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("Open Login Items Settings") {
                            environment.loginItemService?.openApprovalSettingsAfterUserAction()
                        }
                        .buttonStyle(WorkspaceSecondaryCapsuleStyle())
                        .accessibilityIdentifier("settings.openLoginItems")
                    } else if loginItemState == .notFound {
                        Text("Launch at login is unavailable in this build.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if !environment.updateChecker.canCheckForUpdates {
                        Text("Updates are available in signed release builds.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Text("Link history stays on this Mac. Prism removes sensitive URL data before showing or copying it.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    WorkspaceSentence {
                        Text("Version")
                        Text(version)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 8) {
                        Spacer(minLength: 0)
                        if defaultHandlerState != .active {
                            Button("Refresh") {
                                Task { await refreshDefaultHandler() }
                            }
                            .buttonStyle(WorkspaceSecondaryCapsuleStyle())
                            .disabled(isUpdatingDefaultHandler || environment.defaultBrowserService == nil)
                            .accessibilityIdentifier("settings.refreshDefaultHandler")

                            Button("Open System Settings", action: openDefaultAppsSettings)
                                .buttonStyle(WorkspaceSecondaryCapsuleStyle())
                                .disabled(isUpdatingDefaultHandler)
                                .accessibilityIdentifier("settings.openDefaultApps")
                        }
                        Button("Set as Default") {
                            Task { await setDefaultHandler() }
                        }
                        .buttonStyle(WorkspacePrimaryCapsuleStyle())
                        .disabled(
                            isUpdatingDefaultHandler
                                || environment.defaultBrowserService == nil
                                || defaultHandlerState == .active
                        )
                        .accessibilityIdentifier("settings.setDefaultHandler")
                    }
                }
                .padding(.horizontal, WorkspaceLayout.contentInset)
                .padding(.bottom, 28)
                .frame(maxWidth: WorkspaceLayout.settingsReadableWidth, alignment: .leading)
            }
        }
        .tint(.primary)
        .background(WorkspacePalette.canvas)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await loadContext() }
        .alert(
            "Settings could not be updated",
            isPresented: Binding(
                get: { actionMessage != nil },
                set: { if !$0 { actionMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { actionMessage = nil }
        } message: {
            Text(LocalizedStringKey(actionMessage ?? ""))
        }
        .confirmationDialog("Restart Prism to Apply Language", isPresented: $languageRestartRequired) {
            Button("Restart Now") { restart() }
                .accessibilityIdentifier("settings.languageRestartNow")
            Button("Later", role: .cancel) {}
        } message: {
            Text("Prism will use the selected language the next time it opens.")
        }
    }

    private var languageSentence: some View {
        WorkspaceSentence {
            Text(WorkspaceCopy.languageSentenceLead())
            WorkspaceInlinePill(
                selection: appLanguage,
                title: String(localized: environment.settings.language.sentenceTitle),
                accessibilityIdentifier: "settings.language",
                accessibilityLabel: "Language",
                options: [
                    WorkspaceInlineOption(
                        value: AppLanguage.system,
                        title: String(localized: "the system language"),
                        accessibilityIdentifier: "settings.language.system"
                    ),
                    WorkspaceInlineOption(
                        value: AppLanguage.english,
                        title: String(localized: "English"),
                        accessibilityIdentifier: "settings.language.english"
                    ),
                    WorkspaceInlineOption(
                        value: AppLanguage.simplifiedChinese,
                        title: String(localized: "Simplified Chinese"),
                        accessibilityIdentifier: "settings.language.simplifiedChinese"
                    ),
                ]
            )
            Text(WorkspaceCopy.languageSentenceTrail())
        }
    }

    private var menuBarSentence: some View {
        WorkspaceSentence {
            Text("Prism")
            WorkspaceOnOffPill(
                isOn: showMenuBarItem,
                accessibilityIdentifier: "settings.showMenuBarItem",
                accessibilityLabel: "Show Prism in the menu bar",
                onTitle: String(localized: "shows"),
                offTitle: String(localized: "hides")
            )
            Text("in the menu bar.")
        }
    }

    private var automaticRulesSentence: some View {
        WorkspaceSentence {
            Text("Prism")
            WorkspaceOnOffPill(
                isOn: automaticRulesEnabled,
                accessibilityIdentifier: "settings.automaticRules",
                accessibilityLabel: "Use routing rules automatically",
                onTitle: String(localized: "uses"),
                offTitle: String(localized: "ignores")
            )
            Text("routing rules automatically.")
        }
    }

    private var preferredBrowserSentence: some View {
        WorkspaceSentence {
            Text(WorkspaceCopy.preferredBrowserSentenceLead())
            WorkspaceInlinePill(
                selection: preferredBrowserID,
                title: preferredBrowserTitle,
                accessibilityLabel: "Preferred browser",
                options: preferredBrowserOptions
            )
            Text(".")
        }
    }

    private var launchAtLoginSentence: some View {
        WorkspaceSentence {
            Text("Prism")
            WorkspaceOnOffPill(
                isOn: launchAtLogin,
                accessibilityIdentifier: "settings.launchAtLogin",
                accessibilityLabel: "Open Prism at login",
                isDisabled: isUpdatingLoginItem || environment.loginItemService == nil,
                onTitle: String(localized: "opens"),
                offTitle: String(localized: "does not open")
            )
            Text("at login.")
        }
    }

    private var updatesSentence: some View {
        WorkspaceSentence {
            Text("Prism")
            WorkspaceOnOffPill(
                isOn: automaticUpdateChecks,
                accessibilityIdentifier: "settings.automaticUpdateChecks",
                accessibilityLabel: "Automatically check for updates",
                isDisabled: !environment.updateChecker.canCheckForUpdates,
                onTitle: String(localized: "checks"),
                offTitle: String(localized: "does not check")
            )
            Text("for updates automatically.")
            if environment.updateChecker.canCheckForUpdates {
                Button("Check for Updates") {
                    environment.updateChecker.checkForUpdates()
                }
                .buttonStyle(WorkspaceSecondaryCapsuleStyle())
                .accessibilityIdentifier("settings.checkForUpdates")
            }
        }
    }

    private var historySentence: some View {
        WorkspaceSentence {
            Text("Prism")
            WorkspaceOnOffPill(
                isOn: historyEnabled,
                accessibilityIdentifier: "settings.historyEnabled",
                accessibilityLabel: "Save History",
                onTitle: String(localized: "saves"),
                offTitle: String(localized: "does not save")
            )
            if environment.settings.historyEnabled {
                Text("History, keeping up to")
                WorkspaceInlinePill(
                    selection: historyLimit,
                    title: "\(environment.settings.historyLimit)",
                    accessibilityLabel: "History limit",
                    options: historyLimitOptions
                )
                Text("links for")
                WorkspaceInlinePill(
                    selection: historyRetentionDays,
                    title: "\(environment.settings.historyRetentionDays)",
                    accessibilityLabel: "History retention",
                    options: historyRetentionOptions
                )
                Text("days.")
            } else {
                Text("History.")
            }
        }
    }

    private var defaultHandlerSentence: some View {
        WorkspaceSentence {
            Text(WorkspaceCopy.defaultHandlerSentence(for: defaultHandlerState))
            if defaultHandlerState != .active {
                Text(LocalizedStringKey(defaultHandlerExplanation))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var unmatchedPreview: some View {
        switch environment.settings.unmatchedBehavior {
        case .alwaysAsk:
            WorkspaceScaledSelectorPreview(
                browsers: previewBrowsers,
                selectedID: previewBrowsers.first?.id,
                sourceName: selectorSourceName,
                sourceIcon: WorkspaceApplicationIcon.nsImage(bundleIdentifier: "com.apple.Safari"),
                urlText: "https://example.com",
                showsShortcuts: true
            )
        case .preferredBrowser:
            WorkspaceCornerWidgetScene(
                address: "https://example.com",
                browser: preferredBrowser
            )
        case .lastUsedBrowser:
            WorkspaceCornerWidgetScene(
                address: "https://example.com",
                browser: lastUsedBrowser
            )
        }
    }

    private var selectorSourceName: String {
        if WorkspaceApplicationIcon.nsImage(bundleIdentifier: "com.apple.Safari") != nil {
            return "Safari"
        }
        return "Prism"
    }

    private var previewBrowsers: [BrowserDescriptor] {
        browsers.filter { $0.availability == .available }
    }

    private var preferredBrowser: BrowserDescriptor? {
        previewBrowsers.first(where: { $0.id == environment.settings.preferredBrowserID })
            ?? previewBrowsers.first
    }

    private var lastUsedBrowser: BrowserDescriptor? {
        previewBrowsers.first(where: { $0.id == environment.settings.lastUsedBrowserID })
            ?? previewBrowsers.first
    }

    private var preferredBrowserTitle: String {
        preferredBrowser?.displayName ?? String(localized: "Choose a browser")
    }

    private var preferredBrowserOptions: [WorkspaceInlineOption<BrowserID?>] {
        [WorkspaceInlineOption(value: nil, title: String(localized: "Choose a browser"))]
            + previewBrowsers.map { browser in
                WorkspaceInlineOption(value: Optional(browser.id), title: browser.displayName)
            }
    }

    private var historyLimitOptions: [WorkspaceInlineOption<Int>] {
        intOptions(presets: [50, 100, 250, 500, 1_000, 5_000], current: environment.settings.historyLimit)
    }

    private var historyRetentionOptions: [WorkspaceInlineOption<Int>] {
        intOptions(presets: [7, 14, 30, 90, 180, 365], current: environment.settings.historyRetentionDays)
    }

    private func intOptions(presets: [Int], current: Int) -> [WorkspaceInlineOption<Int>] {
        let values = presets.contains(current) ? presets : ([current] + presets).sorted()
        return values.map { WorkspaceInlineOption(value: $0, title: "\($0)") }
    }

    private var automaticRulesEnabled: Binding<Bool> {
        setting(\.automaticRulesEnabled)
    }

    private var appLanguage: Binding<AppLanguage> {
        Binding(
            get: { environment.settings.language },
            set: { language in
                guard language != environment.settings.language else { return }
                guard environment.mutateSettings({ $0.language = language }) else {
                    actionMessage = "Prism could not save this setting. Your previous value is still in use."
                    return
                }
                updateAppLanguagePreference(language)
                languageRestartRequired = true
            }
        )
    }

    private var showMenuBarItem: Binding<Bool> {
        setting(\.showMenuBarItem)
    }

    private var historyEnabled: Binding<Bool> {
        setting(\.historyEnabled)
    }

    private var historyLimit: Binding<Int> {
        setting(\.historyLimit)
    }

    private var historyRetentionDays: Binding<Int> {
        setting(\.historyRetentionDays)
    }

    private var unmatchedBehavior: Binding<UnmatchedBehavior> {
        setting(\.unmatchedBehavior)
    }

    private var preferredBrowserID: Binding<BrowserID?> {
        setting(\.preferredBrowserID)
    }

    private var launchAtLogin: Binding<Bool> {
        Binding(
            get: { loginItemState == .enabled },
            set: { wantsLaunchAtLogin in
                Task { await updateLaunchAtLogin(wantsLaunchAtLogin) }
            }
        )
    }

    private var automaticUpdateChecks: Binding<Bool> {
        Binding(
            get: { environment.updateChecker.automaticallyChecksForUpdates },
            set: { environment.updateChecker.automaticallyChecksForUpdates = $0 }
        )
    }

    private var defaultHandlerExplanation: String {
        guard case let .some(.inactive(http, https)) = defaultHandlerState else {
            return "Prism could not check the current default web-link handler."
        }
        let inactiveSchemes = [http ? nil : "HTTP", https ? nil : "HTTPS"].compactMap { $0 }
        return "Set Prism as the default application for \(inactiveSchemes.joined(separator: " and ")) links."
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let marketing = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        guard let build = info?["CFBundleVersion"] as? String, build != marketing else {
            return marketing
        }
        return "\(marketing) (\(build))"
    }

    private func setting<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { environment.settings[keyPath: keyPath] },
            set: { value in
                guard environment.mutateSettings({ $0[keyPath: keyPath] = value }) else {
                    actionMessage = "Prism could not save this setting. Your previous value is still in use."
                    return
                }
            }
        )
    }

    private func loadContext() async {
        browsers = (try? await browserCatalog.scan()) ?? []
        await refreshDefaultHandler()
        loginItemState = environment.loginItemService?.status()
    }

    private func refreshDefaultHandler() async {
        guard !isUpdatingDefaultHandler else { return }
        defaultHandlerState = try? await environment.defaultBrowserService?.status()
    }

    private func setDefaultHandler() async {
        guard let defaultBrowserService = environment.defaultBrowserService,
              !isUpdatingDefaultHandler
        else { return }
        isUpdatingDefaultHandler = true
        defer { isUpdatingDefaultHandler = false }
        do {
            defaultHandlerState = try await defaultBrowserService.setAsDefaultAfterUserConfirmation()
        } catch {
            defaultHandlerState = try? await defaultBrowserService.status()
            actionMessage = "Prism could not become the default handler for every web link. Review System Settings and try again."
        }
    }

    private func updateLaunchAtLogin(_ wantsLaunchAtLogin: Bool) async {
        guard let loginItemService = environment.loginItemService,
              !isUpdatingLoginItem
        else { return }
        isUpdatingLoginItem = true
        defer { isUpdatingLoginItem = false }
        do {
            if wantsLaunchAtLogin {
                try loginItemService.registerAfterUserAction()
            } else {
                try loginItemService.unregisterAfterUserAction()
            }
            loginItemState = loginItemService.status()
            if wantsLaunchAtLogin, loginItemState != .enabled {
                actionMessage = "macOS needs approval before Prism can open at login."
            }
        } catch {
            loginItemState = loginItemService.status()
            actionMessage = "Prism could not update the launch-at-login setting."
        }
    }

    private func updateAppLanguagePreference(_ language: AppLanguage) {
        #if DEBUG
        guard !ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return }
        #endif
        if let code = language.interfaceLocalizationCode {
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
    }
}
