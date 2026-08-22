import PrismCore
import SwiftUI

struct BrowsersManagementView: View {
    @Environment(AppEnvironment.self) private var environment

    let browserCatalog: any BrowserCataloging
    let addCustomBrowser: @MainActor () async -> OnboardingCustomBrowserResult
    let openApplicationsFolder: () -> Void

    @State private var browsers: [BrowserDescriptor] = []
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
                List {
                    Section {
                        ForEach(browsers, id: \.id) { browser in
                            browserRow(browser)
                        }
                        .onMove(perform: move)
                    } header: {
                        Text("Browser selector order")
                    } footer: {
                        Text("Drag browsers into the order you want Prism to show them. Numbers in the selector follow this order.")
                    }
                }
                .listStyle(.inset)
                .padding(16)
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
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Browsers")
                    .font(WorkspaceLayout.pageTitleFont)
                    .accessibilityIdentifier("appShell.page.browsers.heading")
                Text("Manage the browsers shown in the link selector.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 20)
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
        .padding(.horizontal, WorkspaceLayout.contentInset)
        .padding(.vertical, WorkspaceLayout.headerVerticalInset)
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
        HStack(spacing: 14) {
            Image(systemName: browser.availability == .available ? "safari" : "exclamationmark.triangle")
                .frame(width: 22)
                .foregroundStyle(browser.availability == .available ? Color.accentColor : Color.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(browser.displayName)
                    .font(.body.weight(.medium))
                Text(browser.applicationURL.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(browser.origin == .custom ? LocalizedStringKey("Custom") : LocalizedStringKey("Installed"))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary, in: Capsule())
            if browser.availability == .unavailable {
                Text("Unavailable")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
            }
            if browser.origin == .custom {
                Button("Remove", systemImage: "trash") {
                    browserPendingDeletion = browser
                }
                .labelStyle(.iconOnly)
                .foregroundStyle(.red)
                .accessibilityLabel("Remove \(browser.displayName)")
            }
        }
        .padding(.vertical, 8)
    }

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            browsers = try await browserCatalog.scan()
        } catch {
            errorMessage = "Prism could not scan for web browsers."
        }
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
            Task { await reload() }
        } catch {
            errorMessage = "Prism could not remove this custom browser."
        }
    }
}
