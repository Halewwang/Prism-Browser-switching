import SwiftUI

struct HistoryView: View {
    @Bindable var model: HistoryViewModel
    let testLink: () -> Void

    var body: some View {
        Group {
            if model.state == .content {
                content
            } else if let pageState = model.pageState {
                PageStateView(model: pageState) { action in
                    if action == AppShellActionID.testLink.rawValue {
                        testLink()
                    } else if action == "history.retryLoad" {
                        Task { await model.load() }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WorkspaceLayout.contentSurface)
        .task { await model.runSession() }
        .alert(
            "History Action Failed",
            isPresented: Binding(
                get: { model.actionMessage != nil },
                set: { if !$0 { model.dismissActionMessage() } }
            )
        ) {
            Button("OK", role: .cancel) { model.dismissActionMessage() }
        } message: {
            Text(LocalizedStringKey(model.actionMessage ?? ""))
        }
        .confirmationDialog(
            confirmationTitle,
            isPresented: Binding(
                get: { model.confirmation != nil },
                set: { if !$0 { model.cancelConfirmation() } }
            )
        ) {
            if case .delete = model.confirmation {
                Button("Delete", role: .destructive) {
                    Task { await model.confirmPendingAction() }
                }
            } else if model.confirmation == .clear {
                Button("Clear History", role: .destructive) {
                    Task { await model.confirmPendingAction() }
                }
            }
            Button("Cancel", role: .cancel) { model.cancelConfirmation() }
        } message: {
            Text(LocalizedStringKey(confirmationMessage))
        }
    }

    private var content: some View {
        PageColumn {
            SystemSettingsPageHeader(
                title: "Recent Links",
                subtitle: "Links handled by Prism appear here with their browser and result.",
                accessibilityIdentifier: "appShell.page.history.heading"
            )
            SettingsGroup {
                ForEach(Array(model.entries.enumerated()), id: \.element.id) { index, entry in
                    HistoryRow(
                        entry: entry,
                        presentation: model.presentation(for: entry),
                        isRetryAvailable: model.retryableRequestIDs.contains(entry.requestID),
                        isPerformingAction: model.isPerformingAction(for: entry),
                        activity: model.activity(for: entry),
                        canReopen: model.canReopen(entry),
                        reopenDisabledReason: model.reopenDisabledReason(for: entry),
                        canDelete: model.canDelete(entry),
                        deleteDisabledReason: model.deleteDisabledReason(for: entry),
                        retry: { Task { await model.retry(entry) } },
                        reopen: { Task { await model.reopen(entry) } },
                        copyURL: { model.copyURL(entry) },
                        createRule: { model.createRule(entry) },
                        delete: { model.requestDelete(entry) }
                    )
                    if index < model.entries.count - 1 {
                        SettingsSeparator(leadingInset: 16)
                    }
                }
            }
            HStack {
                Spacer()
                Button(role: .destructive) {
                    model.requestClear()
                } label: {
                    if model.isClearing {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Clearing…")
                        }
                    } else {
                        Text("Clear History")
                    }
                }
                .disabled(!model.canClear)
                .accessibilityIdentifier("history.clear")
                .accessibilityValue(model.isClearing ? "Clearing" : "Ready")
                .accessibilityHint(model.canClear
                    ? "Clear all saved History"
                    : "Clear is unavailable while Prism can still complete or retry a link. Complete or cancel that link first.")
            }
        }
    }

    private var confirmationTitle: String {
        switch model.confirmation {
        case .delete: "Delete this History item?"
        case .clear: "Clear all History?"
        case nil: "Confirm History action"
        }
    }

    private var confirmationMessage: String {
        switch model.confirmation {
        case .delete:
            "The saved History item and its recoverable History data will be removed."
        case .clear:
            "All saved History and recoverable History data will be removed. This cannot be undone."
        case nil:
            ""
        }
    }
}
