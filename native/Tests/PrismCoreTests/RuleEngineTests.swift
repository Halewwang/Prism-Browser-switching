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
        eligibleSourceBundleIDs: ["com.tinyspeck.slackmacgap"],
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
        eligibleSourceBundleIDs: [],
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
        request: .fixture(), rules: [disabled, invalid, valid], availableBrowserIDs: [safari, chrome], eligibleSourceBundleIDs: [], settings: .defaults
    )

    #expect(decision == .open(browserID: chrome, method: .urlRule, ruleID: valid.id))
}

@Test(arguments: [
    (SourceConfidence.confirmed, "com.example.source", Set(["com.example.source"]), RoutingDecision.open(browserID: "com.apple.Safari", method: .sourceRule, ruleID: nil)),
    (SourceConfidence.confirmed, "com.example.source", Set<String>(), RoutingDecision.open(browserID: "com.apple.Safari", method: .sourceRule, ruleID: nil)),
    (SourceConfidence.low, "com.example.source", Set(["com.example.source"]), RoutingDecision.ask(reason: .sourceNotConfirmed)),
    (SourceConfidence.confirmed, "", Set(["com.example.source"]), RoutingDecision.ask(reason: .noMatchingRule))
])
func savedSourceRulesMatchAConfirmedBundleWithoutTheSupportManifest(
    confidence: SourceConfidence,
    bundleID: String,
    eligibleIDs: Set<String>,
    expected: RoutingDecision
) {
    let safari: BrowserID = "com.apple.Safari"
    let sourceRule = rule(
        matcher: .sourceBundleIdentifier("com.example.source"),
        browser: safari,
        priority: 0
    )
    let decision = RuleEngine().decide(
        request: .fixture(sourceBundleID: bundleID, confidence: confidence),
        rules: [sourceRule], availableBrowserIDs: [safari], eligibleSourceBundleIDs: eligibleIDs, settings: .defaults
    )
    #expect(decision.ignoringRuleID == expected.ignoringRuleID)
}

@Test(arguments: [
    ("5ZSL2CJU2T.com.dingtalk.mac", "com.dingtalk.mac"),
    ("com.dingtalk.mac", "5ZSL2CJU2T.com.dingtalk.mac"),
    ("com.larksuite.larkApp.helper", "com.larksuite.larkApp"),
    ("com.larksuite.larkApp.helper.renderer", "com.larksuite.larkApp")
])
func confirmedSourceRulesMatchTeamPrefixesAndHelperBundles(sourceID: String, ruleID: String) {
    let chrome: BrowserID = "com.google.Chrome"
    let sourceRule = rule(matcher: .sourceBundleIdentifier(ruleID), browser: chrome, priority: 0)

    let decision = RuleEngine().decide(
        request: .fixture(sourceBundleID: sourceID, confidence: .confirmed),
        rules: [sourceRule],
        availableBrowserIDs: [chrome],
        eligibleSourceBundleIDs: [],
        settings: .defaults
    )

    #expect(decision == .open(browserID: chrome, method: .sourceRule, ruleID: sourceRule.id))
}

@Test func unconfirmedSourceStillAsksAfterBundleNormalization() {
    let chrome: BrowserID = "com.google.Chrome"
    let sourceRule = rule(matcher: .sourceBundleIdentifier("com.dingtalk.mac"), browser: chrome, priority: 0)

    let decision = RuleEngine().decide(
        request: .fixture(sourceBundleID: "5ZSL2CJU2T.com.dingtalk.mac", confidence: .low),
        rules: [sourceRule],
        availableBrowserIDs: [chrome],
        eligibleSourceBundleIDs: [],
        settings: .defaults
    )

    #expect(decision == .ask(reason: .sourceNotConfirmed))
}

@Test func confirmedSourceRulesMatchBundleIDsCaseInsensitively() {
    let chrome: BrowserID = "com.google.Chrome"
    let sourceRule = rule(matcher: .sourceBundleIdentifier("com.larksuite.larkapp"), browser: chrome, priority: 0)

    let decision = RuleEngine().decide(
        request: .fixture(sourceBundleID: "com.larksuite.larkApp", confidence: .confirmed),
        rules: [sourceRule],
        availableBrowserIDs: [chrome],
        eligibleSourceBundleIDs: [],
        settings: .defaults
    )

    #expect(decision == .open(browserID: chrome, method: .sourceRule, ruleID: sourceRule.id))
}

@Test func helperComponentInsideAnUnrelatedBundleDoesNotCollapse() {
    let chrome: BrowserID = "com.google.Chrome"
    let sourceRule = rule(matcher: .sourceBundleIdentifier("com"), browser: chrome, priority: 0)

    let decision = RuleEngine().decide(
        request: .fixture(sourceBundleID: "com.helper.foo", confidence: .confirmed),
        rules: [sourceRule],
        availableBrowserIDs: [chrome],
        eligibleSourceBundleIDs: [],
        settings: .defaults
    )

    #expect(decision == .ask(reason: .noMatchingRule))
}

@Test func distinctApplicationsDoNotMatchThroughNormalization() {
    let chrome: BrowserID = "com.google.Chrome"
    let sourceRule = rule(matcher: .sourceBundleIdentifier("com.larksuite.larkApp"), browser: chrome, priority: 0)

    let decision = RuleEngine().decide(
        request: .fixture(sourceBundleID: "com.electron.lark", confidence: .confirmed),
        rules: [sourceRule],
        availableBrowserIDs: [chrome],
        eligibleSourceBundleIDs: [],
        settings: .defaults
    )

    #expect(decision == .ask(reason: .noMatchingRule))
}

@Test func savedSourceRulesIgnoreManifestMembership() {
    let safari: BrowserID = "com.apple.Safari"
    let sourceRule = rule(matcher: .sourceBundleIdentifier("com.example.source"), browser: safari, priority: 0)
    let request = LinkRequest.fixture(sourceBundleID: "com.example.source", confidence: .confirmed)
    let engine = RuleEngine()

    let listed = engine.decide(request: request, rules: [sourceRule], availableBrowserIDs: [safari], eligibleSourceBundleIDs: ["com.example.source"], settings: .defaults)
    let unlisted = engine.decide(request: request, rules: [sourceRule], availableBrowserIDs: [safari], eligibleSourceBundleIDs: [], settings: .defaults)

    #expect(listed == .open(browserID: safari, method: .sourceRule, ruleID: sourceRule.id))
    #expect(unlisted == .open(browserID: safari, method: .sourceRule, ruleID: sourceRule.id))
}

@Test func lowerPriorityRuleWinsWithinTheSameCategory() {
    let safari: BrowserID = "com.apple.Safari"
    let chrome: BrowserID = "com.google.Chrome"
    let higherNumber = rule(id: .test(1), matcher: .exactHost("example.com"), browser: safari, priority: 10)
    let lowerNumber = rule(id: .test(2), matcher: .exactHost("example.com"), browser: chrome, priority: 1)

    let decision = RuleEngine().decide(
        request: .fixture(), rules: [higherNumber, lowerNumber], availableBrowserIDs: [safari, chrome], eligibleSourceBundleIDs: [], settings: .defaults
    )

    #expect(decision == .open(browserID: chrome, method: .urlRule, ruleID: lowerNumber.id))
}

@Test func tiesUseRuleIDForDeterministicOrdering() {
    let safari: BrowserID = "com.apple.Safari"
    let chrome: BrowserID = "com.google.Chrome"
    let firstByID = rule(id: .test(1), matcher: .exactHost("example.com"), browser: safari, priority: 1)
    let secondByID = rule(id: .test(2), matcher: .exactHost("example.com"), browser: chrome, priority: 1)

    let decision = RuleEngine().decide(
        request: .fixture(), rules: [secondByID, firstByID], availableBrowserIDs: [safari, chrome], eligibleSourceBundleIDs: [], settings: .defaults
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
        eligibleSourceBundleIDs: [],
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
        request: .fixture(), rules: [fallback, selected], availableBrowserIDs: [chrome], eligibleSourceBundleIDs: [], settings: .defaults
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
        request: .fixture(), rules: [], availableBrowserIDs: availableIDs, eligibleSourceBundleIDs: [], settings: settings
    )

    #expect(decision == expected)
}

private extension RoutingDecision {
    var ignoringRuleID: RoutingDecision {
        if case let .open(browserID, method, _) = self {
            return .open(browserID: browserID, method: method, ruleID: nil)
        }
        return self
    }
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

@Test func rulePreviewFindsTheSameCandidateEvenWhenItsTargetIsUnavailable() {
    let request = LinkRequest.fixture(url: "https://github.com/path", sourceBundleID: "com.example.source", confidence: .low)
    let sourceRule = rule(id: .test(60), matcher: .sourceBundleIdentifier("com.example.source"), browser: "source", priority: 0)
    var urlRule = rule(id: .test(61), matcher: .exactHost("github.com"), browser: "unavailable", priority: 9)
    let engine = RuleEngine()
    #expect(engine.matchingRule(request: request, rules: [sourceRule, urlRule], settings: .defaults) == urlRule)
    #expect(engine.decide(request: request, rules: [sourceRule, urlRule], availableBrowserIDs: [], eligibleSourceBundleIDs: [], settings: .defaults) == .ask(reason: .targetUnavailable("unavailable")))
    urlRule.isEnabled = false
    #expect(engine.matchingRule(request: request, rules: [sourceRule, urlRule], settings: .defaults) == sourceRule)
    #expect(engine.decide(request: request, rules: [sourceRule, urlRule], availableBrowserIDs: ["source"], eligibleSourceBundleIDs: [], settings: .defaults) == .ask(reason: .sourceNotConfirmed))
    var paused = AppSettings.defaults
    paused.automaticRulesEnabled = false
    #expect(engine.matchingRule(request: request, rules: [sourceRule], settings: paused) == nil)
}
