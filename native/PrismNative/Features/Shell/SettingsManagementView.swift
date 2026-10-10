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
    @State private var showBrowserManagement = false
    @State private var showResetConfirmation = false

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
        .onAppear { consumeBrowserManagementRequest() }
        .onChange(of: environment.pendingBrowserManagement) { _, pending in
            if pending { consumeBrowserManagementRequest() }
        }
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
        .alert("Reset All Settings?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) {}
                .keyboardShortcut(.cancelAction)
            Button("Reset Settings", role: .destructive) { resetSettings() }
                .accessibilityIdentifier("settings.confirmReset")
        } message: {
            Text("Restore default options while keeping your rules, History, and History retention limits. Launch at login will be turned off.")
        }
    }

    private var settingsCards: some View {
        VStack(alignment: .leading, spacing: 24) {
            settingsSection("Link Handling", symbol: "arrow.triangle.branch") {
                defaultHandlerRow
                settingsSeparator
                settingsToggle(
                    "Use routing rules automatically",
                    detail: "Enabled rules open matching links without asking.",
                    symbol: "arrow.triangle.branch", tint: SettingsPalette.primary,
                    isOn: automaticRulesEnabled, identifier: "settings.automaticRules"
                )
                settingsSeparator
                settingsRow(
                    title: "When no rule matches",
                    detail: "Choose what happens after rules are checked.",
                    symbol: "questionmark.circle", tint: SettingsPalette.primary
                ) { unmatchedPicker }
                if environment.settings.unmatchedBehavior == .preferredBrowser {
                    settingsSeparator
                    settingsRow(
                        title: "Preferred browser", detail: "Used when no rule matches.",
                        symbol: "safari", tint: SettingsPalette.primary
                    ) { preferredBrowserPicker }
                }
            }

            settingsSection("General", symbol: "slider.horizontal.3") {
                settingsRow(
                    title: "Language",
                    detail: "Prism applies the language the next time it opens.",
                    symbol: "globe", tint: SettingsPalette.primary
                ) { languagePicker }
                settingsSeparator
                settingsToggle(
                    "Open Prism at login", detail: loginItemDetail,
                    symbol: "person.crop.circle", tint: SettingsPalette.primary,
                    isOn: launchAtLogin, identifier: "settings.launchAtLogin",
                    disabled: isUpdatingLoginItem || environment.loginItemService == nil
                )
                settingsSeparator
                settingsToggle(
                    "Show Prism in the menu bar",
                    detail: "Pause rules, open History, and quit from the menu bar.",
                    symbol: "menubar.rectangle", tint: SettingsPalette.primary,
                    isOn: showMenuBarItem, identifier: "settings.showMenuBarItem"
                )
                if loginItemState == .requiresApproval {
                    settingsSeparator
                    settingsAction("Open Login Items Settings", symbol: "gearshape", tint: SettingsPalette.primary, identifier: "settings.openLoginItems") {
                        environment.loginItemService?.openApprovalSettingsAfterUserAction()
                    }
                }
            }

            settingsSection("History & Privacy", symbol: "checkmark.shield") {
                settingsToggle(
                    "Save History",
                    detail: "Saved links stay on this Mac. Prism removes sensitive URL data before showing or copying them.",
                    symbol: "clock", tint: SettingsPalette.primary,
                    isOn: historyEnabled, identifier: "settings.historyEnabled"
                )
                if environment.settings.historyEnabled {
                    settingsSeparator
                    settingsRow(
                        title: "How many links to keep", detail: "Older links are removed first.",
                        symbol: "number", tint: SettingsPalette.primary
                    ) { historyLimitPicker }
                    settingsSeparator
                    settingsRow(
                        title: "How long to keep links", detail: "Links older than this are removed.",
                        symbol: "calendar", tint: SettingsPalette.primary
                    ) { historyRetentionPicker }
                }
            }

            settingsSection("Software Updates", symbol: "arrow.down.to.line") {
                settingsToggle(
                    "Automatically check for updates", detail: updateCheckDetail,
                    symbol: "arrow.down.circle", tint: SettingsPalette.primary,
                    isOn: automaticUpdateChecks, identifier: "settings.automaticUpdateChecks",
                    disabled: !environment.updateChecker.canCheckForUpdates
                )
                settingsSeparator
                settingsRow(
                    title: "Check for Updates", detail: "See whether a new version is available.",
                    symbol: "arrow.clockwise", tint: SettingsPalette.primary
                ) {
                    Button { environment.updateChecker.checkForUpdates() } label: {
                        Text("Check Now")
                            .font(.system(size: 13))
                            .foregroundStyle(SettingsPalette.tertiary)
                            .padding(.horizontal, 10)
                            .frame(height: 31)
                            .background(SettingsPalette.elevated, in: RoundedRectangle(cornerRadius: 8))
                            .overlay { RoundedRectangle(cornerRadius: 8).stroke(SettingsPalette.border, lineWidth: 1) }
                    }
                    .buttonStyle(.plain)
                    .disabled(!environment.updateChecker.canCheckForUpdates)
                    .opacity(environment.updateChecker.canCheckForUpdates ? 1 : 0.4)
                    .accessibilityIdentifier("settings.checkForUpdates")
                }
                settingsSeparator
                publishedInstallerRow
            }

            settingsSection("About", symbol: "info.circle") {
                settingsRow(
                    title: "Version", detail: "Link history stays on this Mac.",
                    symbol: "info.circle", tint: SettingsPalette.primary,
                    detailColor: SettingsPalette.muted
                ) {
                    Text(version)
                        .font(.system(size: 13))
                        .foregroundStyle(SettingsPalette.tertiary)
                        .accessibilityIdentifier("settings.version")
                }
                SettingsSeparator(color: SettingsPalette.borderSubtle)
                settingsRow(
                    title: "Reset All Settings",
                    detail: "Restore default options without deleting rules or History.",
                    symbol: "arrow.counterclockwise", tint: SettingsPalette.primary,
                    detailColor: SettingsPalette.muted
                ) {
                    Button { showResetConfirmation = true } label: {
                        Text("Reset…")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(SettingsPalette.secondary)
                            .padding(.horizontal, 10)
                            .frame(height: 31)
                            .background(SettingsPalette.group, in: RoundedRectangle(cornerRadius: 8))
                            .overlay { RoundedRectangle(cornerRadius: 8).stroke(SettingsPalette.borderStrong, lineWidth: 1) }
                    }
                    .buttonStyle(.plain)
                    .disabled(isUpdatingLoginItem)
                    .opacity(isUpdatingLoginItem ? 0.4 : 1)
                    .accessibilityIdentifier("settings.reset")
                }
            }
        }
        .tint(SettingsPalette.primary)
    }

    private func consumeBrowserManagementRequest() {
        if environment.consumeBrowserManagement() { showBrowserManagement = true }
    }

    private var settingsSeparator: some View {
        SettingsSeparator(color: SettingsPalette.window)
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
        ], compact: true)
        .accessibilityIdentifier("settings.language")
    }

    private var unmatchedPicker: some View {
        WorkspacePicker(title: "When no rule matches", selection: unmatchedBehavior, options: [
            WorkspacePickerOption(value: UnmatchedBehavior.alwaysAsk, title: "Always ask"),
            WorkspacePickerOption(value: UnmatchedBehavior.preferredBrowser, title: "Preferred browser"),
            WorkspacePickerOption(value: UnmatchedBehavior.lastUsedBrowser, title: "Last used")
        ], compact: true)
        .accessibilityIdentifier("settings.unmatchedBehavior")
    }

    private var preferredBrowserPicker: some View {
        WorkspacePicker(title: "Preferred browser", selection: preferredBrowserID, options:
            [WorkspacePickerOption(value: BrowserID?.none, title: "Choose a browser")]
            + browsers.filter { $0.availability == .available }.map {
                WorkspacePickerOption(value: BrowserID?.some($0.id), title: $0.displayName)
            },
            compact: true
        )
        .accessibilityIdentifier("settings.preferredBrowser")
    }

    private var historyLimitPicker: some View {
        WorkspacePicker(title: "How many links to keep", selection: historyLimit, options:
            [50, 100, 250, 500, 1_000].map {
                WorkspacePickerOption(value: $0, title: String(format: NSLocalizedString("%d links", comment: "History limit"), $0))
            },
            compact: true
        )
        .accessibilityIdentifier("settings.historyLimit")
    }

    private var historyRetentionPicker: some View {
        WorkspacePicker(title: "How long to keep links", selection: historyRetentionDays, options: [
            WorkspacePickerOption(value: 7, title: "7 days"),
            WorkspacePickerOption(value: 30, title: "30 days"),
            WorkspacePickerOption(value: 90, title: "90 days"),
            WorkspacePickerOption(value: 365, title: "1 year")
        ], compact: true)
        .accessibilityIdentifier("settings.historyRetentionDays")
    }

    @ViewBuilder
    private var defaultHandlerRow: some View {
        settingsRow(
            title: "Default web link handler",
            detail: defaultHandlerState == .active ? "Let Prism handle links and route them to the right browser." : defaultHandlerExplanation,
            symbol: "link",
            tint: SettingsPalette.primary
        ) {
            HStack(spacing: 6) {
                Image(systemName: defaultHandlerSymbol)
                    .font(.system(size: 13))
                    .frame(width: 14, height: 14)
                Text(LocalizedStringKey(defaultHandlerLabel))
            }
            .foregroundStyle(SettingsPalette.primary)
            .font(.system(size: 13))
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
            detail: "Get the published installer from GitHub.",
            symbol: "square.and.arrow.down",
            tint: SettingsPalette.primary
        ) {
            Button {
                if let publishedInstaller {
                    if let checker = environment.updateChecker as? GitHubUpdateChecker {
                        if GitHubPublishedInstaller.isNewer(publishedInstaller.version, than: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") == true {
                            checker.showUpdate(publishedInstaller)
                        } else { checker.checkForUpdates() }
                    } else { NSWorkspace.shared.open(publishedInstaller.downloadURL) }
                } else {
                    NSWorkspace.shared.open(GitHubPublishedInstaller.releasesURL)
                }
            } label: {
                HStack(spacing: 6) {
                    Text("Go to Download")
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12))
                        .frame(width: 14, height: 14)
                }
                .font(.system(size: 13))
                .foregroundStyle(SettingsPalette.primary)
                .frame(minHeight: 28)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings.downloadInstaller")
        }
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
        environment.updateChecker.canCheckForUpdates
            ? "Get new features and improvements."
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
        detailColor: Color = SettingsPalette.tertiary,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(title))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(SettingsPalette.secondary)
                    .frame(minHeight: 20, alignment: .leading)
                if !detail.isEmpty {
                    Text(LocalizedStringKey(detail))
                        .font(.system(size: 12))
                        .foregroundStyle(detailColor)
                        .frame(minHeight: 17, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            control()
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .frame(minHeight: 67)
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
            "Prism is the default"
        case .inactive:
            "Needs attention"
        case nil:
            "Checking…"
        }
    }

    private var defaultHandlerSymbol: String {
        defaultHandlerState == .active ? "checkmark.circle" : "exclamationmark.circle"
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
        } catch {
            publishedInstaller = nil
        }
    }

    private func resetSettings() {
        let previousLanguage = environment.settings.language
        guard environment.resetSettingsToDefaults() else {
            actionMessage = "Prism could not reset settings. Your previous values are still in use."
            return
        }
        updateAppLanguagePreference(environment.settings.language)
        if let loginItemService = environment.loginItemService {
            do {
                if [.enabled, .requiresApproval].contains(loginItemService.status()) {
                    try loginItemService.unregisterAfterUserAction()
                }
            } catch {
                actionMessage = "Prism reset its saved settings, but could not turn off launch at login."
            }
            loginItemState = loginItemService.status()
        }
        languageRestartRequired = previousLanguage != environment.settings.language && actionMessage == nil
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
