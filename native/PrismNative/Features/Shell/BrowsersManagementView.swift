import PrismCore
import SwiftUI

struct BrowsersManagementView: View {
    @Environment(AppEnvironment.self) private var environment

    let browserCatalog: any BrowserCataloging
    let addCustomBrowser: @MainActor () async -> OnboardingCustomBrowserResult
    let openApplicationsFolder: () -> Void

    @State private var browsers: [BrowserDescriptor] = []
    @State private var selectedBrowserID: BrowserID?
    @State private var isLoading = true
    @State private var isAddingBrowser = false
    @State private var browserPendingDeletion: BrowserDescriptor?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            header
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
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        browserPreviewCard
                        browserList
                    }
                    .padding(.horizontal, WorkspaceLayout.contentInset)
                    .padding(.bottom, 28)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .tint(.primary)
        .background(WorkspacePalette.canvas)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            headingIdentifier: "appShell.page.browsers.heading"
        ) {
            HStack(spacing: 8) {
                Button("Rescan", systemImage: "arrow.clockwise") {
                    Task { await reload() }
                }
                .buttonStyle(WorkspaceSecondaryCapsuleStyle())
                .disabled(isLoading || isAddingBrowser)
                .accessibilityIdentifier("browsers.rescan")
                Button("Add Browser", systemImage: "plus") {
                    Task { await addBrowser() }
                }
                .buttonStyle(WorkspacePrimaryCapsuleStyle())
                .disabled(isAddingBrowser)
                .accessibilityIdentifier("browsers.addCustomBrowser")
            }
        }
    }

    private var emptyActions: some View {
        HStack {
            Button("Rescan") { Task { await reload() } }
                .buttonStyle(WorkspaceSecondaryCapsuleStyle())
            Button("Add Browser") { Task { await addBrowser() } }
                .buttonStyle(WorkspacePrimaryCapsuleStyle())
            Button("Open Applications Folder", action: openApplicationsFolder)
                .buttonStyle(WorkspaceSecondaryCapsuleStyle())
        }
    }

    @ViewBuilder
    private func browserRow(_ browser: BrowserDescriptor) -> some View {
        Button {
            selectedBrowserID = browser.id
        } label: {
            HStack(spacing: 12) {
                WorkspaceBrowserIcon(browser: browser, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(browser.displayName)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(WorkspaceCopy.selectorPosition(
                        order: selectorIndex(for: browser),
                        count: browsers.count
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if selectorIndex(for: browser) < 9 {
                    KeyboardShortcutBadge(number: selectorIndex(for: browser) + 1)
                }
                Text(browser.origin.displayName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, WorkspaceLayout.listRowVerticalPadding)
            .background(
                selectedBrowserID == browser.id ? WorkspacePalette.rowSelection : Color.clear,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("browsers.row.\(browser.id.rawValue)")
        .draggable(browser.id.rawValue)
        .dropDestination(for: String.self) { items, _ in
            guard let rawValue = items.first else { return false }
            move(rawValue, before: browser.id)
            return true
        }
    }

    private var browserPreviewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            WorkspacePreviewCard(accessibilityIdentifier: "browsers.inspector") {
                WorkspaceScaledSelectorPreview(
                    browsers: browsers,
                    selectedID: selectedBrowserID ?? browsers.first?.id,
                    sourceName: "Safari",
                    sourceIcon: WorkspaceApplicationIcon.nsImage(bundleIdentifier: "com.apple.Safari"),
                    urlText: "https://example.com",
                    showsShortcuts: true
                )
            }
            Text("Drag browsers into the order you want Prism to show them. Numbers in the selector follow this order.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let browser = selectedBrowser, browser.origin == .custom {
                Button("Remove \(browser.displayName)", systemImage: "trash", role: .destructive) {
                    browserPendingDeletion = browser
                }
                .buttonStyle(WorkspaceSecondaryCapsuleStyle())
                .accessibilityLabel("Remove \(browser.displayName)")
            }
        }
    }

    private var browserList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(browsers, id: \.id) { browser in
                browserRow(browser)
            }
        }
    }

    private var selectedBrowser: BrowserDescriptor? {
        browsers.first(where: { $0.id == selectedBrowserID })
    }

    private func selectorIndex(for browser: BrowserDescriptor) -> Int {
        browsers.firstIndex(where: { $0.id == browser.id }) ?? browser.selectorOrder
    }

    private func move(_ rawID: String, before targetID: BrowserID) {
        let sourceID = BrowserID(rawValue: rawID)
        guard sourceID != targetID,
              let source = browsers.firstIndex(where: { $0.id == sourceID }),
              let destination = browsers.firstIndex(where: { $0.id == targetID })
        else { return }
        browsers.move(fromOffsets: IndexSet(integer: source), toOffset: destination > source ? destination + 1 : destination)
        persistOrder()
    }

    private func persistOrder() {
        do {
            try environment.browserPreferenceRepository.saveOrder(browsers.map(\.id))
        } catch {
            errorMessage = "Prism could not save the browser order."
            Task { await reload() }
        }
    }

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            browsers = try await browserCatalog.scan()
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
