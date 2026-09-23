import AppKit
import PrismCore
import SwiftUI

struct RulesManagementView: View {
    @Environment(AppEnvironment.self) private var environment

    let browserCatalog: any BrowserCataloging

    @State private var rules: [RoutingRule] = []
    @State private var browsers: [BrowserDescriptor] = []
    @State private var installedApplications: [InstalledApplication] = []
    @State private var searchText = ""
    @State private var draft: RuleEditorDraft?
    @State private var rulePendingDeletion: RoutingRule?
    @State private var errorMessage: String?
    @State private var isLoading = true

    var body: some View {
        PageColumn {
            SystemSettingsPageHeader(
                    title: "Rules",
                    subtitle: "Choose which links Prism should open automatically.",
                    accessibilityIdentifier: "appShell.page.rules.heading"
                )
                searchRow
                if isLoading {
                    ProgressView("Loading rules…")
                        .frame(maxWidth: .infinity, minHeight: 180)
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
                    .frame(maxWidth: .infinity, minHeight: 240)
                } else {
                    ruleGroup(
                        detail: "Prism evaluates these before source-application rules.",
                        rules: filteredURLRules,
                        orderedRules: urlRules
                    )
                    ruleGroup(
                        detail: "These apply only when macOS can confirm the source application.",
                        rules: filteredSourceRules,
                        orderedRules: sourceRules
                    )
                }
        }
        .task { await reload() }
        .onChange(of: environment.pendingSelectorRulePrefill) { _, prefill in
            guard draft == nil, prefill != nil else { return }
            beginCreatingRule()
        }
        .sheet(item: $draft) { draft in
            RuleEditorSheet(draft: draft, browsers: browsers, applications: installedApplications) { updatedRule in
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

    private var searchRow: some View {
        HStack(spacing: 12) {
            TextField("Search rules", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("rules.search")
            if !searchText.isEmpty || !filteredRules.isEmpty {
                Button("Create Rule", systemImage: "plus") { beginCreatingRule() }
                    .buttonStyle(.borderedProminent)
                    .disabled(browsers.allSatisfy { $0.availability != .available })
                    .accessibilityIdentifier("rules.create")
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
    private func ruleGroup(
        detail: String,
        rules: [RoutingRule],
        orderedRules: [RoutingRule]
    ) -> some View {
        if !rules.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SettingsGroup {
                    if searchText.isEmpty {
                        ForEach(Array(orderedRules.enumerated()), id: \.element.id) { index, rule in
                            ruleRow(
                                rule,
                                priority: index + 1,
                                canMoveUp: index > 0,
                                canMoveDown: index < orderedRules.count - 1,
                                moveUp: { move(orderedRules, from: index, to: index - 1) },
                                moveDown: { move(orderedRules, from: index, to: index + 1) }
                            )
                            if index < orderedRules.count - 1 {
                                SettingsSeparator()
                            }
                        }
                    } else {
                        ForEach(Array(rules.enumerated()), id: \.element.id) { index, rule in
                            ruleRow(
                                rule,
                                priority: displayedPriority(for: rule, in: orderedRules, fallback: index + 1),
                                canMoveUp: false,
                                canMoveDown: false,
                                moveUp: {},
                                moveDown: {}
                            )
                            if index < rules.count - 1 {
                                SettingsSeparator()
                            }
                        }
                    }
                }
                Text(LocalizedStringKey(detail))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
    }

    @ViewBuilder
    private func ruleRow(
        _ rule: RoutingRule,
        priority: Int,
        canMoveUp: Bool,
        canMoveDown: Bool,
        moveUp: @escaping () -> Void,
        moveDown: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ruleIcon(rule)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(rule.displayName)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text(matchDetail(rule))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
                browserIcon(for: rule.targetBrowserID)
                Text(browserName(for: rule.targetBrowserID))
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
            }
            .frame(minWidth: 0, maxWidth: 150, alignment: .leading)
            Text("\(String(localized: "Priority")) \(priority)")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
            HStack(spacing: 4) {
                Button("Increase priority", systemImage: "arrow.up") {
                    moveUp()
                }
                .labelStyle(.iconOnly)
                .disabled(!canMoveUp)
                .accessibilityLabel("Increase priority for \(rule.displayName)")
                .accessibilityIdentifier("rules.rule.\(rule.id.uuidString).moveUp")
                Button("Decrease priority", systemImage: "arrow.down") {
                    moveDown()
                }
                .labelStyle(.iconOnly)
                .disabled(!canMoveDown)
                .accessibilityLabel("Decrease priority for \(rule.displayName)")
                .accessibilityIdentifier("rules.rule.\(rule.id.uuidString).moveDown")
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
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
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

    private func save(_ rule: RoutingRule) {
        do {
            var updatedRule = rule
            if !rules.contains(where: { $0.id == rule.id }) {
                updatedRule.priority = nextPriority(for: rule)
            }
            try environment.ruleRepository.upsert(updatedRule)
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

    @ViewBuilder
    private func ruleIcon(_ rule: RoutingRule) -> some View {
        if case let .sourceBundleIdentifier(bundleIdentifier) = rule.matcher {
            ApplicationIconView(
                bundleIdentifier: bundleIdentifier,
                fallbackSymbol: rule.matcherIcon,
                side: 28
            )
        } else {
            Image(systemName: rule.matcherIcon)
                .font(.title3)
                .foregroundStyle(rule.isEnabled ? Color.accentColor : Color.secondary)
                .frame(width: 28, height: 28)
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
        browsers.first(where: { $0.id == id })?.displayName ?? "Unavailable browser"
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
    let applications: [InstalledApplication]
    let save: (RoutingRule) -> Void

    init(
        draft: RuleEditorDraft,
        browsers: [BrowserDescriptor],
        applications: [InstalledApplication],
        save: @escaping (RoutingRule) -> Void
    ) {
        _draft = State(initialValue: draft)
        self.browsers = browsers
        self.applications = applications
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

                if draft.matchKind == .sourceApplication {
                    Picker("Source application", selection: $draft.matchValue) {
                        Text("Choose an application").tag("")
                        if !draft.matchValue.isEmpty,
                           !applications.contains(where: { $0.bundleIdentifier == draft.matchValue }) {
                            Text(draft.matchValue).tag(draft.matchValue)
                        }
                        ForEach(applications) { application in
                            Text(application.displayName).tag(application.bundleIdentifier)
                        }
                    }
                    .onChange(of: draft.matchValue) { _, value in
                        guard draft.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                              let application = applications.first(where: { $0.bundleIdentifier == value })
                        else { return }
                        draft.label = application.displayName
                    }
                    if let selected = applications.first(where: { $0.bundleIdentifier == draft.matchValue }) {
                        Text(selected.bundleIdentifier)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    TextField(draft.matchKind.prompt, text: $draft.matchValue)
                        .textFieldStyle(.roundedBorder)
                }

                Text(LocalizedStringKey(draft.matchKind.hint))
                    .font(.caption)
                    .foregroundStyle(.secondary)

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
