import AppKit
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
                VStack(alignment: .leading, spacing: 18) {
                    browserPreviewCard
                    browserList
                }
                .padding(.horizontal, WorkspaceLayout.contentInset)
                .padding(.bottom, 20)
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
        HStack(spacing: 12) {
            browserIcon(browser, size: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(browser.displayName)
                    .font(.body.weight(.medium))
                Text("\(selectorIndex(for: browser) + 1)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(browser.origin.displayName)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .tag(browser.id)
        .accessibilityIdentifier("browsers.row.\(browser.id.rawValue)")
        .listRowBackground(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selectedBrowserID == browser.id ? WorkspacePalette.rowSelection : Color.clear)
        )
        .listRowSeparator(.hidden)
    }

    private var browserPreviewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            WorkspaceWindowPreview(accessibilityIdentifier: "browsers.inspector") {
                HStack(spacing: 10) {
                    ForEach(Array(browsers.prefix(3).enumerated()), id: \.element.id) { index, browser in
                        VStack(spacing: 8) {
                            Text("\(index + 1)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(index == 0 ? WorkspacePalette.accent : Color.secondary)
                            WorkspacePreviewTile(
                                title: browser.displayName,
                                icon: NSWorkspace.shared.icon(forFile: browser.applicationURL.path),
                                isHighlighted: selectedBrowserID == browser.id || (selectedBrowserID == nil && index == 0)
                            )
                        }
                    }
                }
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
        List(selection: $selectedBrowserID) {
            ForEach(browsers, id: \.id) { browser in
                browserRow(browser)
            }
            .onMove(perform: move)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
