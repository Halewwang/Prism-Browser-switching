import Foundation
import Testing
@testable import PrismCore

@Test func URLRulePrecedesSourceRule() {
    let safari: BrowserID = "com.apple.Safari"
    let chrome: BrowserID = "com.google.Chrome"
    let urlRule = rule(id: .test(2), matcher: .exactHost("github.com"), browser: chrome, priority: 99)
    let sourceRule = rule(
        id: .test(1),
        matcher: .sourceBundleIdentifier("com.tinyspeck.slackmacgap"),
        browser: safari,
        priority: 0
    )

    let decision = RuleEngine().decide(
        request: .fixture(
            url: "https://github.com/eager/prism",
            sourceBundleID: "com.tinyspeck.slackmacgap",
            confidence: .confirmed
        ),
        rules: [sourceRule, urlRule],
        availableBrowserIDs: [safari, chrome],
        settings: .defaults
    )

    #expect(decision == .open(browserID: chrome, method: .urlRule, ruleID: urlRule.id))
}

@Test(arguments: ["notgithub.com", "github.com.evil.test"])
func exactHostRejectsLookalikes(_ host: String) {
    #expect(!URLRuleMatcher.matches(.exactHost("github.com"), url: URL(string: "https://\(host)/path")!))
}

@Test func pausedRulesAlwaysAskEvenWhenPreferredBrowserExists() {
    let safari: BrowserID = "com.apple.Safari"
    var settings = AppSettings.defaults
    settings.automaticRulesEnabled = false
    settings.unmatchedBehavior = .preferredBrowser
    settings.preferredBrowserID = safari

    let decision = RuleEngine().decide(
        request: .fixture(),
        rules: [],
        availableBrowserIDs: [safari],
        settings: settings
    )

    #expect(decision == .ask(reason: .rulesPaused))
}

@Test func exactHostNormalizesCaseAndTrailingDots() {
    #expect(URLRuleMatcher.matches(.exactHost("GitHub.COM.."), url: URL(string: "https://GITHUB.com./eager")!))
}

@Test func exactHostRequiresANonemptyNormalizedHost() {
    #expect(!URLRuleMatcher.matches(.exactHost("..."), url: URL(fileURLWithPath: "/tmp/link")))
}

@Test(arguments: [
    ("https://company.com", true),
    ("https://docs.company.com", true),
    ("https://deep.docs.company.com", true),
    ("https://notcompany.com", false),
    ("https://company.com.evil.test", false)
])
func hostAndSubdomainsRespectsLabelBoundaries(url: String, expected: Bool) {
    #expect(URLRuleMatcher.matches(.hostAndSubdomains("COMPANY.com."), url: URL(string: url)!) == expected)
}

@Test func urlContainsMatchesCaseInsensitively() {
    #expect(URLRuleMatcher.matches(.urlContains("EAGER/PRISM?VIEW=GRID"), url: URL(string: "https://github.com/eager/prism?view=grid")!))
}

@Test func disabledAndInvalidRulesAreIgnored() {
    let safari: BrowserID = "com.apple.Safari"
    let chrome: BrowserID = "com.google.Chrome"
    let disabled = rule(id: .test(1), matcher: .exactHost("example.com"), browser: safari, priority: 0, isEnabled: false)
    let invalid = rule(id: .test(2), matcher: .exactHost("example.com"), browser: safari, priority: 1, validationState: .targetUnavailable)
    let valid = rule(id: .test(3), matcher: .exactHost("example.com"), browser: chrome, priority: 2)

    let decision = RuleEngine().decide(
        request: .fixture(), rules: [disabled, invalid, valid], availableBrowserIDs: [safari, chrome], settings: .defaults
    )

    #expect(decision == .open(browserID: chrome, method: .urlRule, ruleID: valid.id))
}

@Test(arguments: [
    (SourceConfidence.confirmed, "com.example.source", true),
    (SourceConfidence.low, "com.example.source", false),
    (SourceConfidence.unknown, "com.example.source", false),
    (SourceConfidence.confirmed, "", false)
])
func sourceRulesMatchConfirmedBundleIDsWithoutAWhitelist(
    confidence: SourceConfidence,
    bundleID: String,
    shouldMatch: Bool
) {
    let safari: BrowserID = "com.apple.Safari"
    let sourceRule = rule(
        matcher: .sourceBundleIdentifier("com.example.source"),
        browser: safari,
        priority: 0
    )

    let decision = RuleEngine().decide(
        request: .fixture(sourceBundleID: bundleID, confidence: confidence),
        rules: [sourceRule],
        availableBrowserIDs: [safari],
        settings: .defaults
    )

    let expected: RoutingDecision = shouldMatch
        ? .open(browserID: safari, method: .sourceRule, ruleID: sourceRule.id)
        : .ask(reason: .noMatchingRule)
    #expect(decision == expected)
}

@Test func sourceRulesHitByBundleIDWhenTheSupportManifestIsEmpty() {
    let safari: BrowserID = "com.apple.Safari"
    let sourceRule = rule(matcher: .sourceBundleIdentifier("com.example.source"), browser: safari, priority: 0)
    let request = LinkRequest.fixture(sourceBundleID: "com.example.source", confidence: .confirmed)

    let decision = RuleEngine().decide(
        request: request,
        rules: [sourceRule],
        availableBrowserIDs: [safari],
        settings: .defaults
    )

    #expect(decision == .open(browserID: safari, method: .sourceRule, ruleID: sourceRule.id))
}

@Test func lowerPriorityRuleWinsWithinTheSameCategory() {
    let safari: BrowserID = "com.apple.Safari"
    let chrome: BrowserID = "com.google.Chrome"
    let higherNumber = rule(id: .test(1), matcher: .exactHost("example.com"), browser: safari, priority: 10)
    let lowerNumber = rule(id: .test(2), matcher: .exactHost("example.com"), browser: chrome, priority: 1)

    let decision = RuleEngine().decide(
        request: .fixture(), rules: [higherNumber, lowerNumber], availableBrowserIDs: [safari, chrome], settings: .defaults
    )

    #expect(decision == .open(browserID: chrome, method: .urlRule, ruleID: lowerNumber.id))
}

@Test func tiesUseRuleIDForDeterministicOrdering() {
    let safari: BrowserID = "com.apple.Safari"
    let chrome: BrowserID = "com.google.Chrome"
    let firstByID = rule(id: .test(1), matcher: .exactHost("example.com"), browser: safari, priority: 1)
    let secondByID = rule(id: .test(2), matcher: .exactHost("example.com"), browser: chrome, priority: 1)

    let decision = RuleEngine().decide(
        request: .fixture(), rules: [secondByID, firstByID], availableBrowserIDs: [safari, chrome], settings: .defaults
    )

    #expect(decision == .open(browserID: safari, method: .urlRule, ruleID: firstByID.id))
}

@Test func interleavedURLMatchersUseSharedPriorityAndIDOrdering() {
    let safari: BrowserID = "com.apple.Safari"
    let chrome: BrowserID = "com.google.Chrome"
    let firefox: BrowserID = "org.mozilla.firefox"
    let exact = rule(id: .test(9), matcher: .exactHost("example.com"), browser: safari, priority: 8)
    let subdomain = rule(id: .test(5), matcher: .hostAndSubdomains("example.com"), browser: chrome, priority: 1)
    let contains = rule(id: .test(4), matcher: .urlContains("example.com"), browser: firefox, priority: 1)

    let decision = RuleEngine().decide(
        request: .fixture(url: "https://example.com/path"),
        rules: [exact, subdomain, contains],
        availableBrowserIDs: [safari, chrome, firefox],
        settings: .defaults
    )

    #expect(decision == .open(browserID: firefox, method: .urlRule, ruleID: contains.id))
}

@Test func selectedUnavailableRuleTargetAsksWithoutFallingThrough() {
    let unavailableSafari: BrowserID = "com.apple.Safari"
    let chrome: BrowserID = "com.google.Chrome"
    let selected = rule(id: .test(1), matcher: .exactHost("example.com"), browser: unavailableSafari, priority: 0)
    let fallback = rule(id: .test(2), matcher: .exactHost("example.com"), browser: chrome, priority: 1)

    let decision = RuleEngine().decide(
        request: .fixture(), rules: [fallback, selected], availableBrowserIDs: [chrome], settings: .defaults
    )

    #expect(decision == .ask(reason: .targetUnavailable(unavailableSafari)))
}

@Test(arguments: [
    (UnmatchedBehavior.alwaysAsk, Optional<BrowserID>.none, Optional<BrowserID>.none, Set<BrowserID>(), RoutingDecision.ask(reason: .noMatchingRule)),
    (.preferredBrowser, BrowserID("com.apple.Safari"), nil, Set([BrowserID("com.apple.Safari")]), .open(browserID: "com.apple.Safari", method: .preferredBrowser, ruleID: nil)),
    (.preferredBrowser, nil, nil, Set<BrowserID>(), .ask(reason: .preferredBrowserUnavailable(nil))),
    (.preferredBrowser, BrowserID("com.apple.Safari"), nil, Set<BrowserID>(), .ask(reason: .preferredBrowserUnavailable("com.apple.Safari"))),
    (.lastUsedBrowser, nil, BrowserID("com.google.Chrome"), Set([BrowserID("com.google.Chrome")]), .open(browserID: "com.google.Chrome", method: .lastUsedBrowser, ruleID: nil)),
    (.lastUsedBrowser, nil, nil, Set<BrowserID>(), .ask(reason: .preferredBrowserUnavailable(nil))),
    (.lastUsedBrowser, nil, BrowserID("com.google.Chrome"), Set<BrowserID>(), .ask(reason: .preferredBrowserUnavailable("com.google.Chrome")))
])
func unmatchedBehaviorsReturnTheApprovedDecision(
    behavior: UnmatchedBehavior,
    preferredID: BrowserID?,
    lastUsedID: BrowserID?,
    availableIDs: Set<BrowserID>,
    expected: RoutingDecision
) {
    var settings = AppSettings.defaults
    settings.unmatchedBehavior = behavior
    settings.preferredBrowserID = preferredID
    settings.lastUsedBrowserID = lastUsedID

    let decision = RuleEngine().decide(
        request: .fixture(), rules: [], availableBrowserIDs: availableIDs, settings: settings
    )

    #expect(decision == expected)
}

private func rule(
    id: UUID = .test(100),
    matcher: RuleMatcher,
    browser: BrowserID,
    priority: Int,
    isEnabled: Bool = true,
    validationState: RuleValidationState = .valid
) -> RoutingRule {
    RoutingRule(
        id: id,
        isEnabled: isEnabled,
        matcher: matcher,
        targetBrowserID: browser,
        priority: priority,
        label: nil,
        validationState: validationState,
        createdAt: Date(timeIntervalSince1970: 1),
        updatedAt: Date(timeIntervalSince1970: 2)
    )
}
