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
                Text("Available browsers")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(SettingsPalette.secondary)
                    .frame(height: 33, alignment: .leading)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14))
                        .frame(width: 24, height: 33)
                }
                    .buttonStyle(WorkspaceButtonStyle(kind: .quiet, height: 33))
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel("Close")
                    .accessibilityIdentifier("browsers.done")
            }
            Text("Prism discovers installed browsers. You can also add one manually.")
                .font(.system(size: 12))
                .foregroundStyle(SettingsPalette.muted)
                .frame(height: 19, alignment: .leading)
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
                            if index < browsers.count - 1 { SettingsSeparator(color: SettingsPalette.sidebar) }
                        }
                    }
                }
            }
            .frame(height: 307)
            HStack(spacing: 10) {
                Button {
                    Task { await reload() }
                } label: {
                    Text("Rescan")
                }
                .disabled(isLoading)
                .buttonStyle(WorkspaceButtonStyle(kind: .secondary, height: 39))
                .accessibilityIdentifier("browsers.rescan")
                Button("browsers.addButton") {
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
                .buttonStyle(WorkspaceButtonStyle(kind: .primary, height: 39))
                .disabled(isLoading)
                .accessibilityIdentifier("browsers.add")
                Spacer()
            }
            Label {
                Text(LocalizedStringKey(errorMessage ?? "Choose a browser .app in the macOS file picker."))
                    .font(.system(size: 11))
                    .foregroundStyle(errorMessage == nil ? SettingsPalette.muted : SettingsPalette.danger)
            } icon: {
                Image(systemName: errorMessage == nil ? "folder" : "exclamationmark.circle")
                    .foregroundStyle(SettingsPalette.iconDefault)
            }
            .padding(15)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .background(SettingsPalette.window, in: RoundedRectangle(cornerRadius: 8))
            .accessibilityIdentifier(errorMessage == nil ? "browsers.pickerHint" : "browsers.error")
            Text("Removing a custom entry does not uninstall the application. Detected browsers do not need to be added manually.")
                .font(.system(size: 11))
                .foregroundStyle(SettingsPalette.muted)
                .frame(height: 18, alignment: .leading)
        }
        .padding(28)
        .frame(width: 666, height: 630)
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
            ApplicationIconView(bundleIdentifier: browser.bundleIdentifier, applicationURL: browser.applicationURL, fallbackSymbol: "safari", side: 28)
            VStack(alignment: .leading, spacing: 6) {
                Text(browser.displayName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(SettingsPalette.secondary)
                Text(browser.origin == .custom && browser.availability != .available
                     ? String(localized: "browsers.reselectApplication") : browser.applicationURL.path)
                    .font(.system(size: 11))
                    .foregroundStyle(SettingsPalette.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(Text(verbatim: browser.applicationURL.path))
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(browser.availability == .available ? "browsers.available" : "Path unavailable")
                .font(.system(size: 11))
                .foregroundStyle(browser.availability == .available ? SettingsPalette.tertiary : SettingsPalette.danger)
            if browser.origin == .custom && browser.profile == nil {
                Menu { browserActions(browser) } label: {
                    Image(systemName: "ellipsis").frame(width: 24, height: 24)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("More actions for \(browser.displayName)")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 76)
        .contextMenu { browserActions(browser) }
    }

    @ViewBuilder
    private func browserActions(_ browser: BrowserDescriptor) -> some View {
        Toggle("Show in selector", isOn: Binding(
            get: { !hiddenBrowserIDs.contains(browser.id) },
            set: { setVisible($0, browser: browser) }
        ))
        .accessibilityIdentifier("browsers.visible.\(browser.id.rawValue)")
        Button(String(format: String(localized: "Move %@ earlier"), browser.displayName)) { move(browser, offset: -1) }
            .disabled(browsers.first?.managementRowIdentity == browser.managementRowIdentity || browser.availability != .available || isLoading)
            .accessibilityIdentifier("browsers.earlier.\(browser.id.rawValue)")
        Button(String(format: String(localized: "Move %@ later"), browser.displayName)) { move(browser, offset: 1) }
            .disabled(browsers.last?.managementRowIdentity == browser.managementRowIdentity || browser.availability != .available || isLoading)
            .accessibilityIdentifier("browsers.later.\(browser.id.rawValue)")
        if browser.origin == .custom && browser.profile == nil {
            Divider()
            Button("Remove", role: .destructive) { pendingRemoval = browser }
                .accessibilityIdentifier("browsers.remove.\(browser.id.rawValue)")
        }
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
