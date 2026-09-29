import AppKit
import PrismCore
import SwiftUI

struct RulesManagementView: View {
    @Environment(AppEnvironment.self) private var environment

    let browserCatalog: any BrowserCataloging
    var onOpenSettings: (() -> Void)? = nil

    @State private var rules: [RoutingRule] = []
    @State private var browsers: [BrowserDescriptor] = []
    @State private var installedApplications: [InstalledApplication] = []
    @State private var searchText = ""
    @State private var draft: RuleEditorDraft?
    @State private var rulePendingDeletion: RoutingRule?
    @State private var errorMessage: String?
    @State private var pendingRefreshNotice: String?
    @State private var isLoading = true

    var body: some View {
        PageColumn {
            SystemSettingsPageHeader(
                title: "Rules",
                subtitle: "Choose which links Prism should open automatically.",
                accessibilityIdentifier: "appShell.page.rules.heading"
            )
            searchRow
            HStack(spacing: 9) {
                Image(systemName: "info.circle")
                Text("URL rules are matched first, followed by source applications. Rules in each group run in order.")
                    .font(.system(size: 13))
            }
            .foregroundStyle(SettingsPalette.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(SettingsPalette.iconWell, in: RoundedRectangle(cornerRadius: 8))

            if isLoading {
                ProgressView("Loading rules…")
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else if !searchText.isEmpty && filteredRules.isEmpty {
                ContentUnavailableView(
                    "No matching rules",
                    systemImage: "magnifyingglass",
                    description: Text("Try a different search.")
                )
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                ruleGroup(title: "URL Rules", groupPriority: "01", rules: filteredURLRules, orderedRules: urlRules)
                ruleGroup(title: "Source Application Rules", groupPriority: "02", rules: filteredSourceRules, orderedRules: sourceRules)
            }
            unmatchedBehaviorCard
        }
        .task { await reload() }
        .onChange(of: environment.pendingSelectorRulePrefill) { _, prefill in
            guard draft == nil, prefill != nil else { return }
            beginCreatingRule()
        }
        .sheet(item: $draft, onDismiss: {
            if let pendingRefreshNotice {
                errorMessage = pendingRefreshNotice
                self.pendingRefreshNotice = nil
            }
        }) { draft in
            RuleEditorSheet(draft: draft, browsers: browsers, applications: installedApplications) { updatedRule in
                save(updatedRule, reportsError: false)
            }
        }
        .confirmationDialog(
            "Delete this rule?",
            isPresented: Binding(
                get: { rulePendingDeletion != nil },
                set: { if !$0 { rulePendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Rule", role: .destructive) {
                if let rulePendingDeletion { delete(rulePendingDeletion) }
            }
            Button("Cancel", role: .cancel) { rulePendingDeletion = nil }
        } message: {
            Text("Links will no longer be sent by this rule.")
        }
        .alert(
            "Rules could not be updated",
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

    private var searchRow: some View {
        HStack(spacing: 12) {
            WorkspaceSearchField(placeholder: "Search rules", text: $searchText)
                .frame(width: 340)
                .accessibilityIdentifier("rules.search")
            Spacer(minLength: 12)
            Button("Create Rule", systemImage: "plus") { beginCreatingRule() }
                .buttonStyle(WorkspaceButtonStyle(kind: .primary))
                .disabled(browsers.allSatisfy { $0.availability != .available })
                .accessibilityIdentifier("rules.create")
        }
    }

    private var unmatchedBehaviorCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.turn.down.right")
                .font(.system(size: 17))
                .foregroundStyle(SettingsPalette.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text("No matching rule")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SettingsPalette.primary)
                Text(LocalizedStringKey(unmatchedBehaviorDescription))
                    .font(.system(size: 13))
                    .foregroundStyle(SettingsPalette.secondary)
            }
            Spacer(minLength: 12)
            if let onOpenSettings {
                Button(action: onOpenSettings) {
                    HStack(spacing: 5) {
                        Text("Open Settings")
                        Image(systemName: "arrow.right")
                    }
                }
                .buttonStyle(WorkspaceButtonStyle(kind: .quiet))
                .font(.system(size: 13, weight: .medium))
                .accessibilityIdentifier("rules.openSettings")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SettingsPalette.iconWell, in: RoundedRectangle(cornerRadius: 10))
    }

    private var unmatchedBehaviorDescription: String {
        switch environment.settings.unmatchedBehavior {
        case .alwaysAsk: "Show the browser picker"
        case .preferredBrowser: "Open with the preferred browser"
        case .lastUsedBrowser: "Open with the last used browser"
        }
    }

    private var filteredRules: [RoutingRule] {
        guard !searchText.isEmpty else { return rules }
        return rules.filter { rule in
            return rule.displayName.localizedCaseInsensitiveContains(searchText)
                || matchDetail(rule).localizedCaseInsensitiveContains(searchText)
                || browserName(for: rule.targetBrowserID).localizedCaseInsensitiveContains(searchText)
        }
    }

    private var urlRules: [RoutingRule] {
        rules.filter { !$0.isSourceRule }
    }

    private var sourceRules: [RoutingRule] {
        rules.filter(\.isSourceRule)
    }

    private var filteredURLRules: [RoutingRule] {
        filteredRules.filter { !$0.isSourceRule }
    }

    private var filteredSourceRules: [RoutingRule] {
        filteredRules.filter(\.isSourceRule)
    }

    private func ruleGroup(
        title: String,
        groupPriority: String,
        rules: [RoutingRule],
        orderedRules: [RoutingRule]
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(LocalizedStringKey(title))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(SettingsPalette.primary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text("\(String(localized: "Priority")) \(groupPriority)")
                    .font(.system(size: 12))
                    .foregroundStyle(SettingsPalette.secondary)
                Text("\(rules.count) rules")
                    .font(.system(size: 12))
                    .foregroundStyle(SettingsPalette.secondary)
            }
            SettingsGroup {
                if rules.isEmpty {
                    Text("No rules in this group")
                        .font(.system(size: 13))
                        .foregroundStyle(SettingsPalette.secondary)
                        .padding(.horizontal, 20)
                        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                } else {
                    ForEach(Array(rules.enumerated()), id: \.element.id) { index, rule in
                        let orderedIndex = orderedRules.firstIndex(where: { $0.id == rule.id }) ?? index
                        ruleRow(
                            rule,
                            priority: displayedPriority(for: rule, in: orderedRules, fallback: index + 1),
                            canMoveUp: searchText.isEmpty && orderedIndex > 0,
                            canMoveDown: searchText.isEmpty && orderedIndex < orderedRules.count - 1,
                            moveUp: { move(orderedRules, from: orderedIndex, to: orderedIndex - 1) },
                            moveDown: { move(orderedRules, from: orderedIndex, to: orderedIndex + 1) }
                        )
                        if index < rules.count - 1 {
                            SettingsSeparator(leadingInset: 20)
                        }
                    }
                }
            }
        }
    }

    private func ruleRow(
        _ rule: RoutingRule,
        priority: Int,
        canMoveUp: Bool,
        canMoveDown: Bool,
        moveUp: @escaping () -> Void,
        moveDown: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(spacing: 3) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 10))
                Text(String(format: "%02d", priority))
                    .font(.system(size: 10, design: .monospaced))
            }
            .foregroundStyle(SettingsPalette.secondary)
            .frame(width: 18)
            .accessibilityLabel("\(String(localized: "Priority")) \(priority)")
            VStack(alignment: .leading, spacing: 5) {
                Text(rule.displayName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(SettingsPalette.primary)
                    .lineLimit(1)
                Text(matchDetail(rule))
                    .font(.system(size: 13))
                    .foregroundStyle(SettingsPalette.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 7) {
                browserIcon(for: rule.targetBrowserID)
                Text(browserName(for: rule.targetBrowserID))
                    .font(.system(size: 13))
                    .foregroundStyle(SettingsPalette.primary)
                    .lineLimit(1)
            }
            .frame(width: 138, alignment: .leading)
            Toggle("Enable rule", isOn: Binding(
                get: { rule.isEnabled },
                set: { _ in toggle(rule) }
            ))
            .toggleStyle(WorkspaceToggleStyle())
            .labelsHidden()
            .accessibilityLabel("Enable \(rule.displayName)")
            Menu {
                Button("Increase priority", systemImage: "arrow.up", action: moveUp)
                    .disabled(!canMoveUp)
                    .accessibilityLabel("Increase priority for \(rule.displayName)")
                    .accessibilityIdentifier("rules.rule.\(rule.id.uuidString).moveUp")
                Button("Decrease priority", systemImage: "arrow.down", action: moveDown)
                    .disabled(!canMoveDown)
                    .accessibilityLabel("Decrease priority for \(rule.displayName)")
                    .accessibilityIdentifier("rules.rule.\(rule.id.uuidString).moveDown")
                Divider()
                Button("Edit", systemImage: "pencil") {
                    draft = RuleEditorDraft(rule: rule, browsers: browsers)
                }
                Button("Delete", systemImage: "trash", role: .destructive) {
                    rulePendingDeletion = rule
                }
            } label: {
                Label(
                    String(format: String(localized: "Actions for rule %@"), rule.displayName),
                    systemImage: "ellipsis"
                )
                .labelStyle(.iconOnly)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel(String(format: String(localized: "Actions for rule %@"), rule.displayName))
            .accessibilityIdentifier("rules.rule.\(rule.id.uuidString).actions")
        }
        .padding(.horizontal, 20)
        .frame(minHeight: 72)
    }

    private func beginCreatingRule() {
        draft = RuleEditorDraft(
            prefill: environment.consumeSelectorRulePrefill(),
            browsers: browsers
        )
    }

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            browsers = try await browserCatalog.scan()
            installedApplications = InstalledApplicationCatalog.load()
            rules = try normalizePriorities(in: environment.ruleRepository.all())
            if draft == nil, environment.pendingSelectorRulePrefill != nil {
                beginCreatingRule()
            }
        } catch {
            errorMessage = "Prism could not load your saved rules or browser list."
        }
    }

    @discardableResult
    private func save(_ rule: RoutingRule, reportsError: Bool = true) -> Bool {
        var updatedRule = rule
        if !rules.contains(where: { $0.id == rule.id }) {
            updatedRule.priority = nextPriority(for: rule)
        }
        do {
            try environment.ruleRepository.upsert(updatedRule)
        } catch {
            if reportsError { errorMessage = "Prism could not save this rule." }
            return false
        }

        do {
            rules = try environment.ruleRepository.all()
        } catch {
            rules = RoutingRuleOrdering.sorted(rules.filter { $0.id != updatedRule.id } + [updatedRule])
            let notice = "The rule was saved, but the list could not be refreshed. Reopen Rules to try again."
            if reportsError {
                errorMessage = notice
            } else {
                pendingRefreshNotice = notice
            }
        }
        return true
    }

    private func toggle(_ rule: RoutingRule) {
        var updated = rule
        updated.isEnabled.toggle()
        updated.updatedAt = .now
        save(updated)
    }

    private func delete(_ rule: RoutingRule) {
        defer { rulePendingDeletion = nil }
        do {
            try environment.ruleRepository.delete(id: rule.id)
            rules = try environment.ruleRepository.all()
        } catch {
            errorMessage = "Prism could not delete this rule."
        }
    }

    private func browserIcon(for id: BrowserID) -> some View {
        let browser = browsers.first(where: { $0.id == id })
        return ApplicationIconView(
            bundleIdentifier: browser?.bundleIdentifier ?? id.rawValue,
            applicationURL: browser?.applicationURL,
            fallbackSymbol: "safari",
            side: 16
        )
    }

    private func matchDetail(_ rule: RoutingRule) -> String {
        switch rule.matcher {
        case let .exactHost(host):
            "\(String(localized: "Exact domain")) · \(host)"
        case let .hostAndSubdomains(host):
            "\(String(localized: "Domain and subdomains")) · \(host)"
        case let .urlContains(value):
            "\(String(localized: "URL contains")) · \(value)"
        case let .sourceBundleIdentifier(bundleIdentifier):
            "\(String(localized: "Source application")) · \(bundleIdentifier)"
        }
    }

    private func browserName(for id: BrowserID) -> String {
        browsers.first(where: { $0.id == id })?.displayName ?? String(localized: "Unavailable browser")
    }

    private func move(_ orderedRules: [RoutingRule], from source: Int, to destination: Int) {
        guard orderedRules.indices.contains(source), orderedRules.indices.contains(destination) else { return }
        var reordered = orderedRules
        reordered.swapAt(source, destination)
        let updates = reordered.enumerated().compactMap { index, rule -> RoutingRule? in
            guard rule.priority != index else { return nil }
            var updated = rule
            updated.priority = index
            updated.updatedAt = .now
            return updated
        }
        guard !updates.isEmpty else { return }
        do {
            try environment.ruleRepository.updatePriorities(updates)
            rules = try environment.ruleRepository.all()
        } catch {
            errorMessage = "Prism could not save the rule order. Your previous priority is still in use."
        }
    }

    private func normalizePriorities(in loadedRules: [RoutingRule]) throws -> [RoutingRule] {
        let ordered = RoutingRuleOrdering.sorted(loadedRules)
        let updates = [
            ordered.filter { !$0.isSourceRule },
            ordered.filter(\.isSourceRule),
        ].flatMap { group in
            group.enumerated().compactMap { index, rule -> RoutingRule? in
                guard rule.priority != index else { return nil }
                var updated = rule
                updated.priority = index
                updated.updatedAt = .now
                return updated
            }
        }
        guard !updates.isEmpty else { return ordered }
        try environment.ruleRepository.updatePriorities(updates)
        return try environment.ruleRepository.all()
    }

    private func nextPriority(for rule: RoutingRule) -> Int {
        (rule.isSourceRule ? sourceRules : urlRules).count
    }

    private func displayedPriority(
        for rule: RoutingRule,
        in orderedRules: [RoutingRule],
        fallback: Int
    ) -> Int {
        (orderedRules.firstIndex(where: { $0.id == rule.id }) ?? fallback - 1) + 1
    }
}

private struct RuleEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var draft: RuleEditorDraft
    @State private var applicationSearch = ""
    @State private var saveFailed = false

    let browsers: [BrowserDescriptor]
    let applications: [InstalledApplication]
    let save: (RoutingRule) -> Bool

    init(
        draft: RuleEditorDraft,
        browsers: [BrowserDescriptor],
        applications: [InstalledApplication],
        save: @escaping (RoutingRule) -> Bool
    ) {
        _draft = State(initialValue: draft)
        self.browsers = browsers
        self.applications = applications
        self.save = save
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text(draft.existingRule == nil ? "Create Rule" : "Edit Rule")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(SettingsPalette.primary)
                Text("Set a condition and choose where matching links should open.")
                    .font(.system(size: 14))
                    .foregroundStyle(SettingsPalette.secondary)
            }

            ViewThatFits(in: .vertical) {
                editorContent.fixedSize(horizontal: false, vertical: true)
                ScrollView {
                    editorContent
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .frame(maxHeight: 400)
            Rectangle()
                .fill(SettingsPalette.border)
                .frame(height: 1)
            HStack(spacing: 10) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(WorkspaceButtonStyle(kind: .secondary))
                    .keyboardShortcut(.cancelAction)
                Button(draft.existingRule == nil ? "Create Rule" : "Save Changes") {
                    guard let rule = draft.makeRule() else { return }
                    if save(rule) { dismiss() } else { saveFailed = true }
                }
                .buttonStyle(WorkspaceButtonStyle(kind: .primary))
                .disabled(!draft.canSave)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("rules.editor.save")
            }
        }
        .padding(28)
        .frame(width: 520)
        .background(SettingsPalette.group)
    }

    private var editorContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 18) {
                editorField("Match") {
                    WorkspacePicker(
                        title: "Match",
                        selection: $draft.matchKind,
                        options: RuleMatchKind.allCases.map { WorkspacePickerOption(value: $0, title: $0.title) }
                    )
                    .accessibilityIdentifier("rules.editor.match")
                }
                editorField("Condition") {
                    if draft.matchKind == .sourceApplication {
                        WorkspaceSearchField(placeholder: "Search applications", text: $applicationSearch)
                            .accessibilityIdentifier("rules.editor.applicationSearch")
                        WorkspacePicker(
                            title: "Source application",
                            selection: $draft.matchValue,
                            options: applicationOptions
                        )
                        .onChange(of: draft.matchValue) { _, value in
                            guard draft.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                                  let application = applications.first(where: { $0.bundleIdentifier == value })
                            else { return }
                            draft.label = application.displayName
                        }
                        .accessibilityIdentifier("rules.editor.condition")
                        if let selected = applications.first(where: { $0.bundleIdentifier == draft.matchValue }) {
                            Text(selected.bundleIdentifier)
                                .font(.system(size: 12))
                                .foregroundStyle(SettingsPalette.secondary)
                        }
                    } else {
                        WorkspaceInputField(placeholder: draft.matchKind.prompt, text: $draft.matchValue)
                            .accessibilityIdentifier("rules.editor.condition")
                    }
                    Text(LocalizedStringKey(draft.matchKind.hint))
                        .font(.system(size: 12))
                        .foregroundStyle(SettingsPalette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                editorField("Open in") {
                    WorkspacePicker(
                        title: "Open in",
                        selection: $draft.targetBrowserID,
                        options: browserOptions
                    )
                    .accessibilityIdentifier("rules.editor.browser")
                }
                editorField("Rule name (optional)") {
                    WorkspaceInputField(placeholder: "Optional label", text: $draft.label)
                        .accessibilityIdentifier("rules.editor.label")
                }
                Toggle("Enable this rule", isOn: $draft.isEnabled)
                    .toggleStyle(WorkspaceToggleStyle(showsLabel: true))
                    .font(.system(size: 13))
                    .accessibilityIdentifier("rules.editor.enabled")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if saveFailed {
                Label("Prism could not save this rule. Try again.", systemImage: "exclamationmark.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(SettingsPalette.secondary)
            }
        }
    }

    private var applicationOptions: [WorkspacePickerOption<String>] {
        var options = [WorkspacePickerOption(value: "", title: "Choose an application")]
        if !draft.matchValue.isEmpty,
           !applications.contains(where: { $0.bundleIdentifier == draft.matchValue }) {
            options.append(WorkspacePickerOption(value: draft.matchValue, title: draft.matchValue))
        }
        options += applications.filter {
            applicationSearch.isEmpty
                || $0.bundleIdentifier == draft.matchValue
                || $0.displayName.localizedStandardContains(applicationSearch)
                || $0.bundleIdentifier.localizedStandardContains(applicationSearch)
        }.map {
            WorkspacePickerOption(value: $0.bundleIdentifier, title: $0.displayName)
        }
        return options
    }

    private var browserOptions: [WorkspacePickerOption<BrowserID?>] {
        [WorkspacePickerOption(value: BrowserID?.none, title: "Choose a browser")]
            + browsers.filter { $0.availability == .available }.map {
                WorkspacePickerOption(value: BrowserID?.some($0.id), title: $0.displayName)
            }
    }

    private func editorField<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(SettingsPalette.primary)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

}

private extension RoutingRule {
    var isSourceRule: Bool {
        if case .sourceBundleIdentifier = matcher { return true }
        return false
    }

    var matcherDisplayName: String {
        switch matcher {
        case .exactHost: "Exact domain"
        case .hostAndSubdomains: "Domain and subdomains"
        case .urlContains: "URL contains"
        case .sourceBundleIdentifier: "Source application"
        }
    }

    var displayName: String {
        if let label, !label.isEmpty { return label }
        switch matcher {
        case let .exactHost(host), let .hostAndSubdomains(host), let .urlContains(host), let .sourceBundleIdentifier(host):
            return host
        }
    }

    var matcherIcon: String {
        switch matcher {
        case .sourceBundleIdentifier: "app.badge"
        case .exactHost, .hostAndSubdomains, .urlContains: "globe"
        }
    }
}
