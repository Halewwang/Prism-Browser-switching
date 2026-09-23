import AppKit
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
    @State private var publishedInstaller: GitHubPublishedInstaller?
    @State private var publishedInstallerUnavailable = false

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
        VStack(spacing: 16) {
            SettingsGroup {
                settingsRow(
                    title: "Language",
                    detail: "Prism applies the language the next time it opens.",
                    symbol: "globe",
                    tint: .blue
                ) {
                    languagePicker
                }
                SettingsSeparator()
                defaultHandlerRow
                SettingsSeparator()
                settingsToggle(
                    "Use routing rules automatically",
                    detail: "Enabled rules open matching links without asking.",
                    symbol: "arrow.triangle.branch",
                    tint: .blue,
                    isOn: automaticRulesEnabled,
                    identifier: "settings.automaticRules"
                )
                SettingsSeparator()
                settingsRow(
                    title: "When no rule matches",
                    detail: "Choose what happens after rules are checked.",
                    symbol: "questionmark.circle",
                    tint: .orange
                ) {
                    unmatchedPicker
                }
                if environment.settings.unmatchedBehavior == .preferredBrowser {
                    SettingsSeparator()
                    settingsRow(
                        title: "Preferred browser",
                        detail: "Used when no rule matches.",
                        symbol: "safari",
                        tint: .blue
                    ) {
                        preferredBrowserPicker
                    }
                }
            }

            SettingsGroup {
                settingsToggle(
                    "Open Prism at login",
                    detail: loginItemDetail,
                    symbol: "person.crop.circle",
                    tint: .gray,
                    isOn: launchAtLogin,
                    identifier: "settings.launchAtLogin",
                    disabled: isUpdatingLoginItem || environment.loginItemService == nil
                )
                SettingsSeparator()
                settingsToggle(
                    "Show Prism in the menu bar",
                    detail: "Pause rules, open History, and quit from the menu bar.",
                    symbol: "menubar.rectangle",
                    tint: .indigo,
                    isOn: showMenuBarItem,
                    identifier: "settings.showMenuBarItem"
                )
                if loginItemState == .requiresApproval {
                    SettingsSeparator()
                    settingsAction("Open Login Items Settings", symbol: "gearshape", tint: .gray, identifier: "settings.openLoginItems") {
                        environment.loginItemService?.openApprovalSettingsAfterUserAction()
                    }
                }
            }

            SettingsGroup {
                settingsToggle(
                    "Save History",
                    detail: "Saved links stay on this Mac. Prism removes sensitive URL data before showing or copying them.",
                    symbol: "clock",
                    tint: .orange,
                    isOn: historyEnabled,
                    identifier: "settings.historyEnabled"
                )
                if environment.settings.historyEnabled {
                    SettingsSeparator()
                    settingsRow(
                        title: "How many links to keep",
                        detail: "Older links are removed first.",
                        symbol: "number",
                        tint: .gray
                    ) {
                        historyLimitPicker
                    }
                    SettingsSeparator()
                    settingsRow(
                        title: "How long to keep links",
                        detail: "Links older than this are removed.",
                        symbol: "calendar",
                        tint: .gray
                    ) {
                        historyRetentionPicker
                    }
                }
            }

            SettingsGroup {
                settingsToggle(
                    "Automatically check for updates",
                    detail: sparkleUpdateDetail,
                    symbol: "arrow.down.circle",
                    tint: .blue,
                    isOn: automaticUpdateChecks,
                    identifier: "settings.automaticUpdateChecks",
                    disabled: !environment.updateChecker.canCheckForUpdates
                )
                if environment.updateChecker.canCheckForUpdates {
                    SettingsSeparator()
                    settingsAction("Check for Updates", symbol: "arrow.clockwise", tint: .blue, identifier: "settings.checkForUpdates") {
                        environment.updateChecker.checkForUpdates()
                    }
                }
                SettingsSeparator()
                publishedInstallerRow
            }

            SettingsGroup {
                settingsRow(
                    title: "Version",
                    detail: "Link history stays on this Mac.",
                    symbol: "info.circle",
                    tint: .gray
                ) {
                    Text(version)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var languagePicker: some View {
        Picker("Language", selection: appLanguage) {
            Text("Use System Language")
                .tag(AppLanguage.system)
                .accessibilityIdentifier("settings.language.system")
            Text("English")
                .tag(AppLanguage.english)
                .accessibilityIdentifier("settings.language.english")
            Text("Simplified Chinese")
                .tag(AppLanguage.simplifiedChinese)
                .accessibilityIdentifier("settings.language.simplifiedChinese")
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
        .accessibilityIdentifier("settings.language")
    }

    private var unmatchedPicker: some View {
        Picker("When no rule matches", selection: unmatchedBehavior) {
            Text("Always ask").tag(UnmatchedBehavior.alwaysAsk)
            Text("Preferred browser").tag(UnmatchedBehavior.preferredBrowser)
            Text("Last used").tag(UnmatchedBehavior.lastUsedBrowser)
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
    }

    private var preferredBrowserPicker: some View {
        Picker("Preferred browser", selection: preferredBrowserID) {
            Text("Choose a browser").tag(BrowserID?.none)
            ForEach(browsers.filter { $0.availability == .available }, id: \.id) { browser in
                Text(browser.displayName).tag(BrowserID?.some(browser.id))
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
    }

    private var historyLimitPicker: some View {
        Picker("How many links to keep", selection: historyLimit) {
            ForEach([50, 100, 250, 500, 1_000], id: \.self) { limit in
                Text("\(limit)").tag(limit)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
    }

    private var historyRetentionPicker: some View {
        Picker("How long to keep links", selection: historyRetentionDays) {
            Text("7 days").tag(7)
            Text("30 days").tag(30)
            Text("90 days").tag(90)
            Text("1 year").tag(365)
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
    }

    @ViewBuilder
    private var defaultHandlerRow: some View {
        settingsRow(
            title: "Default web link handler",
            detail: defaultHandlerState == .active ? "Prism receives both web-link schemes" : defaultHandlerExplanation,
            symbol: "link",
            tint: defaultHandlerState == .active ? .green : .orange
        ) {
            Label {
                Text(LocalizedStringKey(defaultHandlerLabel))
            } icon: {
                Image(systemName: defaultHandlerSymbol)
            }
            .foregroundStyle(defaultHandlerColor)
            .font(.body)
            .labelStyle(.titleAndIcon)
        }
        if defaultHandlerState != .active {
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button("Set Prism as Default") {
                    Task { await setDefaultHandler() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isUpdatingDefaultHandler || environment.defaultBrowserService == nil)
                .accessibilityIdentifier("settings.setDefaultHandler")

                Button("Refresh") {
                    Task { await refreshDefaultHandler() }
                }
                .disabled(isUpdatingDefaultHandler || environment.defaultBrowserService == nil)
                .accessibilityIdentifier("settings.refreshDefaultHandler")

                Button("Open System Settings", action: openDefaultAppsSettings)
                    .disabled(isUpdatingDefaultHandler)
                    .accessibilityIdentifier("settings.openDefaultApps")
            }
            .padding(.leading, 48)
            .padding(.trailing, 14)
            .padding(.bottom, 12)
        }
    }

    @ViewBuilder
    private var publishedInstallerRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            settingsRow(
                title: "Published installer",
                detail: publishedInstallerDetail,
                symbol: "square.and.arrow.down",
                tint: .blue
            ) {
                EmptyView()
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                if let publishedInstaller {
                    Button("Download installer") {
                        NSWorkspace.shared.open(publishedInstaller.downloadURL)
                    }
                    .accessibilityIdentifier("settings.downloadInstaller")
                }
                Button("Open GitHub Releases") {
                    NSWorkspace.shared.open(GitHubPublishedInstaller.releasesURL)
                }
                .accessibilityIdentifier("settings.openReleases")
            }
            .padding(.leading, 48)
            .padding(.trailing, 14)
            .padding(.bottom, 12)
        }
    }

    private var publishedInstallerDetail: String {
        if let publishedInstaller {
            return "\(publishedInstaller.version) · \(publishedInstaller.fileName). GitHub publishes this disk image separately from Sparkle. This build installs signed updates only when appcast.xml and an EdDSA key are present."
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

    private var sparkleUpdateDetail: String {
        environment.updateChecker.canCheckForUpdates
            ? "Sparkle checks the signed appcast and asks before installing."
            : "Signed in-app updates are off until this build includes an EdDSA key. The latest GitHub release also has no appcast.xml."
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
                .toggleStyle(.switch)
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
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(tint, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title))
                    .font(.body)
                if !detail.isEmpty {
                    Text(LocalizedStringKey(detail))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            control()
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
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

    private var defaultHandlerColor: Color {
        defaultHandlerState == .active ? .green : .orange
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
