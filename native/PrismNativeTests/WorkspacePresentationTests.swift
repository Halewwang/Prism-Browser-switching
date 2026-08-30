import Foundation
import PrismCore
import Testing
@testable import PrismNative

@Suite("Workspace presentation copy")
struct WorkspacePresentationTests {
    @Test func rulePreviewSentenceNamesTheMatcherAndBrowser() {
        let exact = rule(matcher: .exactHost("calendar.example.com"))
        let subdomain = rule(matcher: .hostAndSubdomains("docs.example.com"))
        let contains = rule(matcher: .urlContains("preview"))
        let source = rule(matcher: .sourceBundleIdentifier("com.example.messages"))

        #expect(WorkspaceCopy.rulePreviewSentence(for: exact, browserName: "Safari")
            .contains("calendar.example.com"))
        #expect(WorkspaceCopy.rulePreviewSentence(for: exact, browserName: "Safari").contains("Safari"))
        #expect(WorkspaceCopy.rulePreviewSentence(for: subdomain, browserName: "Chrome")
            .contains("docs.example.com"))
        #expect(WorkspaceCopy.rulePreviewSentence(for: contains, browserName: "Arc").contains("preview"))
        #expect(WorkspaceCopy.rulePreviewSentence(for: source, browserName: "Arc")
            .contains("com.example.messages"))
        #expect(source.isSourceRule)
        #expect(!exact.isSourceRule)
        #expect(source.matcherIcon == "app.badge")
        #expect(exact.matcherIcon == "globe")
        #expect(subdomain.displayName == "Documentation")
    }

    @Test func browserInspectorCopyUsesOneBasedSelectorOrder() {
        #expect(WorkspaceCopy.selectorPosition(order: 0, count: 3, locale: Locale(identifier: "en"))
            .contains("1"))
        #expect(WorkspaceCopy.selectorPosition(order: 0, count: 3, locale: Locale(identifier: "en"))
            .contains("3"))
        #expect(WorkspaceCopy.keyboardShortcut(order: 0) != nil)
        #expect(WorkspaceCopy.keyboardShortcut(order: 8) != nil)
        #expect(WorkspaceCopy.keyboardShortcut(order: 9) == nil)
        #expect(WorkspaceCopy.ruleReferenceCount(1, locale: Locale(identifier: "en")).contains("1"))
        #expect(WorkspaceCopy.ruleReferenceCount(2, locale: Locale(identifier: "en")).contains("2"))
    }

    @Test func englishAndChineseWorkspaceKeysStayPaired() throws {
        let nativeRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let english = try keys(in: nativeRoot.appending(path: "PrismNative/Resources/en.lproj/Localizable.strings"))
        let chinese = try keys(in: nativeRoot.appending(path: "PrismNative/Resources/zh-Hans.lproj/Localizable.strings"))
        #expect(english == chinese)
        #expect(english.contains("Prism uses"))
        #expect(english.contains("When no rule matches, Prism will"))
        #expect(english.contains("Selector position %lld of %lld"))
    }

    @Test func workspaceCopyLooksUpLocalizedSentenceKeys() {
        #expect(NSLocalizedString("Prism uses", comment: "") != "")
        #expect(NSLocalizedString("When no rule matches, Prism will", comment: "") != "")
        #expect(NSLocalizedString("Selector position %lld of %lld", comment: "") != "")
        #expect(NSLocalizedString("Used by %lld rules", comment: "") != "")
    }

    @Test func settingsSentencesStayNaturalLanguage() {
        #expect(
            WorkspaceCopy.defaultHandlerSentence(for: .active)
                != WorkspaceCopy.defaultHandlerSentence(for: .inactive(http: false, https: false))
        )
        #expect(!WorkspaceCopy.languageSentenceLead().isEmpty)
        #expect(!WorkspaceCopy.unmatchedSentenceLead().isEmpty)
        #expect(WorkspaceCopy.historyLimit(100, locale: Locale(identifier: "en")).contains("100"))
        #expect(WorkspaceCopy.historyRetention(30, locale: Locale(identifier: "en")).contains("30"))
    }

    private func keys(in url: URL) throws -> Set<String> {
        let contents = try String(contentsOf: url, encoding: .utf8)
        let regex = try NSRegularExpression(pattern: #"^"((?:\\.|[^"\\])*)"\s*="#, options: [.anchorsMatchLines])
        let range = NSRange(contents.startIndex..., in: contents)
        return Set(regex.matches(in: contents, range: range).compactMap { match in
            Range(match.range(at: 1), in: contents).map { String(contents[$0]) }
        })
    }

    private func rule(matcher: RuleMatcher) -> RoutingRule {
        RoutingRule(
            id: UUID(),
            isEnabled: true,
            matcher: matcher,
            targetBrowserID: "com.example.browser",
            priority: 0,
            label: matcher.isSource ? nil : "Documentation",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 1)
        )
    }
}

private extension RuleMatcher {
    var isSource: Bool {
        if case .sourceBundleIdentifier = self { return true }
        return false
    }
}
