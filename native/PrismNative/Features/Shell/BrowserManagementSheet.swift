import AppKit
import PrismCore
import SwiftUI

enum BrowserManagementPresentation {
    static func browsers(
        discovered: [BrowserDescriptor], custom: [BrowserDescriptor]
    ) -> [BrowserDescriptor] {
        let customRows = custom.map { browser in
            let available = discovered.contains {
                $0.id == browser.id && $0.applicationURL.standardizedFileURL == browser.applicationURL.standardizedFileURL
            }
            return BrowserDescriptor(id: browser.id, bundleIdentifier: browser.bundleIdentifier, displayName: browser.displayName, applicationURL: browser.applicationURL, securityScopedBookmark: browser.securityScopedBookmark, origin: .custom, availability: available ? .available : .unavailable, selectorOrder: browser.selectorOrder)
        }
        return discovered.filter { browser in
            !custom.contains {
                $0.id == browser.id && $0.applicationURL.standardizedFileURL == browser.applicationURL.standardizedFileURL
            }
        } + customRows
    }
}

struct BrowserManagementSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    let browserCatalog: any BrowserCataloging
    let addCustomBrowser: @MainActor () async -> OnboardingCustomBrowserResult

    @State private var browsers: [BrowserDescriptor] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var pendingRemoval: BrowserDescriptor?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Available browsers")
                        .font(.system(size: 23, weight: .semibold))
                    Text("Prism discovers installed browsers. You can also add one manually.")
                        .font(.system(size: 13))
                        .foregroundStyle(SettingsPalette.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(WorkspaceButtonStyle(kind: .quiet))
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("browsers.done")
            }
            ScrollView {
                SettingsGroup {
                    if browsers.isEmpty {
                        VStack(spacing: 12) {
                            if isLoading {
                                ProgressView("Scanning browsers…")
                            } else {
                                Image(systemName: "safari")
                                    .font(.system(size: 28))
                                Text("No browsers are ready yet")
                                    .font(.headline)
                                Text("Rescan installed applications or add a browser manually.")
                                    .font(.system(size: 13))
                                    .foregroundStyle(SettingsPalette.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 180)
                    } else {
                        ForEach(Array(browsers.enumerated()), id: \.element.applicationURL) { index, browser in
                            browserRow(browser)
                            if index < browsers.count - 1 { SettingsSeparator() }
                        }
                    }
                }
            }
            .frame(maxHeight: 380)
            if let errorMessage {
                Label(LocalizedStringKey(errorMessage), systemImage: "exclamationmark.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(SettingsPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("browsers.error")
            }
            HStack(spacing: 10) {
                Button {
                    Task { await reload() }
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
                .disabled(isLoading)
                .buttonStyle(WorkspaceButtonStyle(kind: .secondary))
                .accessibilityIdentifier("browsers.rescan")
                Spacer()
                Button("Add Custom Browser", systemImage: "plus") {
                    Task {
                        isLoading = true
                        let result = await addCustomBrowser()
                        isLoading = false
                        switch result {
                        case .added: await reload()
                        case .cancelled: break
                        case .failed: errorMessage = "The browser could not be added. Choose an application that can open web links."
                        }
                    }
                }
                .buttonStyle(WorkspaceButtonStyle(kind: .primary))
                .disabled(isLoading)
                .accessibilityIdentifier("browsers.add")
            }
            Text("Removing a custom entry does not uninstall the application.")
                .font(.system(size: 12))
                .foregroundStyle(SettingsPalette.secondary)
        }
        .padding(28)
        .frame(width: 640)
        .background(SettingsPalette.canvas)
        .tint(SettingsPalette.primary)
        .task { await reload() }
        .confirmationDialog("Remove this custom browser?", isPresented: Binding(
            get: { pendingRemoval != nil },
            set: { if !$0 { pendingRemoval = nil } }
        ), titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                guard let pendingRemoval else { return }
                do {
                    try environment.browserPreferenceRepository.deleteCustomBrowser(id: pendingRemoval.id)
                    self.pendingRemoval = nil
                    Task { await reload() }
                } catch {
                    errorMessage = "The custom browser could not be removed. Try again."
                }
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: {
            if let pendingRemoval {
                Text(String(format: String(localized: "Remove %@ at %@?\n\nRemoving a custom entry does not uninstall the application."), pendingRemoval.displayName, pendingRemoval.applicationURL.path))
            }
        }
    }

    private func browserRow(_ browser: BrowserDescriptor) -> some View {
        HStack(spacing: 12) {
            ApplicationIconView(bundleIdentifier: browser.bundleIdentifier, fallbackSymbol: "safari", side: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(browser.displayName)
                    .font(.system(size: 14, weight: .medium))
                Text(browser.applicationURL.path)
                    .font(.system(size: 12))
                    .foregroundStyle(SettingsPalette.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(Text(verbatim: browser.applicationURL.path))
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Label(browser.availability == .available ? "Ready" : "Path unavailable", systemImage: browser.availability == .available ? "checkmark.circle" : "exclamationmark.circle")
                .font(.system(size: 12))
                .foregroundStyle(SettingsPalette.secondary)
            if browser.origin == .custom {
                Button("Remove", systemImage: "minus.circle") { pendingRemoval = browser }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(String(format: String(localized: "Remove %@"), browser.displayName)))
                    .accessibilityIdentifier("browsers.remove.\(browser.id.rawValue)")
            }
        }
        .padding(16)
        .frame(minHeight: 72)
    }

    private func reload() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            let discovered = try await browserCatalog.scan()
            let custom = try environment.browserPreferenceRepository.customBrowsers()
            browsers = BrowserManagementPresentation.browsers(discovered: discovered, custom: custom)
        } catch {
            errorMessage = "Browsers could not be loaded. Try scanning again."
        }
    }
}
