import AppKit
import PrismCore
import SwiftUI

struct BrowsersManagementView: View {
    @Environment(AppEnvironment.self) private var environment

    let browserCatalog: any BrowserCataloging
    let addCustomBrowser: @MainActor () async -> OnboardingCustomBrowserResult
    let openApplicationsFolder: () -> Void

    @State private var browsers: [BrowserDescriptor] = []
    @State private var rules: [RoutingRule] = []
    @State private var selectedBrowserID: BrowserID?
    @State private var isLoading = true
    @State private var isAddingBrowser = false
    @State private var browserPendingDeletion: BrowserDescriptor?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if isLoading {
                ProgressView("Looking for browsers…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if browsers.isEmpty {
                VStack(spacing: 16) {
                    ContentUnavailableView(
                        "No browsers are available",
                        systemImage: "safari",
                        description: Text("Rescan installed applications or add a compatible browser manually.")
                    )
                    emptyActions
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                WorkspaceMasterDetail(inspectorIdentifier: "browsers.inspector") {
                    List(selection: $selectedBrowserID) {
                        Section {
                            ForEach(browsers, id: \.id) { browser in
                                browserRow(browser)
                                    .tag(browser.id)
                            }
                            .onMove(perform: move)
                        } header: {
                            Text("Browser selector order")
                        } footer: {
                            Text("Drag browsers into the order you want Prism to show them. Numbers in the selector follow this order.")
                        }
                    }
                    .listStyle(.inset)
                    .scrollContentBackground(.hidden)
                } inspector: {
                    browserInspector
                }
            }
        }
        .task { await reload() }
        .confirmationDialog(
            "Remove this custom browser?",
            isPresented: Binding(
                get: { browserPendingDeletion != nil },
                set: { if !$0 { browserPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove Browser", role: .destructive) {
                if let browserPendingDeletion { delete(browserPendingDeletion) }
            }
            Button("Cancel", role: .cancel) { browserPendingDeletion = nil }
        } message: {
            Text("Prism will stop offering this browser until you add it again.")
        }
        .alert(
            "Browsers could not be updated",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(LocalizedStringKey(errorMessage ?? ""))
        }
    }

    private var header: some View {
        WorkspacePageHeader(
            title: "Browsers",
            subtitle: "Manage the browsers shown in the link selector.",
            headingIdentifier: "appShell.page.browsers.heading"
        ) {
            HStack(spacing: 8) {
                Button("Rescan", systemImage: "arrow.clockwise") {
                    Task { await reload() }
                }
                .disabled(isLoading || isAddingBrowser)
                .accessibilityIdentifier("browsers.rescan")
                Button("Add Browser", systemImage: "plus") {
                    Task { await addBrowser() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isAddingBrowser)
                .accessibilityIdentifier("browsers.addCustomBrowser")
            }
        }
    }

    private var emptyActions: some View {
        HStack {
            Button("Rescan") { Task { await reload() } }
                .buttonStyle(.borderedProminent)
            Button("Add Browser") { Task { await addBrowser() } }
                .buttonStyle(.bordered)
            Button("Open Applications Folder", action: openApplicationsFolder)
                .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private func browserRow(_ browser: BrowserDescriptor) -> some View {
        HStack(spacing: 12) {
            browserIcon(browser, size: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(browser.displayName)
                    .font(.body.weight(.medium))
                Text(browser.applicationURL.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(browser.origin.displayName)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("browsers.row.\(browser.id.rawValue)")
    }

    @ViewBuilder
    private var browserInspector: some View {
        if let browser = selectedBrowser {
            VStack(alignment: .leading, spacing: 16) {
                browserIcon(browser, size: 56)

                VStack(alignment: .leading, spacing: 6) {
                    Text(browser.displayName)
                        .font(.title3.weight(.semibold))
                    HStack(spacing: 8) {
                        WorkspaceStatusPill(
                            title: String(localized: browser.origin.displayName),
                            systemImage: browser.origin == .custom ? "plus.circle" : "internaldrive",
                            tint: .secondary
                        )
                        WorkspaceStatusPill(
                            title: String(localized: browser.availability.displayName),
                            systemImage: browser.availability == .available
                                ? "checkmark.circle.fill"
                                : "exclamationmark.triangle.fill",
                            tint: browser.availability == .available ? .green : .orange
                        )
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    inspectorFact(
                        String(localized: "Application path"),
                        value: browser.applicationURL.path,
                        systemImage: "folder"
                    )
                    inspectorFact(
                        WorkspaceCopy.selectorPosition(order: selectorIndex(for: browser), count: browsers.count),
                        systemImage: "list.number"
                    )
                    if let shortcut = WorkspaceCopy.keyboardShortcut(order: selectorIndex(for: browser)) {
                        inspectorFact(shortcut, systemImage: "keyboard")
                    }
                    inspectorFact(
                        WorkspaceCopy.ruleReferenceCount(rules.filter { $0.targetBrowserID == browser.id }.count),
                        systemImage: "list.bullet.rectangle"
                    )
                }

                if browser.origin == .custom {
                    Button("Remove", systemImage: "trash", role: .destructive) {
                        browserPendingDeletion = browser
                    }
                    .accessibilityLabel("Remove \(browser.displayName)")
                }

                Text("Drag browsers into the order you want Prism to show them. Numbers in the selector follow this order.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            WorkspaceInspectorPlaceholder(
                systemImage: "safari",
                message: "Select a browser to review its selector order and availability."
            )
        }
    }

    private var selectedBrowser: BrowserDescriptor? {
        browsers.first(where: { $0.id == selectedBrowserID })
    }

    private func selectorIndex(for browser: BrowserDescriptor) -> Int {
        browsers.firstIndex(where: { $0.id == browser.id }) ?? browser.selectorOrder
    }

    private func browserIcon(_ browser: BrowserDescriptor, size: CGFloat) -> some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: browser.applicationURL.path))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
            .accessibilityHidden(true)
    }

    private func inspectorFact(_ title: String, value: String? = nil, systemImage: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                if let value {
                    Text(LocalizedStringKey(title))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(value)
                        .font(.callout)
                        .textSelection(.enabled)
                } else {
                    Text(LocalizedStringKey(title))
                        .font(.callout)
                }
            }
        }
    }

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            browsers = try await browserCatalog.scan()
            rules = (try? environment.ruleRepository.all()) ?? []
            selectBrowserIfNeeded()
        } catch {
            errorMessage = "Prism could not scan for web browsers."
        }
    }

    private func selectBrowserIfNeeded() {
        if let selectedBrowserID, browsers.contains(where: { $0.id == selectedBrowserID }) {
            return
        }
        selectedBrowserID = browsers.first?.id
    }

    private func addBrowser() async {
        guard !isAddingBrowser else { return }
        isAddingBrowser = true
        defer { isAddingBrowser = false }
        switch await addCustomBrowser() {
        case .added:
            await reload()
        case .failed:
            errorMessage = "That application could not be added as a web browser."
        case .cancelled:
            break
        }
    }

    private func move(from offsets: IndexSet, to destination: Int) {
        browsers.move(fromOffsets: offsets, toOffset: destination)
        do {
            try environment.browserPreferenceRepository.saveOrder(browsers.map(\.id))
        } catch {
            errorMessage = "Prism could not save the browser order."
            Task { await reload() }
        }
    }

    private func delete(_ browser: BrowserDescriptor) {
        defer { browserPendingDeletion = nil }
        do {
            try environment.browserPreferenceRepository.deleteCustomBrowser(id: browser.id)
            if selectedBrowserID == browser.id {
                selectedBrowserID = nil
            }
            Task { await reload() }
        } catch {
            errorMessage = "Prism could not remove this custom browser."
        }
    }
}
