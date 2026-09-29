import AppKit
import PrismCore
import SwiftUI

struct SettingsManagementView: View {
    @Environment(AppEnvironment.self) private var environment

    let browserCatalog: any BrowserCataloging
    var addCustomBrowser: @MainActor () async -> OnboardingCustomBrowserResult = { .cancelled }
    let openDefaultAppsSettings: () -> Void
    let restart: () -> Void

    @State private var browsers: [BrowserDescriptor] = []
    @State private var defaultHandlerState: DefaultHandlerState?
    @State private var loginItemState: LoginItemState?
    @State private var isUpdatingDefaultHandler = false
    @State private var isUpdatingLoginItem = false
    @State private var actionMessage: String?
    @State private var languageRestartRequired = false
    @State private var publishedInstaller: GitHubPublishedInstaller?
    @State private var publishedInstallerUnavailable = false
    @State private var showBrowserManagement = false

    var body: some View {
        PageColumn {
            SystemSettingsPageHeader(
                    title: "Settings",
                    subtitle: "Control how Prism handles links and keeps local History.",
                    accessibilityIdentifier: "appShell.page.settings.heading"
                )
                settingsCards
        }
        .task { await loadContext() }
        .sheet(isPresented: $showBrowserManagement, onDismiss: {
            Task {
                do { browsers = try await browserCatalog.scan() }
                catch { actionMessage = "Browsers could not be loaded. Try scanning again." }
            }
        }) {
            BrowserManagementSheet(browserCatalog: browserCatalog, addCustomBrowser: addCustomBrowser)
        }
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

    private var settingsCards: some View {
        VStack(alignment: .leading, spacing: 24) {
            settingsSection("Link Handling", symbol: "link") {
                defaultHandlerRow
                SettingsSeparator()
                settingsToggle(
                    "Use routing rules automatically",
                    detail: "Enabled rules open matching links without asking.",
                    symbol: "arrow.triangle.branch", tint: SettingsPalette.primary,
                    isOn: automaticRulesEnabled, identifier: "settings.automaticRules"
                )
                SettingsSeparator()
                settingsRow(
                    title: "When no rule matches",
                    detail: "Choose what happens after rules are checked.",
                    symbol: "questionmark.circle", tint: SettingsPalette.primary
                ) { unmatchedPicker }
                if environment.settings.unmatchedBehavior == .preferredBrowser {
                    SettingsSeparator()
                    settingsRow(
                        title: "Preferred browser", detail: "Used when no rule matches.",
                        symbol: "safari", tint: SettingsPalette.primary
                    ) { preferredBrowserPicker }
                }
            }

            settingsSection("General", symbol: "gearshape") {
                settingsRow(
                    title: "Language",
                    detail: "Prism applies the language the next time it opens.",
                    symbol: "globe", tint: SettingsPalette.primary
                ) { languagePicker }
                SettingsSeparator()
                settingsToggle(
                    "Open Prism at login", detail: loginItemDetail,
                    symbol: "person.crop.circle", tint: SettingsPalette.primary,
                    isOn: launchAtLogin, identifier: "settings.launchAtLogin",
                    disabled: isUpdatingLoginItem || environment.loginItemService == nil
                )
                SettingsSeparator()
                settingsToggle(
                    "Show Prism in the menu bar",
                    detail: "Pause rules, open History, and quit from the menu bar.",
                    symbol: "menubar.rectangle", tint: SettingsPalette.primary,
                    isOn: showMenuBarItem, identifier: "settings.showMenuBarItem"
                )
                SettingsSeparator()
                settingsAction("Manage Browsers", symbol: "safari", tint: SettingsPalette.primary, identifier: "settings.manageBrowsers") {
                    showBrowserManagement = true
                }
                if loginItemState == .requiresApproval {
                    SettingsSeparator()
                    settingsAction("Open Login Items Settings", symbol: "gearshape", tint: SettingsPalette.primary, identifier: "settings.openLoginItems") {
                        environment.loginItemService?.openApprovalSettingsAfterUserAction()
                    }
                }
            }

            settingsSection("History & Privacy", symbol: "lock.shield") {
                settingsToggle(
                    "Save History",
                    detail: "Saved links stay on this Mac. Prism removes sensitive URL data before showing or copying them.",
                    symbol: "clock", tint: SettingsPalette.primary,
                    isOn: historyEnabled, identifier: "settings.historyEnabled"
                )
                if environment.settings.historyEnabled {
                    SettingsSeparator()
                    settingsRow(
                        title: "How many links to keep", detail: "Older links are removed first.",
                        symbol: "number", tint: SettingsPalette.primary
                    ) { historyLimitPicker }
                    SettingsSeparator()
                    settingsRow(
                        title: "How long to keep links", detail: "Links older than this are removed.",
                        symbol: "calendar", tint: SettingsPalette.primary
                    ) { historyRetentionPicker }
                }
            }

            settingsSection("Software Updates", symbol: "arrow.down.circle") {
                settingsToggle(
                    "Automatically check for updates", detail: updateCheckDetail,
                    symbol: "arrow.down.circle", tint: SettingsPalette.primary,
                    isOn: automaticUpdateChecks, identifier: "settings.automaticUpdateChecks",
                    disabled: !environment.updateChecker.canCheckForUpdates
                )
                if environment.updateChecker.canCheckForUpdates {
                    SettingsSeparator()
                    settingsAction("Check for Updates", symbol: "arrow.clockwise", tint: SettingsPalette.primary, identifier: "settings.checkForUpdates") {
                        environment.updateChecker.checkForUpdates()
                    }
                }
                SettingsSeparator()
                publishedInstallerRow
            }

            HStack(spacing: 14) {
                Text("Prism for macOS")
                Spacer(minLength: 12)
                Text(version)
                Button("About Prism") {
                    NSApp.orderFrontStandardAboutPanel(nil)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.about")
                Button("GitHub") {
                    NSWorkspace.shared.open(GitHubPublishedInstaller.releasesURL)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.openReleases")
            }
            .font(.system(size: 12))
            .foregroundStyle(SettingsPalette.secondary)
            .padding(.horizontal, 2)
        }
        .tint(SettingsPalette.primary)
    }

    private func settingsSection<Content: View>(
        _ title: String, symbol: String, @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            WorkspaceSectionHeader(title: title, detail: "", systemImage: symbol)
            SettingsGroup(content: content)
        }
    }

    private var languagePicker: some View {
        WorkspacePicker(title: "Language", selection: appLanguage, options: [
            WorkspacePickerOption(value: AppLanguage.system, title: "Use System Language", accessibilityIdentifier: "settings.language.system"),
            WorkspacePickerOption(value: AppLanguage.english, title: "English", accessibilityIdentifier: "settings.language.english"),
            WorkspacePickerOption(value: AppLanguage.simplifiedChinese, title: "Simplified Chinese", accessibilityIdentifier: "settings.language.simplifiedChinese")
        ])
        .frame(width: 178)
        .accessibilityIdentifier("settings.language")
    }

    private var unmatchedPicker: some View {
        WorkspacePicker(title: "When no rule matches", selection: unmatchedBehavior, options: [
            WorkspacePickerOption(value: UnmatchedBehavior.alwaysAsk, title: "Always ask"),
            WorkspacePickerOption(value: UnmatchedBehavior.preferredBrowser, title: "Preferred browser"),
            WorkspacePickerOption(value: UnmatchedBehavior.lastUsedBrowser, title: "Last used")
        ]).frame(width: 178)
        .accessibilityIdentifier("settings.unmatchedBehavior")
    }

    private var preferredBrowserPicker: some View {
        WorkspacePicker(title: "Preferred browser", selection: preferredBrowserID, options:
            [WorkspacePickerOption(value: BrowserID?.none, title: "Choose a browser")]
            + browsers.filter { $0.availability == .available }.map {
                WorkspacePickerOption(value: BrowserID?.some($0.id), title: $0.displayName)
            }
        ).frame(width: 178)
        .accessibilityIdentifier("settings.preferredBrowser")
    }

    private var historyLimitPicker: some View {
        WorkspacePicker(title: "How many links to keep", selection: historyLimit, options:
            [50, 100, 250, 500, 1_000].map { WorkspacePickerOption(value: $0, title: "\($0)") }
        ).frame(width: 130)
    }

    private var historyRetentionPicker: some View {
        WorkspacePicker(title: "How long to keep links", selection: historyRetentionDays, options: [
            WorkspacePickerOption(value: 7, title: "7 days"),
            WorkspacePickerOption(value: 30, title: "30 days"),
            WorkspacePickerOption(value: 90, title: "90 days"),
            WorkspacePickerOption(value: 365, title: "1 year")
        ]).frame(width: 130)
    }

    @ViewBuilder
    private var defaultHandlerRow: some View {
        settingsRow(
            title: "Default web link handler",
            detail: defaultHandlerState == .active ? "Prism receives both web-link schemes" : defaultHandlerExplanation,
            symbol: "link",
            tint: SettingsPalette.primary
        ) {
            Label {
                Text(LocalizedStringKey(defaultHandlerLabel))
            } icon: {
                Image(systemName: defaultHandlerSymbol)
            }
            .foregroundStyle(SettingsPalette.primary)
            .font(.system(size: 12, weight: .medium))
            .labelStyle(.titleAndIcon)
        }
        if defaultHandlerState != .active {
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button("Set Prism as Default") {
                    Task { await setDefaultHandler() }
                }
                .buttonStyle(WorkspaceButtonStyle(kind: .primary))
                .disabled(isUpdatingDefaultHandler || environment.defaultBrowserService == nil)
                .accessibilityIdentifier("settings.setDefaultHandler")

                Button("Refresh") {
                    Task { await refreshDefaultHandler() }
                }
                .buttonStyle(WorkspaceButtonStyle(kind: .secondary))
                .disabled(isUpdatingDefaultHandler || environment.defaultBrowserService == nil)
                .accessibilityIdentifier("settings.refreshDefaultHandler")

                Button("Open System Settings", action: openDefaultAppsSettings)
                    .buttonStyle(WorkspaceButtonStyle(kind: .quiet))
                    .disabled(isUpdatingDefaultHandler)
                    .accessibilityIdentifier("settings.openDefaultApps")
            }
            .padding(.leading, 18)
            .padding(.trailing, 18)
            .padding(.bottom, 12)
        }
    }

    @ViewBuilder
    private var publishedInstallerRow: some View {
        settingsRow(
            title: "Published installer",
            detail: publishedInstallerDetail,
            symbol: "square.and.arrow.down",
            tint: SettingsPalette.primary
        ) {
            if let publishedInstaller {
                Button("Download installer") {
                    NSWorkspace.shared.open(publishedInstaller.downloadURL)
                }
                .buttonStyle(WorkspaceButtonStyle(kind: .secondary))
                .accessibilityIdentifier("settings.downloadInstaller")
            }
        }
    }

    private var publishedInstallerDetail: String {
        if let publishedInstaller {
            let channel = publishedInstaller.isPrerelease ? " · " + NSLocalizedString("Public Test", comment: "Release channel") : ""
            return "\(publishedInstaller.version)\(channel) · \(publishedInstaller.fileName)"
        }
        if publishedInstallerUnavailable {
            return "Prism could not read the published installer from GitHub."
        }
        return "Checking the published GitHub installer…"
    }

    private var loginItemDetail: String {
        switch loginItemState {
        case .requiresApproval:
            "macOS needs approval before Prism can open at login."
        case .notFound:
            "Launch at login is unavailable in this build."
        default:
            "Prism opens when you log in to this Mac."
        }
    }

    private var updateCheckDetail: String {
        if environment.updateChecker is GitHubUpdateChecker {
            return "Checks GitHub for a newer native version and offers its installer."
        }
        return environment.updateChecker.canCheckForUpdates
            ? "Sparkle checks the signed appcast and asks before installing."
            : "Update checks are unavailable in this build."
    }

    private func settingsToggle(
        _ title: String,
        detail: String,
        symbol: String,
        tint: Color,
        isOn: Binding<Bool>,
        identifier: String,
        disabled: Bool = false
    ) -> some View {
        settingsRow(title: title, detail: detail, symbol: symbol, tint: tint) {
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(WorkspaceToggleStyle())
                .disabled(disabled)
                .accessibilityIdentifier(identifier)
        }
    }

    private func settingsAction(
        _ title: String,
        symbol: String,
        tint: Color,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            settingsRow(title: title, detail: "", symbol: symbol, tint: tint) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private func settingsRow<Control: View>(
        title: String,
        detail: String,
        symbol: String,
        tint: Color,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(SettingsPalette.primary)
                if !detail.isEmpty {
                    Text(LocalizedStringKey(detail))
                        .font(.system(size: 12))
                        .foregroundStyle(SettingsPalette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            control()
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(minHeight: 70)
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

    private var defaultHandlerLabel: String {
        switch defaultHandlerState {
        case .active:
            "HTTP + HTTPS active"
        case .inactive:
            "Needs attention"
        case nil:
            "Checking…"
        }
    }

    private var defaultHandlerSymbol: String {
        defaultHandlerState == .active ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
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
        await loadPublishedInstaller()
    }

    private func loadPublishedInstaller() async {
        do {
            publishedInstaller = try await GitHubPublishedInstallerLookup.load()
            publishedInstallerUnavailable = false
        } catch {
            publishedInstaller = nil
            publishedInstallerUnavailable = true
        }
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
