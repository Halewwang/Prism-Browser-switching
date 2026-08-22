import PrismCore
import SwiftUI

struct SettingsManagementView: View {
    @Environment(AppEnvironment.self) private var environment

    let browserCatalog: any BrowserCataloging

    @State private var browsers: [BrowserDescriptor] = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Settings")
                        .font(.title2.weight(.semibold))
                        .accessibilityIdentifier("appShell.page.settings.heading")
                    Text("Control how Prism handles links and keeps local History.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)

            Divider()

            Form {
                Section("Link handling") {
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
                    LabeledContent("Version", value: "1.0.0")
                    Text("Link history stays on this Mac. Prism removes sensitive URL data before showing or copying it.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .task { await loadBrowsers() }
    }

    private var automaticRulesEnabled: Binding<Bool> {
        setting(\.automaticRulesEnabled)
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

    private func setting<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { environment.settings[keyPath: keyPath] },
            set: { value in
                _ = environment.mutateSettings { $0[keyPath: keyPath] = value }
            }
        )
    }

    private func loadBrowsers() async {
        browsers = (try? await browserCatalog.scan()) ?? []
    }
}
