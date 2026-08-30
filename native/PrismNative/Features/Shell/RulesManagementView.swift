import PrismCore
import SwiftUI

struct RulesManagementView: View {
    @Environment(AppEnvironment.self) private var environment

    let browserCatalog: any BrowserCataloging

    @State private var rules: [RoutingRule] = []
    @State private var browsers: [BrowserDescriptor] = []
    @State private var searchText = ""
    @State private var selectedRuleID: UUID?
    @State private var draft: RuleEditorDraft?
    @State private var rulePendingDeletion: RoutingRule?
    @State private var errorMessage: String?
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            header
            if isLoading {
                ProgressView("Loading rules…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredRules.isEmpty {
                VStack(spacing: 16) {
                    ContentUnavailableView(
                        searchText.isEmpty ? "No routing rules" : "No matching rules",
                        systemImage: searchText.isEmpty ? "list.bullet.rectangle" : "magnifyingglass",
                        description: Text(searchText.isEmpty
                            ? "Create a rule to send matching links to a browser automatically."
                            : "Try a different search.")
                    )
                    if searchText.isEmpty {
                        Button("Create Rule") { beginCreatingRule() }
                            .buttonStyle(WorkspacePrimaryCapsuleStyle())
                            .disabled(browsers.allSatisfy { $0.availability != .available })
                            .accessibilityIdentifier("rules.create")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        rulePreviewCard
                        ruleList
                    }
                    .padding(.horizontal, WorkspaceLayout.contentInset)
                    .padding(.bottom, 28)
                }
            }
        }
        .tint(.primary)
        .background(WorkspacePalette.canvas)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await reload() }
        .onChange(of: searchText) { _, _ in
            selectRuleIfNeeded()
        }
        .onChange(of: environment.pendingSelectorRulePrefill) { _, prefill in
            guard draft == nil, prefill != nil else { return }
            beginCreatingRule()
        }
        .sheet(item: $draft) { draft in
            RuleEditorSheet(draft: draft, browsers: browsers) { updatedRule in
                save(updatedRule)
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

    private var header: some View {
        WorkspacePageHeader(
            title: "Rules",
            headingIdentifier: "appShell.page.rules.heading"
        ) {
            HStack(spacing: 8) {
                TextField("Search rules", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                    .accessibilityIdentifier("rules.search")
                if !searchText.isEmpty || !filteredRules.isEmpty {
                    Button("Create Rule", systemImage: "plus") { beginCreatingRule() }
                        .buttonStyle(WorkspacePrimaryCapsuleStyle())
                        .disabled(browsers.allSatisfy { $0.availability != .available })
                        .accessibilityIdentifier("rules.create")
                }
            }
        }
    }

    private var filteredRules: [RoutingRule] {
        guard !searchText.isEmpty else { return rules }
        return rules.filter { rule in
            return rule.displayName.localizedCaseInsensitiveContains(searchText)
                || rule.matcherDisplayName.localizedCaseInsensitiveContains(searchText)
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

    @ViewBuilder
    private var rulePreviewCard: some View {
        if let rule = selectedRule {
            let orderedRules = rule.isSourceRule ? sourceRules : urlRules
            let index = orderedRules.firstIndex(where: { $0.id == rule.id }) ?? 0
            VStack(alignment: .leading, spacing: 14) {
                WorkspacePreviewCard(accessibilityIdentifier: "rules.inspector") {
                    WorkspaceCornerWidgetScene(
                        address: ruleAddress(for: rule),
                        browser: browsers.first(where: { $0.id == rule.targetBrowserID })
                    )
                }
                Text(WorkspaceCopy.rulePreviewSentence(for: rule, browserName: browserName(for: rule.targetBrowserID)))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("rules.inspector.sentence")

                HStack(spacing: 8) {
                    Text("Priority \(index + 1)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Button("Increase priority", systemImage: "arrow.up") {
                        move(orderedRules, from: index, to: index - 1)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(WorkspaceSecondaryCapsuleStyle())
                    .disabled(searchText.isEmpty ? index == 0 : true)
                    .accessibilityLabel("Increase priority for \(rule.displayName)")
                    .accessibilityIdentifier("rules.rule.\(rule.id.uuidString).moveUp")
                    Button("Decrease priority", systemImage: "arrow.down") {
                        move(orderedRules, from: index, to: index + 1)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(WorkspaceSecondaryCapsuleStyle())
                    .disabled(searchText.isEmpty ? index >= orderedRules.count - 1 : true)
                    .accessibilityLabel("Decrease priority for \(rule.displayName)")
                    .accessibilityIdentifier("rules.rule.\(rule.id.uuidString).moveDown")
                    Spacer(minLength: 0)
                    Button("Edit") {
                        draft = RuleEditorDraft(rule: rule, browsers: browsers)
                    }
                    .buttonStyle(WorkspaceSecondaryCapsuleStyle())
                    Button("Delete", role: .destructive) {
                        rulePendingDeletion = rule
                    }
                    .buttonStyle(WorkspaceSecondaryCapsuleStyle())
                }
            }
        } else {
            WorkspacePreviewCard(accessibilityIdentifier: "rules.inspector") {
                WorkspaceCornerWidgetScene(address: "https://example.com", browser: browsers.first)
            }
        }
    }

    private var ruleList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(filteredURLRules, id: \.id) { rule in
                ruleRow(rule, priority: displayedPriority(for: rule, in: urlRules, fallback: 1))
            }
            if !filteredSourceRules.isEmpty {
                Text("Source-application rules")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.top, 10)
                Text("These apply only when macOS can confirm the source application.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                ForEach(filteredSourceRules, id: \.id) { rule in
                    ruleRow(rule, priority: displayedPriority(for: rule, in: sourceRules, fallback: 1))
                }
            }
        }
    }

    @ViewBuilder
    private func ruleRow(_ rule: RoutingRule, priority: Int) -> some View {
        Button {
            selectedRuleID = rule.id
        } label: {
            HStack(spacing: 12) {
                Image(systemName: rule.matcherIcon)
                    .frame(width: 22)
                    .foregroundStyle(rule.isEnabled ? Color.primary : Color.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(rule.displayName)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text("\(rule.matcherDisplayName)  →  \(browserName(for: rule.targetBrowserID))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text("Priority \(priority)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, WorkspaceLayout.listRowVerticalPadding)
            .background(
                selectedRuleID == rule.id ? WorkspacePalette.rowSelection : Color.clear,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("rules.row.\(rule.id.uuidString)")
    }

    private var selectedRule: RoutingRule? {
        filteredRules.first(where: { $0.id == selectedRuleID })
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
            rules = try normalizePriorities(in: environment.ruleRepository.all())
            selectRuleIfNeeded()
            if draft == nil, environment.pendingSelectorRulePrefill != nil {
                beginCreatingRule()
            }
        } catch {
            errorMessage = "Prism could not load your saved rules or browser list."
        }
    }

    private func selectRuleIfNeeded() {
        if let selectedRuleID, filteredRules.contains(where: { $0.id == selectedRuleID }) {
            return
        }
        selectedRuleID = filteredRules.first?.id
    }

    private func save(_ rule: RoutingRule) {
        do {
            var updatedRule = rule
            if !rules.contains(where: { $0.id == rule.id }) {
                updatedRule.priority = nextPriority(for: rule)
            }
            try environment.ruleRepository.upsert(updatedRule)
            rules = try environment.ruleRepository.all()
            selectedRuleID = updatedRule.id
        } catch {
            errorMessage = "Prism could not save this rule."
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
            selectRuleIfNeeded()
        } catch {
            errorMessage = "Prism could not delete this rule."
        }
    }

    private func browserName(for id: BrowserID) -> String {
        browsers.first(where: { $0.id == id })?.displayName ?? "Unavailable browser"
    }

    private func ruleAddress(for rule: RoutingRule) -> String {
        switch rule.matcher {
        case let .exactHost(host), let .hostAndSubdomains(host):
            host.contains("://") ? host : "https://\(host)"
        case let .urlContains(value):
            value.contains("://") ? value : "https://\(value)"
        case .sourceBundleIdentifier:
            "https://example.com"
        }
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

    let browsers: [BrowserDescriptor]
    let save: (RoutingRule) -> Void

    init(draft: RuleEditorDraft, browsers: [BrowserDescriptor], save: @escaping (RoutingRule) -> Void) {
        _draft = State(initialValue: draft)
        self.browsers = browsers
        self.save = save
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(draft.existingRule == nil ? "Create Rule" : "Edit Rule")
                .font(.title2.weight(.semibold))

            Form {
                Picker("Match", selection: $draft.matchKind) {
                    ForEach(RuleMatchKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }

                TextField(draft.matchKind.prompt, text: $draft.matchValue)
                    .textFieldStyle(.roundedBorder)

                Picker("Open in", selection: $draft.targetBrowserID) {
                    Text("Choose a browser").tag(BrowserID?.none)
                    ForEach(browsers.filter { $0.availability == .available }, id: \.id) { browser in
                        Text(browser.displayName).tag(BrowserID?.some(browser.id))
                    }
                }

                TextField("Optional label", text: $draft.label)
                    .textFieldStyle(.roundedBorder)

                Toggle("Enable this rule", isOn: $draft.isEnabled)
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(draft.existingRule == nil ? "Create Rule" : "Save Changes") {
                    guard let rule = draft.makeRule() else { return }
                    save(rule)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!draft.canSave)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}
