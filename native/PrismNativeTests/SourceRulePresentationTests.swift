import Foundation
import Testing
@testable import PrismNative

@Suite("Source rule presentation")
struct SourceRulePresentationTests {
    @Test func prefersAHumanLabelAndNeverUsesABundleIdentifierAsTheTitle() {
        let presentation = SourceRulePresentation(
            bundleIdentifier: "com.tinyspeck.slackmacgap",
            label: "Slack",
            installedDisplayName: "Slack"
        )

        #expect(presentation.title == "Slack")
        #expect(presentation.isInstalled)
    }

    @Test func usesTheInstalledNameWhenTheLabelIsMissing() {
        let presentation = SourceRulePresentation(
            bundleIdentifier: "com.tinyspeck.slackmacgap",
            label: nil,
            installedDisplayName: "Slack"
        )

        #expect(presentation.title == "Slack")
        #expect(presentation.isInstalled)
    }

    @Test func uninstalledAppsStayUntitledInsteadOfShowingABundleID() {
        let presentation = SourceRulePresentation(
            bundleIdentifier: "com.example.removed",
            label: "com.example.removed",
            installedDisplayName: nil
        )

        #expect(presentation.title == String(localized: "rules.source.untitled", defaultValue: "Unknown Application"))
        #expect(presentation.isInstalled == false)
        #expect(!presentation.title.contains("com."))
    }
}
