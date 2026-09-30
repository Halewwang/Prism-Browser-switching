import AppKit
import PrismCore
import SwiftUI

struct BrowserManagementRowIdentity: Hashable {
    let browserID: BrowserID
    let applicationURL: URL
}

extension BrowserDescriptor {
    var managementRowIdentity: BrowserManagementRowIdentity {
        BrowserManagementRowIdentity(browserID: id, applicationURL: applicationURL.standardizedFileURL)
    }
}

enum BrowserManagementPresentation {
    static func browsers(
        discovered: [BrowserDescriptor], custom: [BrowserDescriptor]
    ) -> [BrowserDescriptor] {
        let customRows = custom.map { browser in
            let available = discovered.contains {
                $0.id == browser.id && $0.applicationURL.standardizedFileURL == browser.applicationURL.standardizedFileURL
            }
            return BrowserDescriptor(id: browser.id, bundleIdentifier: browser.bundleIdentifier, displayName: browser.displayName, applicationURL: browser.applicationURL, securityScopedBookmark: browser.securityScopedBookmark, origin: .custom, availability: available ? .available : .unavailable, selectorOrder: browser.selectorOrder, profile: browser.profile)
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
    @State private var hiddenBrowserIDs: Set<BrowserID> = []

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
                        ForEach(Array(browsers.enumerated()), id: \.element.managementRowIdentity) { index, browser in
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
            Text("Hidden browsers remain available to routing rules and fallback settings.")
                .font(.system(size: 12))
                .foregroundStyle(SettingsPalette.secondary)
        }
        .padding(28)
        .frame(width: 760)
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
            Toggle("Show in selector", isOn: Binding(
                get: { !hiddenBrowserIDs.contains(browser.id) },
                set: { setVisible($0, browser: browser) }
            ))
            .toggleStyle(.checkbox)
            .font(.system(size: 12))
            .accessibilityIdentifier("browsers.visible.\(browser.id.rawValue)")
            VStack(spacing: 6) {
                Button { move(browser, offset: -1) } label: { Image(systemName: "chevron.up") }
                    .disabled(browsers.first?.managementRowIdentity == browser.managementRowIdentity || browser.availability != .available || isLoading)
                    .accessibilityLabel(Text(String(format: String(localized: "Move %@ earlier"), browser.displayName)))
                    .accessibilityIdentifier("browsers.earlier.\(browser.id.rawValue)")
                Button { move(browser, offset: 1) } label: { Image(systemName: "chevron.down") }
                    .disabled(browsers.last?.managementRowIdentity == browser.managementRowIdentity || browser.availability != .available || isLoading)
                    .accessibilityLabel(Text(String(format: String(localized: "Move %@ later"), browser.displayName)))
                    .accessibilityIdentifier("browsers.later.\(browser.id.rawValue)")
            }
            .buttonStyle(.plain)
            if browser.origin == .custom && browser.profile == nil {
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
            let order = try environment.browserPreferenceRepository.orderedBrowserIDs()
            hiddenBrowserIDs = Set(try environment.browserPreferenceRepository.hiddenBrowserIDs())
            let rows = BrowserManagementPresentation.browsers(discovered: discovered, custom: custom)
            let positions = Dictionary(order.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: min)
            browsers = rows.enumerated().sorted {
                let left = positions[$0.element.id] ?? (order.count + $0.offset)
                let right = positions[$1.element.id] ?? (order.count + $1.offset)
                return left == right ? $0.offset < $1.offset : left < right
            }.map(\.element)
        } catch {
            errorMessage = "Browsers could not be loaded. Try scanning again."
        }
    }

    private func setVisible(_ visible: Bool, browser: BrowserDescriptor) {
        do {
            var hidden = Set(try environment.browserPreferenceRepository.hiddenBrowserIDs())
            if visible { hidden.remove(browser.id) } else { hidden.insert(browser.id) }
            try environment.browserPreferenceRepository.saveHiddenBrowserIDs(hidden.sorted { $0.rawValue < $1.rawValue })
            hiddenBrowserIDs = hidden
            errorMessage = nil
        } catch { errorMessage = "Browser choices could not be saved. Try again." }
    }

    private func move(_ browser: BrowserDescriptor, offset: Int) {
        guard let index = browsers.firstIndex(where: { $0.managementRowIdentity == browser.managementRowIdentity }),
              browsers.indices.contains(index + offset) else { return }
        do {
            var reordered = browsers
            reordered.swapAt(index, index + offset)
            var seen: Set<BrowserID> = []
            let visibleIDs = reordered.map(\.id).filter { seen.insert($0).inserted }
            // Keep preferences for targets that are temporarily unavailable.
            let retained = try environment.browserPreferenceRepository.orderedBrowserIDs().filter { seen.insert($0).inserted }
            try environment.browserPreferenceRepository.saveOrder(visibleIDs + retained)
            browsers = reordered
            errorMessage = nil
        } catch { errorMessage = "Browser choices could not be saved. Try again." }
    }
}
