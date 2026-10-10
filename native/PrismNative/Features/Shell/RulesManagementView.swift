import AppKit
import PrismCore
import SwiftUI

struct RulesManagementView: View {
    @Environment(AppEnvironment.self) private var environment

    let browserCatalog: any BrowserCataloging
    var onOpenSettings: (() -> Void)? = nil
    var sourceManifest: SourceSupportManifest = .bundled()
    var operatingSystemVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion

    @State private var rules: [RoutingRule] = []
    @State private var browsers: [BrowserDescriptor] = []
    @State private var installedApplications: [InstalledApplication] = []
    @State private var searchText = ""
    @State private var draft: RuleEditorDraft?
    @State private var rulePendingDeletion: RoutingRule?
    @State private var errorMessage: String?
    @State private var pendingRefreshNotice: String?
    @State private var isLoading = true
    @State private var saveUndo = RuleSaveUndo()
    @State private var editorIntents = RuleEditorIntentCoordinator()
    @State private var editorHostVisible = false
    @State private var hoveredRuleID: UUID?
    @State private var showsRoutingPreview = false
    @State private var previewRuleToEdit: RoutingRule?

    var body: some View {
        PageColumn {
            SystemSettingsPageHeader(
                title: "Rules",
                subtitle: "Choose which links Prism should open automatically.",
                accessibilityIdentifier: "appShell.page.rules.heading"
            )
            searchRow
            if let savedRule = saveUndo.savedRule {
                HStack(spacing: 12) {
                    Label(String(localized: "rules.undo.saved", defaultValue: "New rule saved."), systemImage: "checkmark.circle")
                        .font(.system(size: 13))
                    Text(savedRule.label ?? RuleEditorDraft(rule: savedRule, browsers: browsers).matchValue)
                        .font(.system(size: 13))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Button(String(localized: "rules.undo.action", defaultValue: "Undo")) { undoNewRule() }
                        .buttonStyle(WorkspaceButtonStyle(kind: .secondary))
                        .accessibilityIdentifier("rules.undo")
                }
                .padding(12)
                .background(SettingsPalette.iconWell, in: RoundedRectangle(cornerRadius: 8))
                .accessibilityIdentifier("rules.savedNotice")
            }
            HStack(spacing: 9) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 16))
                    .foregroundStyle(SettingsPalette.primary)
                Text("URL rules are matched first, followed by source applications. Rules in each group run in order.")
                    .font(.system(size: 13))
            }
            .foregroundStyle(SettingsPalette.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(SettingsPalette.iconWell, in: RoundedRectangle(cornerRadius: 12))

            if isLoading {
                PageStateView(model: .loading(title: "Loading rules…"))
            } else if !searchText.isEmpty && filteredRules.isEmpty {
                PageStateView(model: .empty(
                    iconSystemName: "magnifyingglass",
                    title: "No matching rules",
                    message: "Try a different search.",
                    actions: [PageStateAction(id: "rules.clearFilters", title: "pageState.clearFilters", accessibilityIdentifier: "rules.clearFilters")]
                )) { _ in
                    searchText = ""
                }
                .accessibilityIdentifier("rules.emptyFilter")
            } else if rules.isEmpty {
                PageStateView(model: .empty(
                    iconSystemName: "list.bullet",
                    title: "rules.empty.title",
                    message: "rules.empty.message",
                    actions: [PageStateAction(id: "rules.emptyCreate", title: "rules.page.newRule", accessibilityIdentifier: "rules.emptyCreate")]
                )) { _ in beginCreatingRule() }
                .disabled(browsers.allSatisfy { $0.availability != .available })
            } else {
                ruleGroup(title: "URL Rules", groupPriority: "01", rules: filteredURLRules, orderedRules: urlRules)
                ruleGroup(title: "Source Application Rules", groupPriority: "02", rules: filteredSourceRules, orderedRules: sourceRules)
            }
            unmatchedBehaviorCard
        }
        .task { await reload() }
        .onAppear { editorHostVisible = true }
        .onDisappear { editorHostVisible = false }
        .onChange(of: environment.pendingSelectorRulePrefill) { _, _ in
            resumePendingEditorIntent()
        }
        .onChange(of: errorMessage) { _, message in
            guard message == nil else { return }
            Task { @MainActor in
                await Task.yield()
                resumePendingEditorIntent()
            }
        }
        .sheet(item: $draft, onDismiss: {
            if let pendingRefreshNotice {
                errorMessage = pendingRefreshNotice
                self.pendingRefreshNotice = nil
            }
            let dismissedID = editorIntents.activePresentationID
            Task { @MainActor in
                // Let SwiftUI complete the old sheet transition before presenting another.
                await Task.yield()
                if let dismissedID {
                    guard editorIntents.finishDismissal(id: dismissedID) else { return }
                }
                resumePendingEditorIntent()
            }
        }) { draft in
            RuleEditorSheet(
                draft: draft,
                browsers: browsers,
                applications: installedApplications,
                sourceManifest: sourceManifest,
                operatingSystemVersion: operatingSystemVersion
            ) { updatedRule in
                save(updatedRule, reportsError: false)
            }
        }
        .sheet(isPresented: $showsRoutingPreview, onDismiss: {
            let dismissedID = editorIntents.activePresentationID
            Task { @MainActor in
                await Task.yield()
                if let dismissedID {
                    guard editorIntents.finishDismissal(id: dismissedID) else { return }
                }
                if let rule = previewRuleToEdit {
                    previewRuleToEdit = nil
                    beginEditingRule(rule)
                }
                resumePendingEditorIntent()
            }
        }) {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Text(String(localized: "rules.preview.title", defaultValue: "Test routing rules"))
                        .font(.system(size: 23, weight: .semibold))
                    Spacer()
                    Button { showsRoutingPreview = false } label: {
                        Image(systemName: "xmark").font(.system(size: 16))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel("Close")
                }
                RuleRoutingPreviewView(rules: rules, browsers: browsers, applications: installedApplications, settings: environment.settings) { rule in
                    previewRuleToEdit = rule
                    showsRoutingPreview = false
                }
            }
            .padding(28)
            .frame(width: 520)
            .background(SettingsPalette.elevated)
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
            WorkspaceSearchField(placeholder: String(localized: "rules.page.searchPlaceholder", defaultValue: "Search rule names, conditions, or browsers"), text: $searchText)
                .frame(width: 340)
                .accessibilityIdentifier("rules.search")
            Spacer(minLength: 12)
            Button { beginCreatingRule() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus").frame(width: 16, height: 16)
                    Text(String(localized: "rules.page.newRule", defaultValue: "New Rule"))
                }
            }
                .buttonStyle(WorkspaceButtonStyle(kind: .primary, height: 56, horizontalPadding: 20, fontSize: 14))
                .disabled(browsers.allSatisfy { $0.availability != .available })
                .accessibilityIdentifier("rules.create")
        }
    }

    private var unmatchedBehaviorCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle")
                .font(.system(size: 18))
                .foregroundStyle(SettingsPalette.muted)
            VStack(alignment: .leading, spacing: 4) {
                Text("No matching rule")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(SettingsPalette.tertiary)
                Text(LocalizedStringKey(unmatchedBehaviorDescription))
                    .font(.system(size: 13))
                    .foregroundStyle(SettingsPalette.tertiary)
            }
            Spacer(minLength: 12)
            if let onOpenSettings {
                Button(action: onOpenSettings) {
                    HStack(spacing: 5) {
                        Text(String(localized: "rules.page.openSettings", defaultValue: "Go to Settings"))
                        Image(systemName: "arrow.up.right")
                    }
                }
                .buttonStyle(WorkspaceButtonStyle(kind: .quiet))
                .font(.system(size: 13))
                .accessibilityIdentifier("rules.openSettings")
            }
            Menu {
                Button(String(localized: "rules.preview.title", defaultValue: "Test routing rules")) { beginRoutingPreview() }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16))
                    .foregroundStyle(SettingsPalette.muted)
                    .frame(width: 16, height: 28)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel(String(localized: "rules.preview.title", defaultValue: "Test routing rules"))
            .accessibilityIdentifier("rules.preview.open")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SettingsPalette.iconWell, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(SettingsPalette.borderSubtle, lineWidth: 1))
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
            if case let .sourceBundleIdentifier(bundleIdentifier) = rule.matcher,
               bundleIdentifier.localizedCaseInsensitiveContains(searchText) {
                return true
            }
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(LocalizedStringKey(title))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SettingsPalette.secondary)
                    .accessibilityAddTraits(.isHeader)
                    .frame(height: 22)
                Spacer()
                Text("\(String(localized: "Priority")) \(groupPriority) · \(String(format: String(localized: "%d rules"), rules.count))")
                    .font(.system(size: 12))
                    .foregroundStyle(SettingsPalette.tertiary)
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
                            SettingsSeparator()
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
            VStack(spacing: 2) {
                ForEach(0..<3) { _ in
                    HStack(spacing: 2) {
                        Circle().frame(width: 2, height: 2)
                        Circle().frame(width: 2, height: 2)
                    }
                }
            }
                .foregroundStyle(SettingsPalette.muted)
                .frame(width: 16)
                .accessibilityLabel("\(String(localized: "Priority")) \(priority)")
            Image(systemName: rule.matcherIcon)
                .font(.system(size: 16))
                .foregroundStyle(rule.isEnabled ? SettingsPalette.tertiary : SettingsPalette.muted)
                .frame(width: 34, height: 34)
                .background(SettingsPalette.iconWell, in: RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(rule.displayName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(rule.isEnabled ? SettingsPalette.primary : SettingsPalette.tertiary)
                    .lineLimit(1)
                    .frame(height: 22)
                Text(matchDetail(rule))
                    .font(.system(size: 13))
                    .foregroundStyle(SettingsPalette.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(height: 19)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .help(ruleSupportDescription(rule))
            .accessibilityHint(ruleSupportDescription(rule))
            Image(systemName: "arrow.right")
                .font(.system(size: 16))
                .foregroundStyle(SettingsPalette.muted)
                .accessibilityHidden(true)
            HStack(spacing: 7) {
                Image(systemName: "safari")
                    .font(.system(size: 16))
                    .foregroundStyle(rule.isEnabled ? SettingsPalette.primary : SettingsPalette.muted)
                    .accessibilityHidden(true)
                Text(browserName(for: rule.targetBrowserID))
                    .font(.system(size: 14))
                    .foregroundStyle(SettingsPalette.tertiary)
                    .lineLimit(1)
            }
            .frame(width: 155, alignment: .leading)
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
                Button("Edit", systemImage: "pencil") { beginEditingRule(rule) }
                Button("Delete", systemImage: "trash", role: .destructive) {
                    rulePendingDeletion = rule
                }
            } label: {
                Label(
                    String(format: String(localized: "Actions for rule %@"), rule.displayName),
                    systemImage: "ellipsis"
                )
                .labelStyle(.iconOnly)
                .font(.system(size: 16))
                .foregroundStyle(SettingsPalette.muted)
                .frame(width: 16, height: 28)
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel(String(format: String(localized: "Actions for rule %@"), rule.displayName))
            .accessibilityIdentifier("rules.rule.\(rule.id.uuidString).actions")
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 82)
        .background(hoveredRuleID == rule.id ? SettingsPalette.elevated : .clear)
        .onHover { hoveredRuleID = $0 ? rule.id : nil }
    }

    private func ruleSupportDescription(_ rule: RoutingRule) -> String {
        if case let .sourceBundleIdentifier(bundleIdentifier) = rule.matcher {
            return sourceManifest.supportStatus(for: bundleIdentifier, on: operatingSystemVersion).message
        }
        return matchDetail(rule)
    }

    private func beginRoutingPreview() {
        guard draft == nil, errorMessage == nil, !showsRoutingPreview,
              editorIntents.beginPresentation(takePending: { nil }) != nil
        else { return }
        showsRoutingPreview = true
    }

    private func resumePendingEditorIntent() {
        guard editorHostVisible, draft == nil, errorMessage == nil, !showsRoutingPreview,
              environment.pendingSelectorRulePrefill != nil
        else { return }
        beginCreatingRule()
    }

    private func beginEditingRule(_ rule: RoutingRule) {
        guard draft == nil, errorMessage == nil, !showsRoutingPreview,
              editorIntents.beginPresentation(takePending: { nil }) != nil
        else { return }
        draft = RuleEditorDraft(rule: rule, browsers: browsers)
    }

    private func beginCreatingRule() {
        guard draft == nil, errorMessage == nil, !showsRoutingPreview,
              let intent = editorIntents.beginPresentation(takePending: environment.consumeSelectorRulePrefill)
        else { return }
        if case let .savedRule(id) = intent.prefill {
            do {
                guard let rule = try environment.ruleRepository.all().first(where: { $0.id == id }) else {
                    errorMessage = "The recorded rule no longer exists. Create a new rule instead."
                    editorIntents.finishDismissal(id: intent.id)
                    return
                }
                draft = RuleEditorDraft(rule: rule, browsers: browsers)
            } catch {
                errorMessage = "Prism could not load the recorded rule. Try again."
                editorIntents.finishDismissal(id: intent.id)
            }
        } else {
            draft = RuleEditorDraft(prefill: intent.prefill, browsers: browsers)
        }
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
            try saveUndo.save(updatedRule, repository: environment.ruleRepository)
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

    private func undoNewRule() {
        let savedID = saveUndo.savedRule?.id
        do {
            switch try saveUndo.undo(repository: environment.ruleRepository) {
            case .removed, .alreadyRemoved:
                rules.removeAll { $0.id == savedID }
                do { rules = try environment.ruleRepository.all() }
                catch { errorMessage = "The rule was removed, but the list could not be refreshed." }
            case .changed:
                errorMessage = "This rule has changed since it was saved. Undo did not remove it."
            }
        } catch {
            errorMessage = "Prism could not undo the new rule. Nothing was removed; try again."
        }
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

    private func matchDetail(_ rule: RoutingRule) -> String {
        switch rule.matcher {
        case let .exactHost(host):
            "\(String(localized: "Exact domain")) · \(host)"
        case let .hostAndSubdomains(host):
            "\(String(localized: "Domain and subdomains")) · \(host)"
        case let .urlContains(value):
            String(format: String(localized: "rules.condition.urlContains", defaultValue: "URL contains %@"), value)
        case let .sourceBundleIdentifier(bundleIdentifier):
            String(format: String(localized: "rules.condition.sourceApplication", defaultValue: "Source application is %@"), installedApplications.first(where: { $0.bundleIdentifier == bundleIdentifier })?.displayName ?? bundleIdentifier)
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
    @State private var saveFailed = false

    let browsers: [BrowserDescriptor]
    let applications: [InstalledApplication]
    let sourceManifest: SourceSupportManifest
    let operatingSystemVersion: OperatingSystemVersion
    let save: (RoutingRule) -> Bool

    init(
        draft: RuleEditorDraft,
        browsers: [BrowserDescriptor],
        applications: [InstalledApplication],
        sourceManifest: SourceSupportManifest,
        operatingSystemVersion: OperatingSystemVersion,
        save: @escaping (RoutingRule) -> Bool
    ) {
        _draft = State(initialValue: draft)
        self.browsers = browsers
        self.applications = applications
        self.sourceManifest = sourceManifest
        self.operatingSystemVersion = operatingSystemVersion
        self.save = save
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text(draft.existingRule == nil ? String(localized: "rules.page.newRule", defaultValue: "New Rule") : String(localized: "Edit Rule"))
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(SettingsPalette.primary)
                    .frame(height: 33)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16))
                        .foregroundStyle(SettingsPalette.iconMuted)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
                .accessibilityIdentifier("rules.editor.close")
            }
            Text(draft.matchKind == .sourceApplication
                 ? String(localized: "rules.editor.sourceDescription", defaultValue: "Choose a dedicated browser for this application.")
                 : String(localized: "Set a condition and choose where matching links should open."))
                .font(.system(size: 12))
                .foregroundStyle(SettingsPalette.tertiary)
                .frame(minHeight: 17)
            ScrollView {
                editorContent
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: .infinity)
            Rectangle()
                .fill(SettingsPalette.border)
                .frame(height: 1)
            HStack(spacing: 9) {
                Text(String(localized: "keyboard.escapeCancel", defaultValue: "Esc to cancel"))
                    .font(.system(size: 11))
                    .foregroundStyle(SettingsPalette.muted)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(WorkspaceButtonStyle(kind: .secondary, horizontalPadding: 18))
                    .keyboardShortcut(.cancelAction)
                Button(draft.existingRule == nil ? "Create Rule" : "Save Changes") {
                    guard let rule = draft.makeRule() else { return }
                    if save(rule) { dismiss() } else { saveFailed = true }
                }
                .buttonStyle(WorkspaceButtonStyle(kind: .primary, horizontalPadding: 18))
                .disabled(!draft.canSave)
                .keyboardShortcut(.defaultAction)
                .help("\(draft.scopeDescription) \(selectedTargetDescription)")
                .accessibilityIdentifier("rules.editor.save")
            }
        }
        .padding(28)
        .frame(width: 520, height: 637)
        .background(SettingsPalette.elevated)
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
                editorField(conditionTitle) {
                    if draft.matchKind == .sourceApplication {
                        WorkspacePicker(
                            title: "Source application",
                            selection: $draft.matchValue,
                            options: applicationOptions,
                            searchPlaceholder: "Search applications"
                        )
                        .onChange(of: draft.matchValue) { _, value in
                            guard draft.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                                  let application = applications.first(where: { $0.bundleIdentifier == value })
                            else { return }
                            draft.label = application.displayName
                        }
                        .accessibilityIdentifier("rules.editor.condition")
                    } else {
                        WorkspaceInputField(placeholder: draft.matchKind.prompt, text: $draft.matchValue)
                            .accessibilityIdentifier("rules.editor.condition")
                    }
                    Text(conditionExplanation)
                        .font(.system(size: 11))
                        .foregroundStyle(SettingsPalette.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minHeight: 17, alignment: .leading)
                        .help(draft.scopeDescription)
                        .accessibilityIdentifier(draft.matchKind == .sourceApplication ? "rules.editor.sourceSupport" : "rules.editor.scopePreview")
                }
                editorField("Open in") {
                    WorkspacePicker(
                        title: "Open in",
                        selection: $draft.targetBrowserID,
                        options: browserOptions
                    )
                    .help(selectedTargetDescription)
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
                    .foregroundStyle(SettingsPalette.danger)
            }
        }
    }

    private var conditionTitle: String {
        switch draft.matchKind {
        case .exactDomain, .domainAndSubdomains: String(localized: "rules.editor.domain", defaultValue: "Domain")
        case .urlContains: String(localized: "URL contains")
        case .sourceApplication: String(localized: "Source application")
        }
    }

    private var conditionExplanation: String {
        if let supportStatus = draft.sourceSupportStatus(manifest: sourceManifest, operatingSystemVersion: operatingSystemVersion) {
            return "\(draft.matchValue) · \(supportStatus.message)"
        }
        return draft.matcher == nil ? String(localized: String.LocalizationValue(draft.matchKind.hint)) : draft.scopeDescription
    }

    private var selectedTargetDescription: String {
        guard let id = draft.targetBrowserID, let browser = browsers.first(where: { $0.id == id }) else {
            return String(localized: "Choose a browser")
        }
        return String(format: String(localized: "rules.scope.target", defaultValue: "Open in %@"), browser.displayName)
    }

    private var applicationOptions: [WorkspacePickerOption<String>] {
        var options = [WorkspacePickerOption(value: "", title: "Choose an application")]
        if !draft.matchValue.isEmpty,
           !applications.contains(where: { $0.bundleIdentifier == draft.matchValue }) {
            options.append(WorkspacePickerOption(value: draft.matchValue, title: draft.matchValue))
        }
        options += applications.map {
            WorkspacePickerOption(value: $0.bundleIdentifier, title: $0.displayName, searchText: $0.bundleIdentifier)
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
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(SettingsPalette.tertiary)
                .frame(height: 17)
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
        case .sourceBundleIdentifier: "briefcase"
        case .exactHost, .hostAndSubdomains: "globe"
        case .urlContains: "link"
        }
    }
}

private struct RuleRoutingPreviewView: View {
    let rules: [RoutingRule]
    let browsers: [BrowserDescriptor]
    let applications: [InstalledApplication]
    let settings: AppSettings
    let editRule: (RoutingRule) -> Void

    @State private var urlText = ""
    @State private var sourceBundleID = ""
    @State private var result: RulePreviewResult?
    @State private var invalidInput = false
    @State private var isExpanded = true

    var body: some View {
        DisclosureGroup(String(localized: "rules.preview.title", defaultValue: "Test routing rules"), isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "rules.preview.description", defaultValue: "Preview the current rules and fallback settings without opening a browser. A selected source is simulated as confirmed."))
                    .font(.system(size: 12))
                    .foregroundStyle(SettingsPalette.secondary)
                WorkspaceInputField(placeholder: "https://example.com/path", text: $urlText)
                    .accessibilityLabel(String(localized: "rules.preview.url", defaultValue: "URL to preview"))
                    .accessibilityIdentifier("rules.preview.url")
                WorkspacePicker(
                    title: String(localized: "rules.preview.source", defaultValue: "Source (optional, confirmed)"),
                    selection: $sourceBundleID,
                    options: [WorkspacePickerOption(value: "", title: String(localized: "selector.source.unknown", defaultValue: "Unknown source"))]
                        + applications.map { WorkspacePickerOption(value: $0.bundleIdentifier, title: $0.displayName) }
                )
                .accessibilityIdentifier("rules.preview.source")
                Button(String(localized: "rules.preview.action", defaultValue: "Preview routing")) { preview() }
                    .buttonStyle(WorkspaceButtonStyle(kind: .secondary))
                    .accessibilityIdentifier("rules.preview.run")
                if invalidInput {
                    Text(String(localized: "rules.preview.invalid", defaultValue: "Enter a complete HTTP or HTTPS URL with a host."))
                        .font(.system(size: 12))
                        .foregroundStyle(SettingsPalette.secondary)
                }
                if let result { resultView(result) }
            }
            .padding(.top, 12)
        }
        .padding(16)
        .background(SettingsPalette.iconWell, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityIdentifier("rules.preview")
        .onChange(of: rules) { _, _ in result = nil }
        .onChange(of: browsers) { _, _ in result = nil }
        .onChange(of: settings) { _, _ in result = nil }
        .onChange(of: urlText) { _, _ in result = nil; invalidInput = false }
        .onChange(of: sourceBundleID) { _, _ in result = nil }
    }

    private func preview() {
        let source: SourceApplication
        if let application = applications.first(where: { $0.bundleIdentifier == sourceBundleID }) {
            source = SourceApplication(bundleIdentifier: application.bundleIdentifier, displayName: application.displayName, confidence: .confirmed)
        } else {
            source = .unknown
        }
        do {
            result = try RulePreview.evaluate(
                urlText: urlText,
                source: source,
                rules: rules,
                availableBrowserIDs: Set(browsers.filter { $0.availability == .available }.map(\.id)),
                settings: settings
            )
            invalidInput = false
        } catch {
            result = nil
            invalidInput = true
        }
    }

    private func resultView(_ result: RulePreviewResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(result.source == .unknown ? String(localized: "selector.source.unknown", defaultValue: "Unknown source") : result.source.displayName)
                .font(.system(size: 13, weight: .medium))
            if let rule = result.matchingRule {
                let name = rule.label ?? RuleEditorDraft(rule: rule, browsers: browsers).matchValue
                Text(String(format: String(localized: "rules.preview.matched", defaultValue: "Matched condition: %@"), name))
                Text(RuleEditorDraft(rule: rule, browsers: browsers).scopeDescription)
                Text(String(format: String(localized: "rules.preview.target", defaultValue: "Rule target: %@"), browsers.first { $0.id == rule.targetBrowserID }?.displayName ?? rule.targetBrowserID.rawValue))
                Button(String(localized: "rules.preview.edit", defaultValue: "Edit this rule")) { editRule(rule) }
                    .buttonStyle(WorkspaceButtonStyle(kind: .secondary))
                    .accessibilityIdentifier("rules.preview.edit")
            }
            switch result.decision {
            case let .open(browserID, method, _):
                if result.matchingRule == nil {
                    Text(method == .preferredBrowser ? String(localized: "Open with the preferred browser") : String(localized: "Open with the last used browser"))
                }
                Label(browsers.first { $0.id == browserID }?.displayName ?? String(localized: "Unavailable browser"), systemImage: "arrow.down.right")
            case let .ask(reason):
                Label(String(localized: "rules.preview.selector", defaultValue: "Show browser selector"), systemImage: "arrow.down.right")
                Text(SelectorReasonCopy.message(reason))
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(SettingsPalette.secondary)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SettingsPalette.group, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("rules.preview.result")
    }
}

struct RuleEditorPresentationIntent: Equatable {
    let id: UUID
    let prefill: SelectorRulePrefill?
}

@MainActor
final class RuleEditorIntentCoordinator {
    private(set) var activePresentationID: UUID?

    func beginPresentation(takePending: () -> SelectorRulePrefill?) -> RuleEditorPresentationIntent? {
        guard activePresentationID == nil else { return nil }
        let id = UUID()
        activePresentationID = id
        return RuleEditorPresentationIntent(id: id, prefill: takePending())
    }

    @discardableResult
    func finishDismissal(id: UUID) -> Bool {
        guard activePresentationID == id else { return false }
        activePresentationID = nil
        return true
    }
}
