import AppKit
import PrismCore
import SwiftUI

struct HistoryRow: View {
    let entry: HistoryEntry
    let presentation: HistoryRowPresentation
    let isRetryAvailable: Bool
    let isPerformingAction: Bool
    let activity: HistoryRowActivity?
    let canReopen: Bool
    let reopenDisabledReason: String
    let canDelete: Bool
    let deleteDisabledReason: String
    let retry: () -> Void
    let reopen: () -> Void
    let copyURL: () -> Void
    let createRule: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(urlText)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .accessibilityLabel("Saved URL: \(urlText)")
                    .accessibilityIdentifier("\(accessibilityPrefix).url")

                HStack(spacing: 6) {
                    ApplicationIconView(
                        bundleIdentifier: entry.sourceBundleIdentifier,
                        fallbackSymbol: "app.dashed",
                        side: 16
                    )
                    Text(entry.sourceDisplayName)
                        .lineLimit(1)
                    Image(systemName: "arrow.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                    ApplicationIconView(
                        bundleIdentifier: entry.targetBrowserID?.rawValue,
                        fallbackSymbol: "safari",
                        side: 16
                    )
                    Text(targetText)
                        .lineLimit(1)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Source \(entry.sourceDisplayName), target \(targetText)")

                Text(metaText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let failureReason = entry.failureReason,
                   entry.result == .failure || SelectorReasonCopy.message(forPersistenceCode: failureReason) != nil {
                    Text(LocalizedStringKey(failureReasonText(failureReason)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("Failure: \(failureReasonText(failureReason))")
                }

                if activity == .deleting {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Deleting…")
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(.secondary)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Deleting History item")
                    .accessibilityValue("Deleting")
                }

                if entry.result == .failure || entry.result == .cancelled {
                    HStack(spacing: 8) {
                        if entry.result == .failure {
                            Button(action: retry) {
                                actionLabel(
                                    idleTitle: "Retry",
                                    busyTitle: "Retrying…",
                                    isBusy: activity == .retrying
                                )
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!isRetryAvailable || isPerformingAction)
                            .accessibilityIdentifier("\(accessibilityPrefix).retry")
                            .accessibilityValue(activity == .retrying ? "Retrying" : "Ready")
                            .accessibilityHint(isRetryAvailable
                                ? "Retry with the browser selected for this request"
                                : "The original full URL is no longer available for retry")
                        }
                        if entry.result == .cancelled {
                            Button(action: reopen) {
                                actionLabel(
                                    idleTitle: "Reopen",
                                    busyTitle: "Reopening…",
                                    isBusy: activity == .reopening
                                )
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!canReopen || isPerformingAction)
                            .accessibilityIdentifier("\(accessibilityPrefix).reopen")
                            .accessibilityValue(activity == .reopening ? "Reopening" : "Ready")
                            .accessibilityHint(canReopen ? "Reopen the saved safe URL" : reopenDisabledReason)
                        }
                    }
                }

                if entry.result == .failure, !isRetryAvailable {
                    Text("Retry is unavailable because the original link is no longer in the recovery queue.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if entry.result == .cancelled, !canReopen {
                    Text(reopenDisabledReason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 8) {
                statusLabel
                Menu {
                    secondaryActions
                } label: {
                    Label("More actions", systemImage: "ellipsis.circle")
                        .labelStyle(.iconOnly)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel("More actions for \(urlText)")
                .accessibilityIdentifier("\(accessibilityPrefix).more")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contextMenu { secondaryActions }
    }

    @ViewBuilder
    private var secondaryActions: some View {
        if entry.result == .failure {
            Button("Retry", action: retry)
                .disabled(!isRetryAvailable || isPerformingAction)
                .accessibilityHint(isRetryAvailable
                    ? "Retry with the browser selected for this request"
                    : "The original full URL is no longer available for retry")
        }
        if entry.result == .cancelled {
            Button("Reopen", action: reopen)
                .disabled(!canReopen || isPerformingAction)
                .accessibilityHint(canReopen ? "Reopen the saved safe URL" : reopenDisabledReason)
        }
        Button("Copy Safe URL", action: copyURL)
            .disabled(!presentation.canCopy)
            .accessibilityHint(presentation.canCopy
                ? "Copy the safe saved URL"
                : "Copy is unavailable because no safe HTTP or HTTPS URL was saved")
        Button("Create Rule for This Domain", action: createRule)
            .disabled(!presentation.canCreateRule)
            .accessibilityHint(presentation.canCreateRule
                ? "Create a rule for the saved domain"
                : "A rule cannot be created because no safe saved host is available")
        Divider()
        Button("Delete", role: .destructive, action: delete)
            .disabled(!canDelete || isPerformingAction)
            .accessibilityIdentifier("\(accessibilityPrefix).delete")
            .accessibilityHint(canDelete ? "Delete this saved History item" : deleteDisabledReason)
    }

    private var statusLabel: some View {
        Label {
            Text(LocalizedStringKey(resultText))
        } icon: {
            Image(systemName: statusSymbol)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(statusColor)
        .labelStyle(.titleAndIcon)
        .accessibilityLabel("Result: \(resultText)")
    }

    private var urlText: String {
        presentation.urlText
    }

    private var targetText: String {
        entry.targetDisplayName ?? String(localized: "No browser selected")
    }

    private var metaText: String {
        var parts = [localized(methodText), timeText]
        if entry.attemptCount > 0 {
            let format = localized("Attempt %d")
            parts.append(String(format: format, entry.attemptCount))
        }
        return parts.joined(separator: " · ")
    }

    private func localized(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }

    private var accessibilityPrefix: String {
        "history.row.\(entry.id.uuidString)"
    }

    @ViewBuilder
    private func actionLabel(idleTitle: String, busyTitle: String, isBusy: Bool) -> some View {
        if isBusy {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text(LocalizedStringKey(busyTitle))
            }
        } else {
            Text(LocalizedStringKey(idleTitle))
        }
    }

    private var resultText: String {
        switch entry.result {
        case .processing: "Processing"
        case .success: "Opened"
        case .failure: "Failed"
        case .cancelled: "Cancelled"
        }
    }

    private var statusSymbol: String {
        switch entry.result {
        case .processing: "hourglass"
        case .success: "checkmark.circle.fill"
        case .failure: "exclamationmark.triangle.fill"
        case .cancelled: "xmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch entry.result {
        case .processing: .secondary
        case .success: .green
        case .failure: .red
        case .cancelled: .secondary
        }
    }

    private var methodText: String {
        switch entry.method {
        case .urlRule: "URL rule"
        case .sourceRule: "Source rule"
        case .manual: "Manual"
        case .preferredBrowser: "Preferred browser"
        case .lastUsedBrowser: "Last used browser"
        case nil: "No route selected"
        }
    }

    private var timeText: String {
        (entry.completedAt ?? entry.createdAt).formatted(date: .abbreviated, time: .shortened)
    }

    private func failureReasonText(_ reason: String) -> String {
        if let message = SelectorReasonCopy.message(forPersistenceCode: reason) {
            return message
        }
        return switch reason {
        case "launch_failed": "The selected browser did not accept the link."
        case "outcome_unknown": "Prism could not confirm whether the browser opened the link."
        default: "The link could not be opened."
        }
    }
}
