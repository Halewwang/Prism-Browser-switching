import Foundation
import PrismCore
import Testing
@testable import PrismNative

@Suite("Rule editor draft")
struct RuleEditorDraftTests {
    @Test func domainDraftNormalizesInputAndPreservesTheSelectedBrowser() {
        let browser = BrowserDescriptor(
            id: "com.example.browser",
            bundleIdentifier: "com.example.browser",
            displayName: "Example Browser",
            applicationURL: URL(fileURLWithPath: "/Applications/Example Browser.app"),
            securityScopedBookmark: nil,
            origin: .system,
            availability: .available,
            selectorOrder: 0
        )
        var draft = RuleEditorDraft(browsers: [browser])
        draft.matchKind = .domainAndSubdomains
        draft.matchValue = "https://Docs.Example.com/path"

        let rule = draft.makeRule(now: Date(timeIntervalSince1970: 1))

        #expect(rule?.matcher == .hostAndSubdomains("docs.example.com"))
        #expect(rule?.targetBrowserID == browser.id)
        #expect(rule?.isEnabled == true)
    }

    @Test func selectorSourcePrefillBuildsAnEnabledSourceRule() {
        let browser = BrowserDescriptor(
            id: "com.example.browser",
            bundleIdentifier: "com.example.browser",
            displayName: "Example Browser",
            applicationURL: URL(fileURLWithPath: "/Applications/Example Browser.app"),
            securityScopedBookmark: nil,
            origin: .system,
            availability: .available,
            selectorOrder: 0
        )
        let draft = RuleEditorDraft(
            prefill: .source(
                bundleIdentifier: "com.example.source",
                displayName: "Example Source",
                browserID: browser.id
            ),
            browsers: [browser]
        )

        let rule = draft.makeRule(now: Date(timeIntervalSince1970: 1))

        #expect(rule?.matcher == .sourceBundleIdentifier("com.example.source"))
        #expect(rule?.label == "Example Source")
        #expect(rule?.targetBrowserID == browser.id)
        #expect(draft.sourceDisplayName == "Example Source")
        #expect(draft.hasSourceSelection)
    }

    @Test func selectingASourcePersistsBundleIDAndFillsAnEmptyLabel() {
        let browser = exampleBrowser()
        var draft = RuleEditorDraft(browsers: [browser])
        draft.changeMatchKind(.sourceApplication)

        #expect(draft.matchValue.isEmpty)
        #expect(draft.sourceDisplayName.isEmpty)

        draft.selectSource(bundleIdentifier: "com.example.source", displayName: "Example Source")
        let rule = draft.makeRule(now: Date(timeIntervalSince1970: 1))

        #expect(rule?.matcher == .sourceBundleIdentifier("com.example.source"))
        #expect(rule?.label == "Example Source")
        #expect(draft.sourceDisplayName == "Example Source")
    }

    @Test func selectingASourceDoesNotOverwriteAnExistingLabel() {
        let browser = exampleBrowser()
        var draft = RuleEditorDraft(browsers: [browser])
        draft.changeMatchKind(.sourceApplication)
        draft.label = "Work links"
        draft.selectSource(bundleIdentifier: "com.example.source", displayName: "Example Source")

        #expect(draft.label == "Work links")
        #expect(draft.makeRule(now: Date(timeIntervalSince1970: 1))?.label == "Work links")
    }

    @Test func leavingSourceMatchTypeClearsTheSelection() {
        let browser = exampleBrowser()
        var draft = RuleEditorDraft(
            prefill: .source(
                bundleIdentifier: "com.example.source",
                displayName: "Example Source",
                browserID: browser.id
            ),
            browsers: [browser]
        )

        draft.changeMatchKind(.urlContains)

        #expect(draft.matchKind == .urlContains)
        #expect(draft.matchValue.isEmpty)
        #expect(draft.sourceDisplayName.isEmpty)
        #expect(!draft.hasSourceSelection)
    }
}

private func exampleBrowser() -> BrowserDescriptor {
    BrowserDescriptor(
        id: "com.example.browser",
        bundleIdentifier: "com.example.browser",
        displayName: "Example Browser",
        applicationURL: URL(fileURLWithPath: "/Applications/Example Browser.app"),
        securityScopedBookmark: nil,
        origin: .system,
        availability: .available,
        selectorOrder: 0
    )
}
