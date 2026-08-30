import AppKit
import PrismCore
import SwiftUI

struct SourceApplicationPicker: View {
    @Binding var draft: RuleEditorDraft

    let excludedBundleIDs: Set<String>
    private let runningApplications: any RunningSourceApplicationListing
    private let fileChooser: any SourceApplicationFileChoosing

    init(
        draft: Binding<RuleEditorDraft>,
        excludedBundleIDs: Set<String>,
        runningApplications: any RunningSourceApplicationListing = WorkspaceRunningSourceApplicationCatalog(),
        fileChooser: any SourceApplicationFileChoosing = SystemSourceApplicationFileChooser()
    ) {
        _draft = draft
        self.excludedBundleIDs = excludedBundleIDs
        self.runningApplications = runningApplications
        self.fileChooser = fileChooser
    }

    var body: some View {
        HStack(spacing: 10) {
            sourceIcon
                .frame(width: 22, height: 22)
            Text(visibleName)
                .lineLimit(1)
            Spacer(minLength: 8)
            Menu {
                ForEach(menuApplications) { application in
                    Button {
                        draft.selectSource(
                            bundleIdentifier: application.bundleIdentifier,
                            displayName: application.displayName
                        )
                    } label: {
                        if let icon = InstalledApplicationLookup.icon(forBundleIdentifier: application.bundleIdentifier) {
                            Label {
                                Text(application.displayName)
                            } icon: {
                                Image(nsImage: icon)
                            }
                        } else {
                            Text(application.displayName)
                        }
                    }
                }
                Divider()
                Button(String(localized: "rules.source.chooseApplication", defaultValue: "Choose Application…")) {
                    chooseFromPanel()
                }
            } label: {
                Text(
                    draft.hasSourceSelection
                        ? String(localized: "rules.source.change", defaultValue: "Change…")
                        : String(localized: "rules.source.choose", defaultValue: "Choose…")
                )
            }
            .fixedSize()
            .accessibilityIdentifier("rules.sourcePicker.menu")
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("rules.sourcePicker")
        .accessibilityLabel(String(localized: "rules.source.picker", defaultValue: "Source application"))
        .accessibilityValue(visibleName)
    }

    private var menuApplications: [RunningSourceApplication] {
        runningApplications.runningApplications(excludingBundleIDs: excludedBundleIDs)
    }

    private var visibleName: String {
        if !draft.hasSourceSelection {
            return String(localized: "rules.source.empty", defaultValue: "Choose Application")
        }
        return SourceRulePresentation(
            bundleIdentifier: draft.matchValue,
            label: draft.sourceDisplayName.isEmpty ? draft.label : draft.sourceDisplayName,
            installedDisplayName: InstalledApplicationLookup.displayName(forBundleIdentifier: draft.matchValue)
        ).title
    }

    @ViewBuilder
    private var sourceIcon: some View {
        if draft.hasSourceSelection,
           let icon = InstalledApplicationLookup.icon(forBundleIdentifier: draft.matchValue) {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "app.dashed")
                .foregroundStyle(.secondary)
        }
    }

    private func chooseFromPanel() {
        guard let url = fileChooser.chooseApplication(),
              let identity = InstalledApplicationLookup.identity(at: url)
        else {
            return
        }
        draft.selectSource(bundleIdentifier: identity.bundleIdentifier, displayName: identity.displayName)
    }
}
