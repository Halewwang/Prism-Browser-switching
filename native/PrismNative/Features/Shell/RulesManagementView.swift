import PrismCore
import SwiftUI

struct RulesManagementView: View {
    @Environment(AppEnvironment.self) private var environment

    let browserCatalog: any BrowserCataloging

    @State private var rules: [RoutingRule] = []
    @State private var browsers: [BrowserDescriptor] = []
    @State private var searchText = ""
    @State private var draft: RuleEditorDraft?
    @State private var rulePendingDeletion: RoutingRule?
    @State private var errorMessage: String?
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
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
                            .buttonStyle(.borderedProminent)
                            .disabled(browsers.allSatisfy { $0.availability != .available })
                            .accessibilityIdentifier("rules.create")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredRules, id: \.id) { rule in
                        ruleRow(rule)
                    }
                }
                .listStyle(.inset)
            }
        }
        .task { await reload() }
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
            Text(errorMessage ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Rules")
                    .font(.title2.weight(.semibold))
                    .accessibilityIdentifier("appShell.page.rules.heading")
                Text("Choose which links Prism should open automatically.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 20)
            TextField("Search rules", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 220)
                .accessibilityIdentifier("rules.search")
            if !searchText.isEmpty || !filteredRules.isEmpty {
                Button("Create Rule", systemImage: "plus") { beginCreatingRule() }
                    .buttonStyle(.borderedProminent)
                    .disabled(browsers.allSatisfy { $0.availability != .available })
                    .accessibilityIdentifier("rules.create")
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private var filteredRules: [RoutingRule] {
        guard !searchText.isEmpty else { return rules }
        return rules.filter { rule in
            return rule.displayName.localizedCaseInsensitiveContains(searchText)
                || rule.matcherDisplayName.localizedCaseInsensitiveContains(searchText)
                || browserName(for: rule.targetBrowserID).localizedCaseInsensitiveContains(searchText)
        }
    }

    @ViewBuilder
    private func ruleRow(_ rule: RoutingRule) -> some View {
        HStack(spacing: 14) {
            Image(systemName: rule.matcherIcon)
                .frame(width: 22)
                .foregroundStyle(rule.isEnabled ? Color.accentColor : Color.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(rule.displayName)
                    .font(.body.weight(.medium))
                Text("\(rule.matcherDisplayName)  →  \(browserName(for: rule.targetBrowserID))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Enable rule", isOn: Binding(
                get: { rule.isEnabled },
                set: { _ in toggle(rule) }
            ))
            .labelsHidden()
            .accessibilityLabel("Enable \(rule.displayName)")
            Button("Edit", systemImage: "pencil") {
                draft = RuleEditorDraft(rule: rule, browsers: browsers)
            }
            .labelStyle(.iconOnly)
            Button("Delete", systemImage: "trash") {
                rulePendingDeletion = rule
            }
            .labelStyle(.iconOnly)
            .foregroundStyle(.red)
        }
        .padding(.vertical, 5)
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
            rules = try environment.ruleRepository.all()
            if draft == nil, environment.pendingSelectorRulePrefill != nil {
                beginCreatingRule()
            }
        } catch {
            errorMessage = "Prism could not load your saved rules or browser list."
        }
    }

    private func save(_ rule: RoutingRule) {
        do {
            try environment.ruleRepository.upsert(rule)
            rules = try environment.ruleRepository.all()
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
        } catch {
            errorMessage = "Prism could not delete this rule."
        }
    }

    private func browserName(for id: BrowserID) -> String {
        browsers.first(where: { $0.id == id })?.displayName ?? "Unavailable browser"
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

private extension RoutingRule {
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
