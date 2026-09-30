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
    var currentRules: [RoutingRule]? = nil
    var editRule: (() -> Void)? = nil

    @State private var showsDetails = false

    var body: some View {
        HStack(spacing: 14) {
            Button { showsDetails = true } label: {
                detailsButtonContent
                    .frame(minHeight: 84)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(Text(rowAccessibilityLabel))
            .accessibilityHint(Text("View Details"))
            .accessibilityIdentifier("\(accessibilityPrefix).url")
            Menu {
                Button("View Details") { showsDetails = true }
                Divider()
                secondaryActions
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("More actions for \(urlText)")
            .accessibilityIdentifier("\(accessibilityPrefix).more")
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 84)
        .accessibilityAction(named: Text("View Details")) { showsDetails = true }
        .contextMenu {
            Button("View Details") { showsDetails = true }
            Divider()
            secondaryActions
        }
        .sheet(isPresented: $showsDetails) { details }
        .onDisappear { showsDetails = false }
    }

    private var detailsButtonContent: some View {
        HStack(spacing: 14) {
            Image(systemName: "globe")
                .font(.system(size: 17))
                .foregroundStyle(SettingsPalette.secondary)
                .frame(width: 34, height: 34)
                .background(SettingsPalette.iconWell, in: RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Text(presentation.safeHost ?? localized("URL not saved"))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(SettingsPalette.primary)
                        .lineLimit(1)
                        .layoutPriority(1)
                    if let safeURL = presentation.safeURL, !safeURL.path.isEmpty, safeURL.path != "/" {
                        Text(safeURL.path)
                            .font(.system(size: 12))
                            .foregroundStyle(SettingsPalette.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                HStack(spacing: 6) {
                    ApplicationIconView(bundleIdentifier: entry.sourceBundleIdentifier, fallbackSymbol: "app.dashed", side: 16)
                    Text(displayedSource).lineLimit(1)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .medium))
                        .accessibilityHidden(true)
                    ApplicationIconView(bundleIdentifier: entry.targetBrowserID?.rawValue, fallbackSymbol: "safari", side: 16)
                    Text(targetText).lineLimit(1)
                    Text("·")
                    Text(LocalizedStringKey(methodText)).lineLimit(1)
                }
                .font(.system(size: 13))
                .foregroundStyle(SettingsPalette.secondary)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 7) {
                statusLabel
                Text(HistoryListPresentation.eventDate(for: entry), format: .dateTime.hour().minute())
                    .font(.system(size: 12))
                    .foregroundStyle(SettingsPalette.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 20) {
            detailsHeader
            ScrollView {
                detailsContent
                    .padding(.trailing, 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            detailsFooter
        }
        .foregroundStyle(SettingsPalette.primary)
        .padding(28)
        .frame(width: 640, height: 620)
        .background(SettingsPalette.canvas)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("\(accessibilityPrefix).details")
    }

    private var detailsHeader: some View {
        HStack {
            Text("Link Details")
                .font(.system(size: 23, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button { showsDetails = false } label: {
                Image(systemName: "xmark").font(.system(size: 12))
            }
            .buttonStyle(WorkspaceButtonStyle(kind: .quiet))
            .keyboardShortcut(.cancelAction)
            .foregroundStyle(SettingsPalette.secondary)
            .accessibilityLabel("Close")
            .accessibilityIdentifier("\(accessibilityPrefix).details.close")
        }
    }

    private var detailsContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                statusLabel
                if let reason = entry.failureReason,
                   entry.result == .failure || SelectorReasonCopy.message(forPersistenceCode: reason) != nil {
                    Text(LocalizedStringKey(failureReasonText(reason)))
                        .font(.system(size: 12))
                        .foregroundStyle(SettingsPalette.secondary)
                        .accessibilityLabel("Failure: \(failureReasonText(reason))")
                }
                if activity == .deleting {
                    Label("Deleting…", systemImage: "hourglass")
                        .font(.system(size: 12))
                        .accessibilityLabel("Deleting History item")
                        .accessibilityValue("Deleting")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(SettingsPalette.iconWell, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 8) {
                Text("Saved Safe URL")
                    .font(.system(size: 11))
                    .foregroundStyle(SettingsPalette.secondary)
                Text(urlText)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("\(accessibilityPrefix).details.url")
                Text("Sensitive parameters such as login tokens are hidden from history and copied URLs.")
                    .font(.system(size: 11))
                    .foregroundStyle(SettingsPalette.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SettingsPalette.group, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(SettingsPalette.border, lineWidth: 1))
            routingExplanationSection
            VStack(spacing: 14) {
                detailField("Source App", value: displayedSource, bundleIdentifier: entry.sourceBundleIdentifier)
                detailField("Target Browser", value: targetText, bundleIdentifier: entry.targetBrowserID?.rawValue)
                detailField("Routing Method", value: localized(methodText))
                detailField("Result", value: localized(resultText))
                detailField("Time", value: timeText)
                detailField("Attempts", value: String(format: localized("Attempt %d"), entry.attemptCount))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var detailsFooter: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button("Copy Safe URL", action: copyURL)
                    .disabled(!presentation.canCopy)
                    .help(presentation.canCopy ? localized("Copy the safe saved URL") : localized("Copy is unavailable because no safe HTTP or HTTPS URL was saved"))
                Spacer(minLength: 0)
                recoveryButton
            }
            .buttonStyle(WorkspaceButtonStyle(kind: .secondary))
            HStack(spacing: 8) {
                Button("Create Rule for This Domain") {
                    showsDetails = false
                    createRule()
                }
                .disabled(!presentation.canCreateRule)
                .help(presentation.canCreateRule ? localized("Create a rule for the saved domain") : localized("A rule cannot be created because no safe saved host is available"))
                if case .current = routingExplanation.ruleReference, let editRule {
                    Button(String(localized: "history.explanation.edit", defaultValue: "Edit Current Rule")) {
                        showsDetails = false
                        editRule()
                    }
                    .accessibilityIdentifier("\(accessibilityPrefix).editRule")
                }
                Spacer(minLength: 0)
            }
            .buttonStyle(WorkspaceButtonStyle(kind: .secondary))
            recoveryExplanation
        }
    }

    private var displayedSource: String {
        entry.sourceDisplayName == "Unknown"
            ? String(localized: "selector.source.unknown", defaultValue: "Unknown source")
            : entry.sourceDisplayName
    }

    private var routingExplanation: HistoryRoutingExplanation {
        HistoryRoutingExplanation(entry: entry, currentRules: currentRules)
    }

    private var routingExplanationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "history.explanation.title", defaultValue: "Why this browser?"))
                .font(.system(size: 13, weight: .semibold))
            Text("\(displayedSource) → \(localized(methodText)) → \(targetText)")
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
            Text(routingExplanation.methodExplanation)
                .font(.system(size: 12))
            switch routingExplanation.ruleReference {
            case let .current(rule):
                Text(String(format: String(localized: "history.explanation.currentRule", defaultValue: "Current rule: %@"), rule.label ?? RuleEditorDraft(rule: rule, browsers: []).matchValue))
                    .font(.system(size: 12, weight: .medium))
                Text(RuleEditorDraft(rule: rule, browsers: []).scopeDescription)
                    .font(.system(size: 12))
                snapshotLimitation
            case .missing:
                Text(String(localized: "history.explanation.deleted", defaultValue: "The recorded rule has been deleted."))
                    .font(.system(size: 12))
                snapshotLimitation
            case .unavailable:
                Text(String(localized: "history.explanation.unavailable", defaultValue: "The current rule could not be read."))
                    .font(.system(size: 12))
                snapshotLimitation
            case .notRecorded:
                Text(String(localized: "history.explanation.noID", defaultValue: "This record has no matched rule ID, so its rule cannot be identified."))
                    .font(.system(size: 12))
            case .notApplicable:
                EmptyView()
            }
        }
        .foregroundStyle(SettingsPalette.secondary)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SettingsPalette.iconWell, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityIdentifier("\(accessibilityPrefix).details.explanation")
    }

    private var snapshotLimitation: some View {
        Text(String(localized: "history.explanation.noSnapshot", defaultValue: "History saved the method, browser and rule ID, but not the rule's conditions. The current rule may have changed; it is not a snapshot of that time."))
            .font(.system(size: 12))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func detailField(_ title: String, value: String, bundleIdentifier: String? = nil) -> some View {
        HStack(spacing: 10) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 12))
                .foregroundStyle(SettingsPalette.secondary)
            Spacer()
            if let bundleIdentifier {
                ApplicationIconView(bundleIdentifier: bundleIdentifier, fallbackSymbol: "app.dashed", side: 16)
            }
            Text(value)
                .font(.system(size: 13))
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
        }
    }

    @ViewBuilder
    private var recoveryButton: some View {
        if entry.result == .failure {
            Button {
                showsDetails = false
                retry()
            } label: {
                actionLabel(idleTitle: "Retry", busyTitle: "Retrying…", isBusy: activity == .retrying)
            }
            .buttonStyle(WorkspaceButtonStyle(kind: .primary))
            .disabled(!isRetryAvailable || isPerformingAction)
            .accessibilityIdentifier("\(accessibilityPrefix).retry")
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(activity == .retrying ? "Retrying" : "Ready")
            .accessibilityHint(isRetryAvailable ? "Retry with the browser selected for this request" : "The original full URL is no longer available for retry")
        } else if entry.result == .cancelled {
            Button {
                showsDetails = false
                reopen()
            } label: {
                actionLabel(idleTitle: "Reopen", busyTitle: "Reopening…", isBusy: activity == .reopening)
            }
            .buttonStyle(WorkspaceButtonStyle(kind: .primary))
            .disabled(!canReopen || isPerformingAction)
            .accessibilityIdentifier("\(accessibilityPrefix).reopen")
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(activity == .reopening ? "Reopening" : "Ready")
            .accessibilityHint(canReopen ? "Reopen the saved safe URL" : reopenDisabledReason)
        }
    }

    @ViewBuilder
    private var recoveryExplanation: some View {
        if entry.result == .failure {
            Label {
                Text(LocalizedStringKey(isRetryAvailable
                    ? "Retry is available while the original link remains in the recovery queue."
                    : "Retry is unavailable because the original link is no longer in the recovery queue."))
            } icon: {
                Image(systemName: "lock")
            }
                .font(.system(size: 11))
                .foregroundStyle(SettingsPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else if entry.result == .cancelled, !canReopen {
            Text(LocalizedStringKey(reopenDisabledReason))
                .font(.system(size: 11))
                .foregroundStyle(SettingsPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var secondaryActions: some View {
        if entry.result == .failure {
            Button("Retry", action: retry)
                .accessibilityIdentifier("\(accessibilityPrefix).retry")
                .disabled(!isRetryAvailable || isPerformingAction)
                .accessibilityHint(isRetryAvailable
                    ? "Retry with the browser selected for this request"
                    : "The original full URL is no longer available for retry")
        }
        if entry.result == .cancelled {
            Button("Reopen", action: reopen)
                .accessibilityIdentifier("\(accessibilityPrefix).reopen")
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
        HStack(spacing: 4) {
            if isPerformingAction {
                ProgressView().controlSize(.mini)
            } else {
                Image(systemName: statusSymbol).accessibilityHidden(true)
            }
            Text(LocalizedStringKey(resultText))
        }
        .font(.system(size: 12))
        .foregroundStyle(SettingsPalette.secondary)
        .accessibilityLabel("Result: \(resultText)")
    }

    private var urlText: String {
        presentation.safeURL?.absoluteString ?? localized("URL not saved")
    }

    private var rowAccessibilityLabel: String {
        String(
            format: localized("Saved URL: %@. Source: %@. Target: %@. Result: %@. Time: %@."),
            urlText,
            entry.sourceDisplayName,
            targetText,
            localized(resultText),
            timeText
        )
    }

    private var targetText: String {
        entry.targetDisplayName ?? String(localized: "No browser selected")
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
