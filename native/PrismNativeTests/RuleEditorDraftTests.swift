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
    }

    @Test func retryingCreationKeepsTheSameRuleIdentity() throws {
        var draft = RuleEditorDraft(
            prefill: .domain(host: "example.com", browserID: "com.example.browser"),
            browsers: []
        )
        let firstAttempt = try #require(draft.makeRule(now: Date(timeIntervalSince1970: 1)))
        draft.label = "Updated before retry"
        let retry = try #require(draft.makeRule(now: Date(timeIntervalSince1970: 2)))

        #expect(firstAttempt.id == draft.id)
        #expect(retry.id == firstAttempt.id)
        #expect(retry.label == "Updated before retry")
        #expect(retry.updatedAt == Date(timeIntervalSince1970: 2))
    }

    @Test func editingKeepsTheSavedRuleIdentityAndCreationDate() throws {
        let original = RoutingRule(
            id: UUID(),
            isEnabled: true,
            matcher: .exactHost("example.com"),
            targetBrowserID: "com.example.browser",
            priority: 2,
            label: "Original",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        var draft = RuleEditorDraft(rule: original, browsers: [])
        draft.label = "Edited"
        let edited = try #require(draft.makeRule(now: Date(timeIntervalSince1970: 2)))
        let retry = try #require(draft.makeRule(now: Date(timeIntervalSince1970: 3)))

        #expect(edited.id == original.id)
        #expect(retry.id == original.id)
        #expect(edited.createdAt == original.createdAt)
        #expect(edited.priority == original.priority)
        #expect(edited.label == "Edited")
    }
}
