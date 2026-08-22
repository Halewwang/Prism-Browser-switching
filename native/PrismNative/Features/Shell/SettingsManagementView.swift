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
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Settings")
                        .font(WorkspaceLayout.pageTitleFont)
                        .accessibilityIdentifier("appShell.page.settings.heading")
                    Text("Control how Prism handles links and keeps local History.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, WorkspaceLayout.contentInset)
            .padding(.vertical, WorkspaceLayout.headerVerticalInset)

            Divider()

            Form {
                Section("Interface") {
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
                    .accessibilityIdentifier("settings.language")
                }

                Section("Link handling") {
                    defaultHandlerControl

                    Toggle("Show Prism in the menu bar", isOn: showMenuBarItem)
                        .accessibilityIdentifier("settings.showMenuBarItem")

                    Toggle("Use routing rules automatically", isOn: automaticRulesEnabled)
                        .accessibilityIdentifier("settings.automaticRules")

                    Picker("When no rule matches", selection: unmatchedBehavior) {
                        Text("Always ask").tag(UnmatchedBehavior.alwaysAsk)
                        Text("Open in preferred browser").tag(UnmatchedBehavior.preferredBrowser)
                        Text("Open in last used browser").tag(UnmatchedBehavior.lastUsedBrowser)
                    }

                    if environment.settings.unmatchedBehavior == .preferredBrowser {
                        Picker("Preferred browser", selection: preferredBrowserID) {
                            Text("Choose a browser").tag(BrowserID?.none)
                            ForEach(browsers.filter { $0.availability == .available }, id: \.id) { browser in
                                Text(browser.displayName).tag(BrowserID?.some(browser.id))
                            }
                        }
                    }
                }

                Section("Startup") {
                    Toggle("Open Prism at login", isOn: launchAtLogin)
                        .disabled(isUpdatingLoginItem || environment.loginItemService == nil)
                        .accessibilityIdentifier("settings.launchAtLogin")

                    if loginItemState == .requiresApproval {
                        Text("macOS needs approval before Prism can open at login.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("Open Login Items Settings") {
                            environment.loginItemService?.openApprovalSettingsAfterUserAction()
                        }
                        .accessibilityIdentifier("settings.openLoginItems")
                    } else if loginItemState == .notFound {
                        Text("Launch at login is unavailable in this build.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Updates") {
                    Toggle("Automatically check for updates", isOn: automaticUpdateChecks)
                        .disabled(!environment.updateChecker.canCheckForUpdates)
                        .accessibilityIdentifier("settings.automaticUpdateChecks")

                    if environment.updateChecker.canCheckForUpdates {
                        Button("Check for Updates") {
                            environment.updateChecker.checkForUpdates()
                        }
                        .accessibilityIdentifier("settings.checkForUpdates")
                    } else {
                        Text("Updates are available in signed release builds.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("History") {
                    Toggle("Save History", isOn: historyEnabled)
                        .accessibilityIdentifier("settings.historyEnabled")

                    if environment.settings.historyEnabled {
                        Stepper(
                            "Keep up to \(environment.settings.historyLimit) links",
                            value: historyLimit,
                            in: 1...10_000,
                            step: 25
                        )
                        Stepper(
                            "Keep links for \(environment.settings.historyRetentionDays) days",
                            value: historyRetentionDays,
                            in: 1...3_650
                        )
                    }
                }

                Section("About") {
                    LabeledContent("Version", value: version)
                    Text("Link history stays on this Mac. Prism removes sensitive URL data before showing or copying it.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .formStyle(.grouped)
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

    @ViewBuilder
    private var defaultHandlerControl: some View {
        LabeledContent("Default web link handler") {
            Label(defaultHandlerLabel, systemImage: defaultHandlerSymbol)
                .foregroundStyle(defaultHandlerColor)
        }

        if defaultHandlerState != .active {
            Text(LocalizedStringKey(defaultHandlerExplanation))
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
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
        }
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
