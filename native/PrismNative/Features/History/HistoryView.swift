import PrismCore
import SwiftUI

struct HistoryView: View {
    @Environment(AppEnvironment.self) private var environment
    @Bindable var model: HistoryViewModel
    let testLink: () -> Void
    @State private var query = ""
    @State private var resultFilter: HistoryResultFilter = .all

    var body: some View {
        Group {
            if model.state == .content {
                content
            } else if let pageState = historyPageState {
                PageColumn {
                    SystemSettingsPageHeader(
                        title: "History",
                        subtitle: "Every link has a story.",
                        accessibilityIdentifier: "appShell.page.history.heading"
                    )
                    PageStateView(model: pageState) { action in
                        if action == AppShellActionID.testLink.rawValue {
                            testLink()
                        } else if action == "history.openSettings" {
                            environment.updateRoute(.settings)
                        } else if action == "history.retryLoad" {
                            Task { await model.load() }
                        }
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

    private var historyPageState: PageStateModel? {
        if model.state == .empty, !environment.settings.historyEnabled {
            return .empty(
                iconSystemName: "shield.slash",
                title: "History recording is paused",
                message: "New links are not being saved. You can turn history back on in Settings.",
                actions: [PageStateAction(id: "history.openSettings", title: "Open Settings", accessibilityIdentifier: "history.openSettings")]
            )
        }
        return model.pageState
    }

    private var content: some View {
        PageColumn {
            SystemSettingsPageHeader(
                title: "History",
                subtitle: "Every link has a story.",
                accessibilityIdentifier: "appShell.page.history.heading"
            )
            HStack(spacing: 16) {
                WorkspaceSearchField(placeholder: "Search URL, source app, or browser", text: $query)
                    .frame(width: 340)
                    .accessibilityIdentifier("history.search")
                Spacer(minLength: 0)
                clearButton
            }
            HStack(spacing: 16) {
                resultFilterButtons
                Spacer(minLength: 0)
                Text(String(format: String(localized: "%d records"), filteredEntries.count))
                    .font(.system(size: 13))
                    .foregroundStyle(SettingsPalette.tertiary)
                    .accessibilityIdentifier("history.recordCount")
            }
            if filteredEntries.isEmpty {
                PageStateView(model: .empty(
                    iconSystemName: "magnifyingglass",
                    title: "No matching history",
                    message: "Try another search or result filter.",
                    actions: [PageStateAction(id: "history.clearFilters", title: "pageState.clearFilters", accessibilityIdentifier: "history.clearFilters")]
                )) { _ in
                    query = ""
                    resultFilter = .all
                }
                .accessibilityIdentifier("history.filteredEmpty")
            } else {
                ForEach(HistoryListPresentation.grouped(filteredEntries)) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        WorkspaceSectionHeader(title: group.title(), detail: group.detail)
                        SettingsGroup {
                            ForEach(Array(group.entries.enumerated()), id: \.element.id) { index, entry in
                                historyRow(entry)
                                if index < group.entries.count - 1 {
                                    SettingsSeparator()
                                }
                            }
                        }
                    }
                }
            }
            Label("Sensitive URL parameters are hidden. History stays on this Mac.", systemImage: "checkmark.shield")
                .font(.system(size: 11))
                .foregroundStyle(SettingsPalette.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var resultFilterButtons: some View {
        HStack(spacing: 2) {
            Menu {
                ForEach([HistoryResultFilter.all, .failed, .processing]) { filter in
                    Button(LocalizedStringKey(filter.title)) { resultFilter = filter }
                        .accessibilityIdentifier(filter == .all ? "history.resultFilter.menu.all" : "history.resultFilter.\(filter.rawValue)")
                }
            } label: {
                Text(LocalizedStringKey((isAdditionalResultSelected ? resultFilter : .all).title))
                    .font(.system(size: 13, weight: resultFilter == .all || isAdditionalResultSelected ? .semibold : .regular))
                    .foregroundStyle(resultFilter == .all || isAdditionalResultSelected ? SettingsPalette.primary : SettingsPalette.tertiary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .padding(.horizontal, 16)
            .frame(height: 31)
            .background(resultFilter == .all || isAdditionalResultSelected ? SettingsPalette.group : .clear, in: RoundedRectangle(cornerRadius: 8))
            .accessibilityLabel("Result")
            .accessibilityIdentifier("history.resultFilter.all")
            ForEach([HistoryResultFilter.opened, .cancelled]) { filter in
                Button { resultFilter = filter } label: {
                    filterLabel(filter, selected: resultFilter == filter)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(resultFilter == filter ? .isSelected : [])
                .accessibilityIdentifier("history.resultFilter.\(filter.rawValue)")
            }
        }
        .padding(3)
        .fixedSize(horizontal: true, vertical: false)
        .frame(height: 37)
        .background(SettingsPalette.iconWell, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Result")
        .accessibilityIdentifier("history.resultFilter")
    }

    private var isAdditionalResultSelected: Bool {
        resultFilter == .failed || resultFilter == .processing
    }

    private func filterLabel(_ filter: HistoryResultFilter, selected: Bool) -> some View {
        Text(LocalizedStringKey(filter.title))
            .font(.system(size: 13, weight: selected ? .semibold : .regular))
            .foregroundStyle(selected ? SettingsPalette.primary : SettingsPalette.tertiary)
            .lineLimit(1)
            .padding(.horizontal, 16)
            .frame(height: 31)
            .background(selected ? SettingsPalette.group : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
    }

    private var filteredEntries: [HistoryEntry] {
        HistoryListPresentation.filtered(model.entries, query: query, result: resultFilter) {
            model.presentation(for: $0)
        }
    }

    private func historyRow(_ entry: HistoryEntry) -> some View {
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
            delete: { model.requestDelete(entry) },
            currentRules: try? environment.ruleRepository.all(),
            editRule: { model.editMatchingRule(entry, currentRules: try? environment.ruleRepository.all()) }
        )
    }

    private var clearButton: some View {
        Button(role: .destructive) {
            model.requestClear()
        } label: {
            if model.isClearing {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Clearing…")
                }
            } else {
                Label("history.clearButton", systemImage: "trash")
            }
        }
        .buttonStyle(WorkspaceButtonStyle(kind: .secondary, height: 36))
        .disabled(!model.canClear)
        .accessibilityIdentifier("history.clear")
        .accessibilityValue(model.isClearing ? "Clearing" : "Ready")
        .accessibilityHint(model.canClear
            ? "Clear all saved History"
            : "Clear is unavailable while Prism can still complete or retry a link. Complete or cancel that link first.")
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

enum HistoryResultFilter: String, CaseIterable, Identifiable {
    case all, opened, cancelled, failed, processing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .opened: "Opened"
        case .cancelled: "Cancelled"
        case .failed: "Failed"
        case .processing: "Processing"
        }
    }

    func includes(_ result: HistoryResult) -> Bool {
        switch self {
        case .all: true
        case .opened: result == .success
        case .cancelled: result == .cancelled
        case .failed: result == .failure
        case .processing: result == .processing
        }
    }
}

struct HistoryDayGroup: Identifiable {
    let date: Date
    let entries: [HistoryEntry]

    var id: Date { date }

    func title(now: Date = .now, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return String(localized: "Today") }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) { return String(localized: "Yesterday") }
        return date.formatted(.dateTime.year().month().day())
    }

    var detail: String { date.formatted(.dateTime.month().day().weekday(.wide)) }
}

enum HistoryListPresentation {
    static func eventDate(for entry: HistoryEntry) -> Date { entry.completedAt ?? entry.createdAt }

    static func filtered(
        _ entries: [HistoryEntry],
        query: String,
        result: HistoryResultFilter,
        presentation: (HistoryEntry) -> HistoryRowPresentation
    ) -> [HistoryEntry] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return entries.filter { entry in
            guard result.includes(entry.result) else { return false }
            guard !search.isEmpty else { return true }
            let searchable = [
                presentation(entry).safeURL?.absoluteString ?? "",
                entry.sourceDisplayName,
                entry.targetDisplayName ?? "",
            ]
            return searchable.contains { $0.localizedStandardContains(search) }
        }
    }

    static func grouped(_ entries: [HistoryEntry], calendar: Calendar = .current) -> [HistoryDayGroup] {
        let groups = Dictionary(grouping: entries) { calendar.startOfDay(for: eventDate(for: $0)) }
        return groups.keys.sorted(by: >).map { day in
            HistoryDayGroup(date: day, entries: groups[day, default: []].sorted {
                eventDate(for: $0) > eventDate(for: $1)
            })
        }
    }
}
