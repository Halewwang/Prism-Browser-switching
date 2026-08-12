# Prism Native macOS 1.0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Electron runtime with a public-release-quality native macOS 15+ Prism application that never automatically sends the same captured link twice, preserves ordered recovery when delivery outcome is uncertain, routes through explicit rules or the approved Figma selector, and ships as a signed, notarized Universal application.

**Architecture:** A local Swift package contains domain models, routing, queueing, privacy, and history transitions without UI or AppKit dependencies. The macOS application uses SwiftUI for feature screens, AppKit for URL events, panels, windows, and status items, SwiftData for native persistence, and isolated services for `NSWorkspace`, default handlers, login items, source attribution, and Sparkle.

**Tech Stack:** Swift 6, Swift Testing, SwiftUI, AppKit, Observation, SwiftData, ServiceManagement, XcodeGen 2.46.0, Sparkle 2.9.4, XCTest/XCUITest, macOS 15 SDK.

## Global Constraints

- Minimum deployment target is macOS 15.0.
- Product bundle identifier remains `com.prism.app` so the native build replaces the existing product identity.
- Native data starts fresh and never reads or deletes Electron rules, settings, custom browsers, or history.
- Unmatched links default to Always Ask.
- URL rules precede source-application rules; visible order wins within each rule type.
- Source rules are disabled for an application until the source validation matrix records zero false attributions and at least 95% confirmed attribution.
- Unknown or low-confidence sources never match source rules.
- No link may be overwritten or silently discarded. Prism never automatically retries an attempt whose system-delivery outcome is uncertain; the user must choose Retry or Mark Completed.
- The selector uses Figma file `c1PRx6G3c4z9O9jnerReHW`, node `4:395`, at a fixed 425 × 200 point content size.
- More than three browsers show three complete items and half of the fourth in a horizontal scroll view; no arrows or visible scroll bar are added.
- Full URLs may exist only in temporary recovery storage; persisted history stores sanitized URLs.
- Direct distribution uses a Universal DMG, Developer ID, Hardened Runtime, notarization, stapling, Gatekeeper validation, and a signed Sparkle appcast.
- Browser profiles, private/incognito windows, regular expressions, AI routing, cloud sync, rule import/export, team rules, time/network/location/workspace routing, browser-extension integration, Mac App Store distribution, and silent updates are excluded from 1.0.
- Keep the existing Electron source during native development; remove it only in the final cutover task after native release acceptance passes.
- Every production behavior follows red-green-refactor: write a failing test, verify the expected failure, implement the minimum behavior, and rerun the focused and full suites.
- Before Task 5, select the installed full Xcode with `xcode-select`, accept its license, and install XcodeGen 2.46.0; do not claim AppKit or UI verification while Command Line Tools remain selected.
- `native/PrismNative.xcodeproj` is generated and gitignored. Run `zsh scripts/generate-project.sh` immediately before every `xcodebuild` invocation so newly added files and targets cannot be skipped.

## Planned File Structure

```text
native/
├── Package.swift
├── project.yml
├── Sources/PrismCore/
│   ├── Models/
│   │   ├── AppSettings.swift
│   │   ├── BrowserDescriptor.swift
│   │   ├── HistoryEntry.swift
│   │   ├── LinkRequest.swift
│   │   └── RoutingRule.swift
│   ├── History/HistoryStateMachine.swift
│   ├── Privacy/URLSanitizer.swift
│   ├── Queue/LinkRequestQueue.swift
│   ├── Queue/PendingRequestStore.swift
│   └── Routing/RuleEngine.swift
├── Tests/PrismCoreTests/
│   ├── TestFixtures.swift
│   └── …
├── PrismNative/
│   ├── App/
│   │   ├── AppDelegate.swift
│   │   ├── AppEnvironment.swift
│   │   ├── AppRoute.swift
│   │   └── PrismNativeApp.swift
│   ├── Features/
│   │   ├── Browsers/
│   │   ├── History/
│   │   ├── Onboarding/
│   │   ├── Rules/
│   │   ├── Selector/
│   │   ├── Settings/
│   │   └── Shell/
│   ├── MenuBar/StatusItemController.swift
│   ├── Persistence/
│   ├── Resources/
│   │   ├── Assets.xcassets/
│   │   │   └── AppIcon.appiconset/
│   │   ├── Base.lproj/Main.strings
│   │   ├── en.lproj/Localizable.strings
│   │   ├── zh-Hans.lproj/Localizable.strings
│   │   ├── Info.plist
│   │   ├── SupportedSources.json
│   │   └── PrismNative.entitlements
│   ├── System/
│   ├── Updates/
│   └── Windows/
├── PrismNativeTests/
├── PrismNativeUITests/
└── scripts/
    ├── generate-project.sh
    ├── verify-release.sh
    └── package-release.sh
```

---

## Phase A — Pure Swift Core

### Task 1: Create the Swift Package and Domain Models

**Files:**
- Create: `native/Package.swift`
- Create: `native/Sources/PrismCore/Models/BrowserDescriptor.swift`
- Create: `native/Sources/PrismCore/Models/RoutingRule.swift`
- Create: `native/Sources/PrismCore/Models/LinkRequest.swift`
- Create: `native/Sources/PrismCore/Models/HistoryEntry.swift`
- Create: `native/Sources/PrismCore/Models/AppSettings.swift`
- Create: `native/Tests/PrismCoreTests/TestFixtures.swift`
- Test: `native/Tests/PrismCoreTests/ModelRoundTripTests.swift`

**Interfaces:**
- Consumes: No native code; this is the foundation.
- Produces: `BrowserID`, `BrowserDescriptor`, `SourceApplication`, `SourceConfidence`, `RuleMatcher`, `RoutingRule`, `LinkRequest`, `PendingRequestSnapshot`, `TerminalRequestRecord`, `HistoryEntry`, `RoutingMethod`, `HistoryResult`, `UnmatchedBehavior`, and `AppSettings`.

- [ ] **Step 1: Write the model round-trip test**

```swift
import Foundation
import Testing
@testable import PrismCore

@Test func routingRuleRoundTripsWithoutLosingPriority() throws {
    let rule = RoutingRule(
        id: UUID(uuidString: "2A50BE99-7BA5-4F41-9B8C-1849D704B631")!,
        isEnabled: true,
        matcher: .hostAndSubdomains("company.com"),
        targetBrowserID: BrowserID("com.apple.Safari"),
        priority: 3,
        label: "Company links",
        createdAt: Date(timeIntervalSince1970: 1),
        updatedAt: Date(timeIntervalSince1970: 2)
    )

    let data = try JSONEncoder().encode(rule)
    let decoded = try JSONDecoder().decode(RoutingRule.self, from: data)

    #expect(decoded == rule)
    #expect(decoded.priority == 3)
}
```

- [ ] **Step 2: Run the test and verify the expected failure**

Run: `cd native && swift test --filter routingRuleRoundTripsWithoutLosingPriority`

Expected: FAIL because `PrismCore` and `RoutingRule` do not exist.

- [ ] **Step 3: Create the package manifest**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PrismNative",
    platforms: [.macOS(.v15)],
    products: [.library(name: "PrismCore", targets: ["PrismCore"])],
    targets: [
        .target(name: "PrismCore"),
        .testTarget(name: "PrismCoreTests", dependencies: ["PrismCore"])
    ]
)
```

- [ ] **Step 4: Implement the exact shared model surface**

```swift
public struct BrowserID: RawRepresentable, Codable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }
}

public enum SourceConfidence: String, Codable, Sendable { case confirmed, low, unknown }

public struct SourceApplication: Codable, Equatable, Sendable {
    public let bundleIdentifier: String?
    public let displayName: String
    public let confidence: SourceConfidence

    public static let unknown = SourceApplication(
        bundleIdentifier: nil,
        displayName: "Unknown",
        confidence: .unknown
    )
}

public enum RuleMatcher: Codable, Equatable, Sendable {
    case exactHost(String)
    case hostAndSubdomains(String)
    case urlContains(String)
    case sourceBundleIdentifier(String)
}

public enum BrowserOrigin: String, Codable, Sendable { case system, custom }
public enum BrowserAvailability: String, Codable, Sendable { case available, unavailable }

public struct BrowserDescriptor: Codable, Equatable, Sendable {
    public let id: BrowserID
    public let bundleIdentifier: String
    public let displayName: String
    public let applicationURL: URL
    public let securityScopedBookmark: Data?
    public let origin: BrowserOrigin
    public let availability: BrowserAvailability
    public let selectorOrder: Int
}

public enum RuleValidationState: String, Codable, Sendable {
    case valid, targetUnavailable, sourceIneligible
}

public struct RoutingRule: Codable, Equatable, Sendable {
    public let id: UUID
    public var isEnabled: Bool
    public var matcher: RuleMatcher
    public var targetBrowserID: BrowserID
    public var priority: Int
    public var label: String?
    public var validationState: RuleValidationState
    public let createdAt: Date
    public var updatedAt: Date
}

public enum LinkRequestState: String, Codable, Sendable {
    case queued, presenting, launching, outcomeUnknown
}

public struct LinkRequest: Codable, Equatable, Sendable {
    public let id: UUID
    public let url: URL
    public let receivedAt: Date
    public let source: SourceApplication
    public var state: LinkRequestState
    public var attemptCount: Int
    public var lastAttemptedBrowserID: BrowserID?
    public var reopenedFromHistoryEntryID: UUID?
}

public enum TerminalRequestOutcome: String, Codable, Sendable { case succeeded, cancelled }

public struct TerminalRequestRecord: Codable, Equatable, Sendable {
    public let requestID: UUID
    public let outcome: TerminalRequestOutcome
    public let historyEntry: HistoryEntry?
    public let completedAt: Date
}

public struct PendingRequestSnapshot: Codable, Equatable, Sendable {
    public var pendingRequests: [LinkRequest]
    public var terminalRecords: [TerminalRequestRecord]
}

public enum UnmatchedBehavior: String, Codable, Sendable {
    case alwaysAsk, preferredBrowser, lastUsedBrowser
}

public enum RoutingMethod: String, Codable, Sendable {
    case urlRule, sourceRule, manual, preferredBrowser, lastUsedBrowser
}

public enum HistoryResult: String, Codable, Sendable {
    case processing, success, failure, cancelled
}

public struct HistoryEntry: Codable, Equatable, Sendable {
    public let id: UUID
    public let requestID: UUID
    public var sanitizedURL: URL?
    public let sourceBundleIdentifier: String?
    public let sourceDisplayName: String
    public var targetBrowserID: BrowserID?
    public var targetDisplayName: String?
    public var method: RoutingMethod?
    public var result: HistoryResult
    public var matchingRuleID: UUID?
    public var failureReason: String?
    public var attemptCount: Int
    public let createdAt: Date
    public var completedAt: Date?

    public static func processing(request: LinkRequest, sanitizedURL: URL?) -> HistoryEntry
}

public enum AppLanguage: String, Codable, Sendable { case system, english, simplifiedChinese }

public struct AppSettings: Codable, Equatable, Sendable {
    public var language: AppLanguage
    public var unmatchedBehavior: UnmatchedBehavior
    public var preferredBrowserID: BrowserID?
    public var lastUsedBrowserID: BrowserID?
    public var historyEnabled: Bool
    public var historyLimit: Int
    public var historyRetentionDays: Int
    public var automaticRulesEnabled: Bool
    public var showMenuBarItem: Bool
    public var onboardingCompleted: Bool
    public var schemaVersion: Int

    public static let defaults = AppSettings(
        language: .system,
        unmatchedBehavior: .alwaysAsk,
        preferredBrowserID: nil,
        lastUsedBrowserID: nil,
        historyEnabled: true,
        historyLimit: 100,
        historyRetentionDays: 30,
        automaticRulesEnabled: true,
        showMenuBarItem: true,
        onboardingCompleted: false,
        schemaVersion: 1
    )
}
```

Implement all listed models as `Codable`, `Equatable`, and `Sendable`. Give every public struct an explicit public memberwise initializer. `RoutingRule.init` defaults `validationState` to `.valid`; `LinkRequest.init` defaults `state` to `.queued`, `attemptCount` to `0`, `lastAttemptedBrowserID` to `nil`, and `reopenedFromHistoryEntryID` to `nil`. `HistoryEntry.processing(request:sanitizedURL:)` copies the request source bundle ID and display name so History remains stable after an app disappears. A terminal record contains no complete URL. Use `Date` and `UUID`; do not store AppKit types, SwiftData models, or image data in PrismCore.

Create deterministic test fixtures with these signatures so later tasks do not invent parallel model builders:

```swift
extension LinkRequest {
    static func fixture(
        id: UUID = UUID(uuidString: "A4C3CB34-05C4-4B06-83EB-D18CE0260F63")!,
        url: String = "https://example.com",
        sourceBundleID: String? = nil,
        confidence: SourceConfidence = .unknown
    ) -> LinkRequest
}

extension RoutingRule {
    static func fixture(
        id: UUID = UUID(uuidString: "9EA80967-70C1-4BCE-BC6C-C79754C168F2")!,
        matcher: RuleMatcher,
        browser: BrowserID,
        priority: Int
    ) -> RoutingRule
}

extension HistoryEntry {
    static func fixture(
        requestID: UUID = .test(1),
        result: HistoryResult = .cancelled,
        sanitizedURL: String? = "https://example.com"
    ) -> HistoryEntry

    static var cancelledFixture: HistoryEntry {
        fixture(result: .cancelled)
    }
}

extension UUID {
    static func test(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }
}
```

- [ ] **Step 5: Run model tests and the full package suite**

Run: `cd native && swift test --filter routingRuleRoundTripsWithoutLosingPriority && swift test`

Expected: PASS with zero failures.

- [ ] **Step 6: Commit the package foundation**

```bash
git add native/Package.swift native/Sources/PrismCore/Models native/Tests/PrismCoreTests/TestFixtures.swift native/Tests/PrismCoreTests/ModelRoundTripTests.swift
git commit -m "feat(native): add Prism core models"
```

### Task 2: Implement Deterministic Rule Evaluation

**Files:**
- Create: `native/Sources/PrismCore/Routing/RuleEngine.swift`
- Test: `native/Tests/PrismCoreTests/RuleEngineTests.swift`

**Interfaces:**
- Consumes: `RoutingRule`, `LinkRequest`, `BrowserID`, `AppSettings` from Task 1.
- Produces: `SelectorReason`, `RoutingDecision`, and `RuleEngine.decide(request:rules:availableBrowserIDs:eligibleSourceBundleIDs:settings:)`.

- [ ] **Step 1: Write failing priority and host-boundary tests**

```swift
@Test func URLRulePrecedesSourceRule() {
    let request = LinkRequest.fixture(
        url: "https://github.com/eager/prism",
        sourceBundleID: "com.tinyspeck.slackmacgap",
        confidence: .confirmed
    )
    let source = RoutingRule.fixture(
        matcher: .sourceBundleIdentifier("com.tinyspeck.slackmacgap"),
        browser: "com.apple.Safari",
        priority: 0
    )
    let url = RoutingRule.fixture(
        matcher: .exactHost("github.com"),
        browser: "com.google.Chrome",
        priority: 99
    )

    let decision = RuleEngine().decide(
        request: request,
        rules: [source, url],
        availableBrowserIDs: ["com.apple.Safari", "com.google.Chrome"],
        eligibleSourceBundleIDs: ["com.tinyspeck.slackmacgap"],
        settings: .defaults
    )

    #expect(decision == .open(browserID: "com.google.Chrome", method: .urlRule, ruleID: url.id))
}

@Test(arguments: ["notgithub.com", "github.com.evil.test"])
func exactHostRejectsLookalikes(_ host: String) {
    #expect(URLRuleMatcher.matches(.exactHost("github.com"), url: URL(string: "https://\(host)/")!) == false)
}

@Test func pausedRulesAlwaysAskEvenWhenPreferredBrowserExists() {
    var settings = AppSettings.defaults
    settings.automaticRulesEnabled = false
    settings.unmatchedBehavior = .preferredBrowser
    settings.preferredBrowserID = "com.apple.Safari"

    let decision = RuleEngine().decide(
        request: .fixture(),
        rules: [],
        availableBrowserIDs: ["com.apple.Safari"],
        eligibleSourceBundleIDs: [],
        settings: settings
    )

    #expect(decision == .ask(reason: .rulesPaused))
}
```

- [ ] **Step 2: Run and verify failure**

Run: `cd native && swift test --filter URLRulePrecedesSourceRule`

Expected: FAIL because `RuleEngine`, `RoutingDecision`, and `URLRuleMatcher` do not exist.

- [ ] **Step 3: Implement match normalization and decision types**

```swift
public enum SelectorReason: Equatable, Sendable {
    case noMatchingRule
    case rulesPaused
    case targetUnavailable(BrowserID)
    case preferredBrowserUnavailable(BrowserID?)
}

public enum RoutingDecision: Equatable, Sendable {
    case open(browserID: BrowserID, method: RoutingMethod, ruleID: UUID?)
    case ask(reason: SelectorReason)
}

public struct RuleEngine: Sendable {
    public func decide(
        request: LinkRequest,
        rules: [RoutingRule],
        availableBrowserIDs: Set<BrowserID>,
        eligibleSourceBundleIDs: Set<String>,
        settings: AppSettings
    ) -> RoutingDecision
}
```

Normalize hosts with `URL.host?.lowercased()` and trim a trailing dot. `hostAndSubdomains("company.com")` matches only `company.com` or hosts ending in `.company.com`. `urlContains` compares normalized absolute strings case-insensitively. Source match requires `.confirmed`, a non-empty bundle identifier present in `eligibleSourceBundleIDs`, and rule validation state `.valid`. Eligibility is checked on every decision, so removing an app from the signed support manifest immediately disables existing source rules.

- [ ] **Step 4: Implement fixed rule precedence and unmatched behavior**

Sort enabled URL rules by `priority`, then enabled source rules by `priority`. If the selected target is unavailable, return `.ask(.targetUnavailable(id))`. For unmatched requests, map settings as follows:

```swift
switch settings.unmatchedBehavior {
case .alwaysAsk:
    return .ask(reason: .noMatchingRule)
case .preferredBrowser:
    return available(settings.preferredBrowserID, method: .preferredBrowser)
case .lastUsedBrowser:
    return available(settings.lastUsedBrowserID, method: .lastUsedBrowser)
}
```

If `settings.automaticRulesEnabled` is `false`, return `.ask(.rulesPaused)` before evaluating any rule or unmatched automatic browser. Pausing rules therefore keeps link intake active and always shows the selector.

- [ ] **Step 5: Run focused and full tests**

Run: `cd native && swift test --filter URLRulePrecedesSourceRule && swift test`

Expected: PASS; exact-host and source-confidence cases remain green.

- [ ] **Step 6: Commit rule evaluation**

```bash
git add native/Sources/PrismCore/Routing native/Tests/PrismCoreTests/RuleEngineTests.swift
git commit -m "feat(native): add deterministic rule engine"
```

### Task 3: Implement the FIFO Recovery Queue and Crash-Safe Terminal Journal

**Files:**
- Create: `native/Sources/PrismCore/Queue/PendingRequestStore.swift`
- Create: `native/Sources/PrismCore/Queue/LinkRequestQueue.swift`
- Test: `native/Tests/PrismCoreTests/LinkRequestQueueTests.swift`

**Interfaces:**
- Consumes: `LinkRequest` from Task 1.
- Produces: `PendingRequestStore`, `LinkRequestQueue.enqueue(_:)`, `next()`, `markLaunching`, `markCompleted`, `markCancelled`, `markOutcomeUnknown`, `compactTerminal`, and `restore()`.

- [ ] **Step 1: Write failing FIFO and duplicate-ID tests**

```swift
@Test func queuePreservesOrderAndRejectsDuplicateID() async throws {
    let store = InMemoryPendingRequestStore()
    let queue = LinkRequestQueue(store: store)
    let first = LinkRequest.fixture(id: .test(1), url: "https://one.example")
    let second = LinkRequest.fixture(id: .test(2), url: "https://two.example")

    #expect(try await queue.enqueue(first))
    #expect(try await queue.enqueue(second))
    #expect(try await queue.enqueue(first) == false)
    #expect(await queue.next()?.id == first.id)

    try await queue.markCompleted(first.id, historyEntry: nil)
    #expect(await queue.next()?.id == second.id)
}

@Test func restoreNeverAutomaticallyReplaysAnInterruptedLaunch() async throws {
    var interrupted = LinkRequest.fixture(id: .test(3))
    interrupted.state = .launching
    let store = InMemoryPendingRequestStore(seed: [interrupted])
    let queue = LinkRequestQueue(store: store)

    try await queue.restore()

    #expect(await queue.next()?.state == .outcomeUnknown)
    #expect(await queue.next()?.id == interrupted.id)
}
```

- [ ] **Step 2: Run and verify failure**

Run: `cd native && swift test --filter queuePreservesOrderAndRejectsDuplicateID`

Expected: FAIL because the queue and store protocol do not exist.

- [ ] **Step 3: Define the persistence boundary**

```swift
public protocol PendingRequestStore: Sendable {
    func load() async throws -> PendingRequestSnapshot
    func save(_ snapshot: PendingRequestSnapshot) async throws
}

public actor LinkRequestQueue {
    public init(store: any PendingRequestStore)
    public func restore() async throws
    @discardableResult public func enqueue(_ request: LinkRequest) async throws -> Bool
    public func next() -> LinkRequest?
    public func snapshot() -> [LinkRequest]
    public func terminalSnapshot() -> [TerminalRequestRecord]
    public func markPresenting(_ id: UUID) async throws
    public func markLaunching(_ id: UUID, browserID: BrowserID) async throws
    public func markOutcomeUnknown(_ id: UUID) async throws
    public func markCompleted(_ id: UUID, historyEntry: HistoryEntry?) async throws
    public func markCancelled(_ id: UUID, historyEntry: HistoryEntry?) async throws
    public func compactTerminal(_ id: UUID) async throws
}
```

Define `InMemoryPendingRequestStore` in `LinkRequestQueueTests.swift` as an actor conforming to `PendingRequestStore`, with `init(seed: [LinkRequest] = [], terminal: [TerminalRequestRecord] = [])`, `load`, and `save`. It keeps the most recent snapshot so tests can assert persistence without adding test-only behavior to PrismCore.

- [ ] **Step 4: Implement persistence-after-mutation**

Maintain ordered pending requests, terminal records, and a `Set<UUID>`. Persist every transition before acknowledging it. `next()` returns the first pending `.queued`, `.presenting`, or `.outcomeUnknown` request. `markCompleted` and `markCancelled` atomically remove the active `LinkRequest` containing the complete URL and append a URL-free terminal record with the optional sanitized History entry, so a later History write failure cannot cause automatic replay or retain the full URL. `compactTerminal` removes a terminal record only after History reconciliation succeeds or History is disabled. If any save fails, restore the prior in-memory state and throw.

- [ ] **Step 5: Add restart restoration coverage**

```swift
@Test func restoreContinuesWithFirstUnfinishedRequest() async throws {
    let pending = [LinkRequest.fixture(id: .test(7)), LinkRequest.fixture(id: .test(8))]
    let store = InMemoryPendingRequestStore(seed: pending)
    let queue = LinkRequestQueue(store: store)

    try await queue.restore()

    #expect(await queue.snapshot().map(\.id) == pending.map(\.id))
    #expect(await queue.next()?.id == pending[0].id)
}

@Test func terminalJournalDoesNotBlockNextAndSurvivesUntilCompacted() async throws {
    let first = LinkRequest.fixture(id: .test(10))
    let second = LinkRequest.fixture(id: .test(11))
    let store = InMemoryPendingRequestStore(seed: [first, second])
    let queue = LinkRequestQueue(store: store)
    try await queue.restore()

    try await queue.markCompleted(first.id, historyEntry: .fixture(requestID: first.id, result: .success))

    #expect(await queue.next()?.id == second.id)
    #expect(await queue.terminalSnapshot().first?.outcome == .succeeded)
    #expect(await queue.terminalSnapshot().first?.historyEntry?.sanitizedURL != nil)
}
```

During `restore()`, convert every `.launching` record to `.outcomeUnknown` and persist that conversion before returning. Never convert it back to `.queued`. A terminal journal remains unavailable to routing but remains loadable for the Task 6 reconciler.

- [ ] **Step 6: Run all queue and package tests**

Run: `cd native && swift test --filter queuePreservesOrderAndRejectsDuplicateID && swift test`

Expected: PASS with no order, duplication, or restoration failures.

- [ ] **Step 7: Commit the queue**

```bash
git add native/Sources/PrismCore/Queue native/Tests/PrismCoreTests/LinkRequestQueueTests.swift
git commit -m "feat(native): add crash-safe link recovery queue"
```

### Task 4: Implement URL Privacy and One-Entry History Transitions

**Files:**
- Create: `native/Sources/PrismCore/Privacy/URLSanitizer.swift`
- Create: `native/Sources/PrismCore/History/HistoryStateMachine.swift`
- Test: `native/Tests/PrismCoreTests/URLSanitizerTests.swift`
- Test: `native/Tests/PrismCoreTests/HistoryStateMachineTests.swift`

**Interfaces:**
- Consumes: `HistoryEntry`, `HistoryResult`, `RoutingMethod`, and `BrowserID`.
- Produces: `URLSanitizer.sanitize(_:)`, `HistoryEvent`, and `HistoryStateMachine.apply(_:to:)`.

- [ ] **Step 1: Write failing sanitizer tests**

```swift
@Test func sanitizerRemovesFragmentAndSensitiveParameters() throws {
    let input = URL(string: "https://example.com/doc?id=42&token=secret&utm_source=mail#section")!
    let output = try #require(URLSanitizer.default.sanitize(input))

    #expect(output.absoluteString == "https://example.com/doc?id=42")
}
```

The default sensitive set is case-insensitive and contains `token`, `access_token`, `auth`, `authorization`, `code`, `state`, `session`, `session_id`, `signature`, every `utm_*` name, `gclid`, and `fbclid`.

- [ ] **Step 2: Write the failing one-entry retry test**

```swift
@Test func retryUpdatesTheExistingHistoryEntry() throws {
    let request = LinkRequest.fixture(id: .test(9), sourceBundleID: "com.example.Source", confidence: .confirmed)
    var entry = HistoryEntry.processing(request: request, sanitizedURL: URL(string: "https://example.com")!)
    let originalID = entry.id
    let machine = HistoryStateMachine()

    try machine.apply(.launchStarted(browserID: "com.apple.Safari", browserName: "Safari", method: .manual, ruleID: nil), to: &entry)
    try machine.apply(.launchFailed(browserID: "com.apple.Safari", message: "not found"), to: &entry)
    try machine.apply(.launchStarted(browserID: "com.google.Chrome", browserName: "Google Chrome", method: .manual, ruleID: nil), to: &entry)
    try machine.apply(.launchSucceeded(browserID: "com.google.Chrome", method: .manual), to: &entry)

    #expect(entry.result == .success)
    #expect(entry.attemptCount == 2)
    #expect(entry.targetBrowserID == "com.google.Chrome")
    #expect(entry.targetDisplayName == "Google Chrome")
    #expect(entry.sourceBundleIdentifier == "com.example.Source")
    #expect(entry.id == originalID)
}
```

- [ ] **Step 3: Run and verify both failures**

Run: `cd native && swift test --filter sanitizerRemovesFragmentAndSensitiveParameters && swift test --filter retryUpdatesTheExistingHistoryEntry`

Expected: FAIL because both production types are missing.

- [ ] **Step 4: Implement sanitizer and legal history transitions**

```swift
public enum HistoryEvent: Equatable, Sendable {
    case launchStarted(browserID: BrowserID, browserName: String, method: RoutingMethod, ruleID: UUID?)
    case launchFailed(browserID: BrowserID, message: String)
    case launchSucceeded(browserID: BrowserID, method: RoutingMethod)
    case cancelled
}

public struct HistoryStateMachine: Sendable {
    public func apply(_ event: HistoryEvent, to entry: inout HistoryEntry) throws
}
```

Reject transitions after success or cancellation. Increment attempt count only on `launchStarted`. A failed attempt preserves the request ID and sanitized URL. A later success changes the same entry to success.

- [ ] **Step 5: Run focused and full package tests**

Run: `cd native && swift test --filter sanitizerRemovesFragmentAndSensitiveParameters && swift test --filter retryUpdatesTheExistingHistoryEntry && swift test`

Expected: PASS.

- [ ] **Step 6: Commit privacy and history behavior**

```bash
git add native/Sources/PrismCore/Privacy native/Sources/PrismCore/History native/Tests/PrismCoreTests
git commit -m "feat(native): add private recoverable history"
```

---

## Phase B — Native Application and macOS Services

### Task 5: Generate the Reproducible macOS Application Project

**Files:**
- Create: `native/project.yml`
- Create: `native/scripts/generate-project.sh`
- Modify: `.gitignore`
- Create: `native/PrismNative/App/PrismNativeApp.swift`
- Create: `native/PrismNative/App/AppEnvironment.swift`
- Create: `native/PrismNative/App/AppRoute.swift`
- Create: `native/PrismNative/Updates/UpdateChecking.swift`
- Create: `native/PrismNative/Updates/DisabledUpdateChecker.swift`
- Create: `native/PrismNative/Resources/Info.plist`
- Create: `native/PrismNative/Resources/PrismNative.entitlements`
- Create: `native/PrismNative/Resources/Assets.xcassets/Contents.json`
- Create: `native/PrismNative/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`
- Create: `native/scripts/generate-app-icon.sh`
- Create: `native/PrismNativeTests/AppSmokeTests.swift`
- Create: `native/PrismNativeTests/TestFixtures.swift`
- Create: `native/PrismNativeUITests/AppLaunchUITests.swift`
- Generate but do not commit: `native/PrismNative.xcodeproj`

**Interfaces:**
- Consumes: local package product `PrismCore`.
- Produces: `PrismNative` application target, `PrismNativeTests`, `PrismNativeUITests`, `AppEnvironment`, and an Xcode-buildable native shell.

- [ ] **Step 1: Verify the mandatory environment before touching the app target**

Run:

```bash
test "$(xcode-select -p)" = "/Applications/Xcode.app/Contents/Developer"
xcodebuild -checkFirstLaunchStatus
xcodebuild -version
xcodegen --version
```

Expected: full Xcode is selected and XcodeGen reports `Version: 2.46.0`. If selection, license acceptance, or XcodeGen fails, stop this phase and continue only Phase A work until the prerequisite is corrected.

- [ ] **Step 2: Write the smoke test before the application composition**

```swift
import Testing
@testable import PrismNative

@Test @MainActor func environmentStartsOnHistoryRoute() {
    let environment = AppEnvironment.preview
    #expect(environment.route == .history)
    #expect(environment.unmatchedBehavior == .alwaysAsk)
}
```

- [ ] **Step 3: Create the pinned project specification**

```yaml
name: PrismNative
options:
  minimumXcodeGenVersion: 2.46.0
  deploymentTarget:
    macOS: "15.0"
packages:
  PrismCore:
    path: .
targets:
  PrismNative:
    type: application
    platform: macOS
    sources: [PrismNative]
    dependencies:
      - package: PrismCore
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.prism.app
        PRODUCT_NAME: Prism
        MACOSX_DEPLOYMENT_TARGET: 15.0
        SWIFT_VERSION: 6.0
        ENABLE_HARDENED_RUNTIME: YES
    info:
      path: PrismNative/Resources/Info.plist
    entitlements:
      path: PrismNative/Resources/PrismNative.entitlements
  PrismNativeTests:
    type: bundle.unit-test
    platform: macOS
    sources: [PrismNativeTests]
    dependencies:
      - target: PrismNative
  PrismNativeUITests:
    type: bundle.ui-testing
    platform: macOS
    sources: [PrismNativeUITests]
    dependencies:
      - target: PrismNative
schemes:
  PrismNative-Unit:
    build:
      targets:
        PrismNative: all
        PrismNativeTests: [test]
    test:
      targets: [PrismNativeTests]
  PrismNative-UI:
    build:
      targets:
        PrismNative: all
        PrismNativeUITests: [test]
    test:
      targets: [PrismNativeUITests]
  PrismNative-Release:
    build:
      targets:
        PrismNative: all
    archive:
      config: Release
```

- [ ] **Step 4: Declare HTTP and HTTPS handlers in Info.plist**

Add `CFBundleURLTypes` entries for `http` and `https`, `CFBundleName` as `Prism`, `LSMinimumSystemVersion` as `15.0`, `NSPrincipalClass` as `NSApplication`, `CFBundleShortVersionString` as `$(MARKETING_VERSION)`, `CFBundleVersion` as `$(CURRENT_PROJECT_VERSION)`, and `SUFeedURL` as `https://github.com/Halewwang/Prism-Browser-switching/releases/latest/download/appcast.xml`. Do not add Accessibility or Apple Events control usage descriptions because Prism reads its incoming event and does not control other applications.

- [ ] **Step 5: Create the generation script and application shell**

```bash
#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
test "$(xcodegen --version | awk '{print $2}')" = "2.46.0"
xcodegen generate --spec project.yml
```

`PrismNativeApp` creates `WindowGroup(id: "main", for: MainWindowIdentity.self)` whose `defaultValue` closure returns `MainWindowIdentity.singleton`, injects one minimal `AppEnvironment`, and renders a localized `Text("Prism")` shell at a minimum 760 × 520 content size. `MainWindowIdentity` is a `Codable`, `Hashable` enum declared in `AppRoute.swift`. Both the initial window and every later caller therefore use the same fixed value; later callers must use `openWindow(id: "main", value: MainWindowIdentity.singleton)`, which raises the existing value-identified window instead of creating another. Replace the macOS New Window command with an empty command group so users cannot create a second main window. Task 6 adds repositories and Task 12 replaces that shell with `AppShellView`. `AppEnvironment.preview` contains `.history`, `.alwaysAsk`, and `DisabledUpdateChecker`; it does not reference repositories that do not exist yet. `UpdateChecking` exposes a no-network `checkForUpdates()` boundary used by Tasks 12 and 16; Task 17 replaces only its driver with Sparkle. `AppLaunchUITests` launches the app and asserts that the Prism label exists. `PrismNativeTests/TestFixtures.swift` duplicates the small public fixture builders needed by application tests and defines a test-target-local `InMemoryPendingRequestStore` actor conforming to `PendingRequestStore`; it does not depend on the separate `PrismCoreTests` target.

```swift
enum UpdateFailure: Equatable, Sendable {
    case unavailableInThisBuild
    case configuration
    case network
    case signatureVerification
    case installation
    case system(String)
}

enum UpdateEvent: Equatable, Sendable {
    case checking
    case current
    case available(version: String)
    case downloading(progress: Double?)
    case extracting(progress: Double?)
    case readyToInstall
    case installed(relaunched: Bool)
    case cancelled
    case failed(UpdateFailure)
}

@MainActor protocol UpdateChecking: AnyObject {
    var events: AsyncStream<UpdateEvent> { get }
    var canCheckForUpdates: Bool { get }
    var automaticallyChecksForUpdates: Bool { get set }
    func checkForUpdates()
}
```

`DisabledUpdateChecker` yields `.failed(.unavailableInThisBuild)` when checked. Application settings do not duplicate Sparkle's own automatic-check preference once Task 17 is active; the eventual Sparkle driver remains the source of truth.

`generate-app-icon.sh` reads the existing approved 1024 × 1024 `build/icon.png`, writes the ten macOS icon renditions from 16 points through 512 points at 1×/2×, and creates the matching `AppIcon.appiconset/Contents.json`. It fails if the source is absent or not exactly 1024 × 1024; it does not redesign the icon.

- [ ] **Step 6: Generate, run the test, and build without signing**

Run:

```bash
cd native
zsh scripts/generate-app-icon.sh
zsh scripts/generate-project.sh
xcodebuild -project PrismNative.xcodeproj -scheme PrismNative-Unit -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO test
zsh scripts/generate-project.sh
xcodebuild -project PrismNative.xcodeproj -scheme PrismNative-UI -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- test
zsh scripts/generate-project.sh
xcodebuild -project PrismNative.xcodeproj -scheme PrismNative-Unit -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

Expected: smoke test and build PASS.

- [ ] **Step 7: Commit the reproducible app shell**

```bash
git add native/project.yml native/scripts/generate-project.sh native/scripts/generate-app-icon.sh native/PrismNative native/PrismNativeTests native/PrismNativeUITests/AppLaunchUITests.swift .gitignore
git commit -m "feat(native): scaffold macOS application"
```

### Task 6: Add SwiftData Persistence and Safe-Mode Recovery

**Files:**
- Create: `native/PrismNative/Persistence/RuleRecord.swift`
- Create: `native/PrismNative/Persistence/HistoryRecord.swift`
- Create: `native/PrismNative/Persistence/CustomBrowserRecord.swift`
- Create: `native/PrismNative/Persistence/SettingsRecord.swift`
- Create: `native/PrismNative/Persistence/SwiftDataRepositories.swift`
- Create: `native/PrismNative/Persistence/AtomicPendingRequestStore.swift`
- Create: `native/PrismNative/Persistence/PersistenceWarning.swift`
- Create: `native/PrismNative/Persistence/ModelContainerFactory.swift`
- Test: `native/PrismNativeTests/PersistenceTests.swift`

**Interfaces:**
- Consumes: PrismCore models and `PendingRequestStore`.
- Produces: `RuleRepository`, `HistoryRepository`, `BrowserPreferenceRepository`, `SettingsRepository`, `AtomicPendingRequestStore`, `PersistenceWarning`, and `ModelContainerFactory.make(inMemory:)`.

- [ ] **Step 1: Write a failing in-memory repository test**

```swift
@Test @MainActor func pendingStoreRestoresCompleteURLUntilCompletion() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let store = AtomicPendingRequestStore(directory: directory)
    let request = LinkRequest.fixture(url: "https://example.com/private?token=kept-until-complete")

    try await store.save(PendingRequestSnapshot(pendingRequests: [request], terminalRecords: []))
    let restored = try await store.load()

    #expect(restored.pendingRequests == [request])
    #expect(restored.terminalRecords.isEmpty)
}
```

- [ ] **Step 2: Run and verify failure**

Run: `cd native && zsh scripts/generate-project.sh && xcodebuild -project PrismNative.xcodeproj -scheme PrismNative-Unit -destination 'platform=macOS' -only-testing:PrismNativeTests CODE_SIGNING_ALLOWED=NO test`

Expected: FAIL because persistence records and repositories do not exist.

- [ ] **Step 3: Implement versioned SwiftData records**

Each `@Model` record stores primitive SwiftData-compatible fields. Encode enum payloads such as `RuleMatcher` as versioned `Data` using `JSONEncoder`. Set schema version `1` in `SettingsRecord`. Never store `NSImage`, `Image`, Base64 data, or complete recovery URLs in SwiftData.

`AtomicPendingRequestStore` keeps the recovery queue and terminal journal in `Application Support/Prism/Recovery/pending-requests-v1.json`. Save by encoding into a sibling temporary file, calling `FileHandle.synchronize()`, then atomically replacing the destination. On corrupt JSON, move it to a `CorruptRecoveryBackup/YYYYMMDD-HHmmss/` folder, return an explicit data-loss notice, and create an empty file; never silently delete it. Tests inject a temporary directory.

- [ ] **Step 4: Implement repository contracts and retention**

```swift
@MainActor protocol HistoryRepository {
    func upsert(_ entry: HistoryEntry) throws
    func recent(limit: Int, newerThan: Date) throws -> [HistoryEntry]
    func delete(id: UUID) throws
    func clear() throws
    func enforceRetention(limit: Int, cutoff: Date) throws
}
```

Use 100 entries and 30 days as defaults. `RuleRepository` sorts by rule type and priority. `BrowserPreferenceRepository` stores order and custom security-scoped bookmarks, not scan results.

Define the shared warning values before any coordinator consumes them:

```swift
enum PersistenceWarning: Equatable, Sendable {
    case historyNotSaved
    case recoveryStoreUnavailable
    case settingsNotSaved
    case corruptStoreRecovered(backupLocation: String)
}
```

Warnings describe local persistence truth only; none of them can claim a link handoff succeeded or failed.

- [ ] **Step 5: Implement safe-mode container recovery**

`ModelContainerFactory` first opens `PrismNative.store`. On failure, move the store and its `-shm` and `-wal` companions into a timestamped `CorruptDataBackup` directory, create a new store, set `automaticRulesEnabled` to false, set unmatched behavior to Always Ask, and return a visible recovery notice. Never delete the backup automatically.

After repositories exist, extend `AppEnvironment` to receive protocol-typed repositories and use in-memory implementations in `preview`. At startup reconcile terminal queue journal entries into History: best-effort upsert their embedded sanitized entry, compact the terminal record only after the upsert succeeds or History is disabled, and show a persistent “Link completed, but History is waiting to be saved” warning on failure. This reconciliation never routes or reopens a terminal request.

- [ ] **Step 6: Run focused tests and full native tests**

Run:

```bash
cd native
zsh scripts/generate-project.sh
xcodebuild -project PrismNative.xcodeproj -scheme PrismNative-Unit -destination 'platform=macOS' -only-testing:PrismNativeTests CODE_SIGNING_ALLOWED=NO test
zsh scripts/generate-project.sh
xcodebuild -project PrismNative.xcodeproj -scheme PrismNative-Unit -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
```

Expected: PASS.

- [ ] **Step 7: Commit persistence**

```bash
git add native/PrismNative/Persistence native/PrismNativeTests/PersistenceTests.swift
git commit -m "feat(native): add SwiftData persistence"
```

### Task 7: Implement Browser Discovery and Confirmed Launch Results

**Files:**
- Create: `native/PrismNative/System/WorkspaceClient.swift`
- Create: `native/PrismNative/System/BrowserCatalogService.swift`
- Create: `native/PrismNative/System/BrowserLauncherService.swift`
- Create: `native/PrismNative/System/ApplicationIconProvider.swift`
- Test: `native/PrismNativeTests/BrowserServicesTests.swift`

**Interfaces:**
- Consumes: `BrowserDescriptor`, browser preference repository.
- Produces: `BrowserCataloging.scan() async throws -> [BrowserDescriptor]`, `BrowserLaunching.open(_:with:) async throws`, and native icon lookup by application URL.

- [ ] **Step 1: Write failing discovery normalization tests**

```swift
@Test @MainActor func catalogDeduplicatesHandlersByBundleIdentifier() async throws {
    let fixtures = try TemporaryApplicationBundles([
        ("Safari.app", "com.apple.Safari"),
        ("Safari Copy.app", "com.apple.Safari"),
        ("Google Chrome.app", "com.google.Chrome")
    ])
    defer { fixtures.remove() }
    let safariURL = fixtures.urls[0]
    let safariCopyURL = fixtures.urls[1]
    let chromeURL = fixtures.urls[2]
    let workspace = StubWorkspaceClient(applicationURLs: [safariURL, safariCopyURL, chromeURL])
    let catalog = BrowserCatalogService(workspace: workspace, customBrowsers: .empty)

    let browsers = try await catalog.scan()

    #expect(browsers.map(\.id) == ["com.apple.Safari", "com.google.Chrome"])
}
```

- [ ] **Step 2: Run and verify failure**

Run: `cd native && zsh scripts/generate-project.sh && xcodebuild -project PrismNative.xcodeproj -scheme PrismNative-Unit -destination 'platform=macOS' -only-testing:PrismNativeTests CODE_SIGNING_ALLOWED=NO test`

Expected: FAIL because browser service types do not exist.

- [ ] **Step 3: Define the narrow workspace wrapper**

```swift
@MainActor protocol WorkspaceClient {
    func applicationURLs(toOpen url: URL) -> [URL]
    func open(_ url: URL, with applicationURL: URL) async throws
    func icon(for applicationURL: URL) -> NSImage
}
```

The production implementation delegates to `NSWorkspace.shared.urlsForApplications(toOpen:)`, `open(_:withApplicationAt:configuration:)`, and `icon(forFile:)`.

`TemporaryApplicationBundles` and `StubWorkspaceClient` live in `BrowserServicesTests.swift`. The helper creates `.app/Contents/Info.plist` under a unique temporary directory and removes the root during cleanup. Two paths share Safari's bundle identifier and one uses Chrome's. This exercises the real metadata reader while the stub controls the returned application URLs; no installed application is opened or modified.

- [ ] **Step 4: Implement scan ordering and custom-browser validation**

Take the union of HTTP and HTTPS handlers, resolve symbolic links and standardized URLs, discard Prism itself, require a readable application bundle and a non-empty bundle identifier, deduplicate by bundle ID, merge valid custom applications, and apply saved selector order. Before saving a custom `.app`, require its resolved URL to appear in both `NSWorkspace.shared.urlsForApplications(toOpen: URL(string: "http://example.com")!)` and the corresponding HTTPS result; otherwise reject it with `BrowserCatalogError.cannotOpenWebLinks`. Do not launch the candidate during validation.

- [ ] **Step 5: Implement launch result propagation**

`BrowserLauncherService.open` must return `.handoffSucceeded` only after the `NSWorkspace` completion handler succeeds. This means LaunchServices accepted the handoff; it does not claim that the page finished loading. It throws `BrowserLaunchError.applicationUnavailable`, `.rejected`, or `.system(Error)`; it does not write history or close the selector.

- [ ] **Step 6: Run tests and an opt-in local scan diagnostic**

Run:

```bash
cd native
zsh scripts/generate-project.sh
xcodebuild -project PrismNative.xcodeproj -scheme PrismNative-Unit -destination 'platform=macOS' -only-testing:PrismNativeTests CODE_SIGNING_ALLOWED=NO test
zsh scripts/generate-project.sh
xcodebuild -project PrismNative.xcodeproj -scheme PrismNative-Unit -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

Then run an app-only diagnostic that prints bundle IDs and application URLs without changing defaults or launching a browser. Verify Safari and installed third-party browsers appear once.

- [ ] **Step 7: Commit browser services**

```bash
git add native/PrismNative/System native/PrismNativeTests/BrowserServicesTests.swift
git commit -m "feat(native): add browser discovery and launch"
```

### Task 8: Capture Source Evidence and Enforce the Source-Rule Gate

**Files:**
- Create: `native/PrismNative/System/SourceAttributionProvider.swift`
- Create: `native/PrismNative/System/AppleEventSenderReader.swift`
- Create: `native/PrismNative/System/ApplicationActivationTracker.swift`
- Create: `native/PrismNative/System/SourceSupportManifest.swift`
- Create: `native/PrismNative/Resources/SupportedSources.json`
- Create: `native/docs/source-attribution-matrix.md`
- Test: `native/PrismNativeTests/SourceAttributionTests.swift`

**Interfaces:**
- Consumes: incoming Apple Event, `NSRunningApplication`, current macOS version, and bundled source-support manifest.
- Produces: `SourceAttributing.resolve(senderPID:lastActivated:) -> SourceApplication` and `SourceSupportManifest.eligibleBundleIDs(for:)`.

- [ ] **Step 1: Write failing attribution truth tests**

```swift
@Test @MainActor func unknownPIDNeverFallsBackToAnUnrelatedVisibleApplication() {
    let slack = SourceApplication(bundleIdentifier: "com.tinyspeck.slackmacgap", displayName: "Slack", confidence: .low)
    let resolver = SourceAttributionProvider(runningApplications: StubRunningApplications(empty: true))
    let result = resolver.resolve(senderPID: 999_999, lastActivated: slack)

    #expect(result.displayName == "Unknown")
    #expect(result.bundleIdentifier == nil)
    #expect(result.confidence == .unknown)
}

@Test func freshInstallUsesOnlyBundledApprovedSourcesForCurrentOS() throws {
    let json = Data(#"""
    {"schemaVersion":1,"sources":[{"bundleIdentifier":"com.tinyspeck.slackmacgap","minimumMacOS":"15.0.0","maximumMacOS":"15.9.99","coldSamples":20,"warmSamples":20,"confirmedCount":40,"falseAttributionCount":0,"validatedAt":"2026-08-12T00:00:00Z"}]}
    """#.utf8)
    let manifest = try SourceSupportManifest.decode(json)
    #expect(manifest.eligibleBundleIDs(for: OperatingSystemVersion(majorVersion: 15, minorVersion: 2, patchVersion: 0)) == ["com.tinyspeck.slackmacgap"])
    #expect(manifest.eligibleBundleIDs(for: OperatingSystemVersion(majorVersion: 16, minorVersion: 0, patchVersion: 0)).isEmpty)
}
```

- [ ] **Step 2: Run and verify failure**

Run: `cd native && zsh scripts/generate-project.sh && xcodebuild -project PrismNative.xcodeproj -scheme PrismNative-Unit -destination 'platform=macOS' -only-testing:PrismNativeTests CODE_SIGNING_ALLOWED=NO test`

Expected: FAIL because source attribution provider types do not exist.

- [ ] **Step 3: Implement synchronous Apple Event sender copying**

```swift
@MainActor protocol RunningApplicationLookup {
    func sourceApplication(processIdentifier: Int32) -> SourceApplication?
}
```

`StubRunningApplications` is a same-file test implementation; the production implementation wraps `NSRunningApplication(processIdentifier:)`.

In the URL event callback, read `NSAppleEventManager.shared().currentAppleEvent`, obtain `keySenderPIDAttr`, copy the PID into an `Int32`, and stop touching `currentAppleEvent` after returning from the callback. Resolve the PID later through `NSRunningApplication(processIdentifier:)`.

- [ ] **Step 4: Implement confidence without guessing**

- Confirmed: sender PID resolves to a non-Prism application with bundle ID.
- Low: no sender PID, but the last activated application is available and labelled as inference.
- Unknown: neither source is usable.

Only Confirmed can become eligible for source rules. Low remains visible context but cannot automatically route.

- [ ] **Step 5: Define the Source Probe evidence contract and matrix template**

Define the data columns that the Task 9 Debug probe must record: timestamp, app name, bundle ID, sender PID presence, confidence, expected source, cold/warm state, and pass/fail. The markdown matrix has 20 rows per state for DingTalk, Lark, WeChat, Slack, Finder, Terminal, Safari, Chrome, and Arc when installed. Task 8 does not add an application entry point because the real AppDelegate and URL intake do not exist until Task 9.

- [ ] **Step 6: Bundle a disabled-by-default support manifest**

`SupportedSources.json` starts with schema version 1 and an empty `sources` array. Each eventual entry contains bundle ID, minimum and maximum verified macOS versions, cold/warm sample counts, confirmed count, false-attribution count, and validation date. `SourceSupportManifest` fails closed for malformed, unlisted, or out-of-range entries. This task enables no real source application; Task 18 updates the manifest only from committed physical evidence.

- [ ] **Step 7: Run tests and commit source attribution**

Run: `cd native && zsh scripts/generate-project.sh && xcodebuild -project PrismNative.xcodeproj -scheme PrismNative-Unit -destination 'platform=macOS' -only-testing:PrismNativeTests CODE_SIGNING_ALLOWED=NO test`

Expected: PASS, including Unknown and low-confidence gating cases.

```bash
git add native/PrismNative/System native/PrismNative/Resources/SupportedSources.json native/docs/source-attribution-matrix.md native/PrismNativeTests/SourceAttributionTests.swift
git commit -m "feat(native): add validated source attribution"
```

### Task 9: Connect URL Intake, Default Handlers, and Login Item State

**Files:**
- Create: `native/PrismNative/App/AppDelegate.swift`
- Modify: `native/PrismNative/App/PrismNativeApp.swift`
- Create: `native/PrismNative/System/DefaultBrowserService.swift`
- Create: `native/PrismNative/System/LoginItemService.swift`
- Create: `native/PrismNative/System/LinkIntakeService.swift`
- Create: `native/PrismNative/System/LinkRoutingCoordinator.swift`
- Create: `native/PrismNative/Diagnostics/SourceProbeView.swift`
- Test: `native/PrismNativeTests/SystemStateServicesTests.swift`
- Test: `native/PrismNativeTests/LinkIntakeServiceTests.swift`

**Interfaces:**
- Consumes: `LinkRequestQueue`, source attribution, default-handler APIs, `SMAppService.mainApp`.
- Produces: synchronous `LinkIntakeService.capture(url:senderPID:)`, asynchronous FIFO draining, `LinkRoutingCoordinating`, `DefaultHandlerState`, and `LoginItemState`.

- [ ] **Step 1: Write failing tests for explicit default changes and queue intake**

```swift
@Test func readingDefaultStatusNeverSetsAHandler() async throws {
    let client = StubDefaultHandlerClient(http: false, https: false)
    let service = DefaultBrowserService(client: client)

    let state = try await service.status()

    #expect(state == .inactive(http: false, https: false))
    #expect(client.setCalls.isEmpty)
}

@Test @MainActor func receivingTwoURLsEnqueuesTwoDifferentRequests() async throws {
    let store = InMemoryPendingRequestStore()
    let queue = LinkRequestQueue(store: store)
    let intake = LinkIntakeService(queue: queue, sourceAttributor: StubSourceAttributor(result: .unknown))

    intake.capture(url: URL(string: "https://one.example")!, senderPID: nil)
    intake.capture(url: URL(string: "https://two.example")!, senderPID: nil)
    try await intake.drainForTesting()

    #expect(await queue.snapshot().map(\.url.host) == ["one.example", "two.example"])
}

@Test @MainActor func automaticLaunchFailureKeepsTheSameRequestRecoverable() async throws {
    let harness = LinkRoutingCoordinator.fixture(
        automaticBrowserID: "com.apple.Safari",
        launchShouldFail: true
    )
    let request = LinkRequest.fixture(id: .test(40))
    try await harness.queue.enqueue(request)

    await harness.coordinator.processNext()

    #expect(await harness.queue.next()?.id == request.id)
    #expect(harness.presenter.request?.id == request.id)
    #expect(harness.history.entries.filter { $0.requestID == request.id }.count == 1)
    #expect(harness.history.entries[0].result == .failure)
}

@Test @MainActor func historyWriteFailureNeverReplaysSuccessfulHandoff() async throws {
    let harness = LinkRoutingCoordinator.fixture(
        automaticBrowserID: "com.apple.Safari",
        launchShouldFail: false,
        historyShouldFail: true
    )
    let request = LinkRequest.fixture(id: .test(41))
    try await harness.queue.enqueue(request)

    await harness.coordinator.processNext()

    #expect(harness.launcher.handoffCount == 1)
    #expect(await harness.queue.next() == nil)
    #expect(await harness.queue.terminalSnapshot().first?.outcome == .succeeded)
    #expect(harness.warning.last == .historyNotSaved)
}

@Test @MainActor func coldStartBufferDrainsAfterRestoredRequests() async throws {
    let bootstrap = BootstrapLinkBuffer()
    bootstrap.capture(URL(string: "https://new.example")!, senderPID: nil)
    let harness = LinkIntakeService.fixture(restoredURLs: ["https://old.example"], bootstrap: bootstrap)

    try await harness.finishRestoreAndDrain()

    #expect(await harness.queue.snapshot().map(\.url.host) == ["old.example", "new.example"])
}

@Test @MainActor func launchingSaveFailureNeverCallsBrowser() async throws {
    let harness = LinkRoutingCoordinator.fixture(pendingSaveFailure: .onCall(1))
    let request = LinkRequest.fixture(id: .test(42))
    try await harness.seedWithoutFailure(request)

    await harness.coordinator.processNext()

    #expect(harness.launcher.handoffCount == 0)
    #expect(harness.presenter.context == .storageUnavailable)
}

@Test @MainActor func terminalSaveFailureAfterHandoffNeverHandsOffAgain() async throws {
    let harness = LinkRoutingCoordinator.fixture(pendingSaveFailure: .onCall(2))
    let request = LinkRequest.fixture(id: .test(43))
    try await harness.seedWithoutFailure(request)

    await harness.coordinator.processNext()
    await harness.coordinator.processNext()

    #expect(harness.launcher.handoffCount == 1)
    #expect(harness.presenter.context == .outcomeUnknown(browserID: "com.apple.Safari"))
    #expect(harness.warning.last == .recoveryStoreUnavailable)
}
```

The fixture overloads in `LinkIntakeServiceTests.swift` return the coordinator plus in-memory queue, presenter, launcher, settings, rules, browser catalog, History repository, and warning presenter; they call production coordinator methods and do not reimplement routing.

- [ ] **Step 2: Run and verify failures**

Run: `cd native && zsh scripts/generate-project.sh && xcodebuild -project PrismNative.xcodeproj -scheme PrismNative-Unit -destination 'platform=macOS' -only-testing:PrismNativeTests CODE_SIGNING_ALLOWED=NO test`

Expected: FAIL because default-handler, login-item, and intake services do not exist.

- [ ] **Step 3: Implement default-handler state**

Use this testable boundary; `StubDefaultHandlerClient` is a same-file test fake that records `setDefault` calls:

```swift
@MainActor protocol DefaultHandlerClient {
    func handlerBundleIdentifier(forScheme scheme: String) -> String?
    func setDefault(applicationURL: URL, forScheme scheme: String) async throws
}
```

The production client queries `NSWorkspace.urlForApplication(toOpen:)` with `http://example.com` and `https://example.com`, then reads each bundle identifier. It sets `http` and `https` only from `setAsDefaultAfterUserConfirmation()`, then re-queries and returns the real state. An attempted setter call is not success.

- [ ] **Step 4: Implement login item mapping**

Map `SMAppService.mainApp.status` into `.notRegistered`, `.enabled`, `.requiresApproval`, or `.notFound`. Register and unregister only after user actions. Surface `requiresApproval` with an action that calls `SMAppService.openSystemSettingsLoginItems()`. Unit tests use a fake; signed integration testing occurs in Task 19.

- [ ] **Step 5: Implement one routing coordinator and AppDelegate intake**

```swift
@MainActor protocol LinkSelectionPresenting: AnyObject {
    func present(_ request: LinkRequest, context: SelectorPresentationContext)
    func dismiss(requestID: UUID)
}

enum SelectorPresentationContext: Equatable {
    case normal
    case launchFailed(browserID: BrowserID, message: String)
    case outcomeUnknown(browserID: BrowserID?)
    case noAvailableBrowsers
    case storageUnavailable
}

@MainActor protocol LinkRoutingCoordinating: AnyObject {
    func processNext() async
    func select(browserID: BrowserID, for requestID: UUID) async
    func retry(browserID: BrowserID, for requestID: UUID) async
    func markUncertainAttemptCompleted(requestID: UUID) async
    func cancel(requestID: UUID) async
}

@MainActor protocol PersistenceWarningPresenting: AnyObject {
    func present(_ warning: PersistenceWarning)
}
```

`LinkRoutingCoordinator` is the only production type allowed to combine the queue, rule engine, current `SourceSupportManifest` eligibility, browser launcher, History state machine/repository, and selector presenter. It creates at most one History entry per request. Automatic and manual launches call the same private attempt method. Before the system call it best-effort writes the processing History state, reports but ignores a History failure, and persists `.launching`; a handoff failure moves the request back to `.presenting`, preserves the full URL, best-effort writes failure History, and presents `.launchFailed`. A successful handoff first atomically moves the active request into a URL-free `.succeeded` terminal record containing the sanitized History entry, making the request ineligible for replay and removing the complete URL; then it best-effort writes History and compacts the journal. History failure never blocks or repeats the browser handoff and produces `.historyNotSaved`. On manual success it best-effort persists `lastUsedBrowserID` and warns without reversing success if that preference write fails.

Recovery-store failure follows four non-negotiable rules. If persisting `.launching` fails, never call the browser and show `.storageUnavailable`. If the browser accepted the handoff but terminal-journal save fails, retain an in-memory `.outcomeUnknown` guard, never hand off again in the current session, show Retry/Mark Completed/Cancel plus `.recoveryStoreUnavailable`, and require explicit user recovery; restart may also restore the last durable `.launching` state as Outcome Unknown. If a failed handoff cannot persist `.presenting`, retain the request, stop automatic draining, and show storage recovery without another handoff. If terminal compaction fails, leave the URL-free terminal record in place; never recreate the request. The application retries only persistence operations after storage becomes available, never a browser handoff.

On restore, `.outcomeUnknown` is never automatically sent. The selector explains “Prism closed while handing off this link” and offers Retry, Mark Completed, or Cancel. Retry is an explicit new attempt on the same request and increments its attempt count. Mark Completed persists a terminal journal without another browser handoff. With zero available browsers, present `.noAvailableBrowsers` and keep the request pending. Cancellation atomically persists `.cancelled` plus an optional sanitized History entry; if critical recovery storage cannot save, keep the request and show a storage error. History upsert failure after cancellation shows a warning but does not resurrect the request. When History is disabled, no `HistoryEntry` is built or persisted.

Attach `AppDelegate` through `@NSApplicationDelegateAdaptor` in `PrismNativeApp`. `AppDelegate.init` synchronously creates and owns a database-free `BootstrapLinkBuffer`, then constructs the single shared `AppEnvironment` service graph without restoring or draining the recovery queue. `PrismNativeApp` injects `appDelegate.environment` into its scenes; it never creates a second production environment. On the main actor, `application(_:open:)` validates `http`/`https`, copies the sender PID, assigns a monotonic sequence, and appends each URL to the bootstrap buffer before returning. `applicationDidFinishLaunching` awaits persistent queue restoration through that same environment, appends the bootstrap buffer after all restored requests, then starts exactly one drain worker. No window or later dependency injection is required to capture a cold-start URL. `StubSourceAttributor` and all coordinator harness dependencies used above are declared in `LinkIntakeServiceTests.swift`; the shared in-memory pending store comes from `PrismNativeTests/TestFixtures.swift`.

Under `#if DEBUG`, `PrismNativeApp` accepts `--source-probe` and replaces its normal root with `SourceProbeView` while retaining the Task 9 real AppDelegate, URL handler, and source attribution path. The probe implements the Task 8 evidence contract and writes only local diagnostic rows; Release builds do not compile the view or launch-argument branch.

- [ ] **Step 6: Run focused, native, and core tests**

Run:

```bash
cd native
swift test
zsh scripts/generate-project.sh
xcodebuild -project PrismNative.xcodeproj -scheme PrismNative-Unit -destination 'platform=macOS' -only-testing:PrismNativeTests CODE_SIGNING_ALLOWED=NO test
```

Expected: every test passes; there are no set-default calls during status reads or startup.

- [ ] **Step 7: Commit system intake and state services**

```bash
git add native/PrismNative/App/AppDelegate.swift native/PrismNative/App/PrismNativeApp.swift native/PrismNative/System native/PrismNative/Diagnostics/SourceProbeView.swift native/PrismNativeTests
git commit -m "feat(native): connect system link intake"
```

### Task 10: Implement Window Coordination and Multi-Display Positioning

**Files:**
- Create: `native/PrismNative/Windows/SelectorPositioner.swift`
- Create: `native/PrismNative/Windows/SelectorPanel.swift`
- Create: `native/PrismNative/Windows/SelectorPanelController.swift`
- Create: `native/PrismNative/Windows/WindowCoordinator.swift`
- Test: `native/PrismNativeTests/SelectorPositionerTests.swift`

**Interfaces:**
- Consumes: `LinkSelectionPresenting`, active `LinkRequest`, an injected `AnyView` content factory, and a `MainWindowOpening` adapter supplied by SwiftUI; it does not depend on the Task 11 selector model.
- Produces: `SelectorPositioner.origin(panelSize:pointer:visibleFrames:)`, `WindowCoordinator` conformance to `LinkSelectionPresenting`, selector-panel ownership, `showMainWindow(route:)`, and `hideSelector()`.

- [ ] **Step 1: Write failing negative-coordinate and edge-clamp tests**

```swift
@Test func selectorRemainsInsideLeftDisplayVisibleFrame() {
    let frame = CGRect(x: -1920, y: 24, width: 1920, height: 1056)
    let origin = SelectorPositioner().origin(
        panelSize: CGSize(width: 425, height: 200),
        pointer: CGPoint(x: -1900, y: 30),
        visibleFrames: [frame]
    )

    #expect(origin.x >= frame.minX)
    #expect(origin.y >= frame.minY)
    #expect(origin.x + 425 <= frame.maxX)
    #expect(origin.y + 200 <= frame.maxY)
}

@Test @MainActor func selectorPanelCanReceiveKeyboardFocus() {
    let panel = SelectorPanel(contentRect: CGRect(x: 0, y: 0, width: 425, height: 200))
    #expect(panel.canBecomeKey)
    #expect(panel.canBecomeMain == false)
}
```

- [ ] **Step 2: Run and verify failure**

Run: `cd native && zsh scripts/generate-project.sh && xcodebuild -project PrismNative.xcodeproj -scheme PrismNative-Unit -destination 'platform=macOS' -only-testing:PrismNativeTests CODE_SIGNING_ALLOWED=NO test`

Expected: FAIL because `SelectorPositioner` does not exist.

- [ ] **Step 3: Implement pure positioning**

Select the visible frame containing the pointer; if none contains it, choose the frame with the shortest squared distance. Start 12 points down-right from the pointer and clamp x/y to the selected visible frame. The function accepts CGRect inputs so it is testable without `NSScreen`.

- [ ] **Step 4: Implement the fixed NSPanel**

Create `final class SelectorPanel: NSPanel` with `canBecomeKey == true` and `canBecomeMain == false`. Configure it as borderless and non-activating, content size 425 × 200, shadow enabled, floating level, collection behavior for all spaces, and an `NSHostingView<AnyView>`. The controller sets the hosting view as initial first responder before `makeKeyAndOrderFront`; this keeps keyboard selection reliable without activating the main window.

- [ ] **Step 5: Implement one window coordinator**

The value-identified SwiftUI `WindowGroup(id: "main", for: MainWindowIdentity.self)` remains the only owner of the main window. `WindowCoordinator` owns only one selector panel; it never creates, retains, enumerates, or closes a main `NSWindow`. `MainWindowOpening` accepts an `AppRoute`, updates the shared route, and invokes the registered `OpenWindowAction` with `id: "main"` and the fixed `.singleton` value. `present(_:context:)` asks the injected content factory for the current selector view, positions it using `NSEvent.mouseLocation` and `NSScreen.visibleFrame`, then makes it key. Task 10 uses a minimal localized Text content factory; Task 11 replaces it with the real selector. `dismiss(requestID:)` ignores stale IDs and hides only the panel for the matching active request. Closing the SwiftUI main window closes that instance; Dock reopen, status item, and `showMainWindow(route:)` reopen the same singleton value. Repeated calls while it is visible bring that window forward and never create another. `Cmd+Q` and menu Quit terminate the app.

- [ ] **Step 6: Run unit tests and an AppKit smoke test**

Run: `cd native && zsh scripts/generate-project.sh && xcodebuild -project PrismNative.xcodeproj -scheme PrismNative-Unit -destination 'platform=macOS' -only-testing:PrismNativeTests CODE_SIGNING_ALLOWED=NO test`

Verify the panel size with an assertion, then test pointer positions on main, right, left-negative, and above displays. Do not claim physical multi-display acceptance until Task 18.

- [ ] **Step 7: Commit window coordination**

```bash
git add native/PrismNative/Windows native/PrismNativeTests/SelectorPositionerTests.swift
git commit -m "feat(native): add selector window coordination"
```

---

## Phase C — Native Clarity UI and Product Features

### Task 11: Implement the Figma Selector and Horizontal Browser Scrolling

**Files:**
- Create: `native/PrismNative/Features/Selector/SelectorMetrics.swift`
- Create: `native/PrismNative/Features/Selector/SelectorViewModel.swift`
- Create: `native/PrismNative/Features/Selector/SelectorView.swift`
- Create: `native/PrismNative/Features/Selector/BrowserChoiceView.swift`
- Create: `native/PrismNative/Features/Selector/KeyboardShortcutBadge.swift`
- Create: `native/PrismNative/Features/Selector/SelectorEmptyStateView.swift`
- Create: `native/PrismNative/Features/Selector/HorizontalScrollBridge.swift`
- Test: `native/PrismNativeTests/SelectorViewModelTests.swift`
- Test: `native/PrismNativeUITests/SelectorUITests.swift`

**Interfaces:**
- Consumes: active request, browser catalog, and `LinkRoutingCoordinating` from Task 9.
- Produces: selection, cancellation, retry, create-rule intent, pending-count presentation, and Figma-matched selector UI.

- [ ] **Step 1: Write failing layout and keyboard tests**

```swift
@Test(arguments: [(3, 130.0), (4, 109.14), (8, 109.14)])
func itemWidthPreservesThreeOrThreeAndAHalfItems(count: Int, expected: Double) {
    #expect(abs(SelectorMetrics.itemWidth(browserCount: count) - expected) < 0.02)
}

@Test @MainActor func rightArrowMovesAndRequestsReveal() {
    let model = SelectorViewModel.fixture(browserCount: 5)
    model.handle(.rightArrow)
    #expect(model.selectedIndex == 1)
    #expect(model.revealBrowserID == model.browsers[1].id)
}

@Test @MainActor func pendingCountAppearsOnlyWhenMoreThanOneLinkWaits() {
    #expect(SelectorViewModel.fixture(pendingCount: 1).pendingBadgeText == nil)
    #expect(SelectorViewModel.fixture(pendingCount: 3).pendingBadgeText == "3")
}

@Test func fourItemGeometryShowsExactlyHalfOfFourth() {
    let width = SelectorMetrics.itemWidth(browserCount: 4)
    let thirdMaxX = SelectorMetrics.viewportLeadingInset + (2 * (width + SelectorMetrics.itemGap)) + width
    let fourthVisible = SelectorMetrics.viewportSize.width - (thirdMaxX + SelectorMetrics.itemGap)
    #expect(thirdMaxX <= SelectorMetrics.viewportSize.width)
    #expect(abs(fourthVisible - width / 2) < 0.02)
}

@Test @MainActor func noBrowserStatePreservesRecoveryActions() {
    let model = SelectorViewModel.fixture(browserCount: 0)
    #expect(model.presentation == .noAvailableBrowsers)
    #expect(model.canRescan)
    #expect(model.canOpenBrowserManagement)
}
```

- [ ] **Step 2: Run and verify failure**

Run: `cd native && zsh scripts/generate-project.sh && xcodebuild -project PrismNative.xcodeproj -scheme PrismNative-Unit -destination 'platform=macOS' -only-testing:PrismNativeTests CODE_SIGNING_ALLOWED=NO test`

Expected: FAIL because selector metrics and model do not exist.

- [ ] **Step 3: Implement exact layout metrics from Figma node 4:395**

```swift
enum SelectorMetrics {
    static let panelSize = CGSize(width: 425, height: 200)
    static let outerRadius: CGFloat = 15
    static let topHeight: CGFloat = 40
    static let viewportSize = CGSize(width: 412, height: 142)
    static let itemGap: CGFloat = 8
    static let viewportLeadingInset: CGFloat = 6

    static func itemWidth(browserCount: Int) -> CGFloat {
        if browserCount <= 3 { return 130 }
        return (viewportSize.width - viewportLeadingInset - 3 * itemGap) / 3.5
    }
}
```

- [ ] **Step 4: Implement selection behavior before styling**

`SelectorViewModel` supports left/right, numbers 1–9, Enter, Escape, mouse selection, cancellation, retry, Mark Completed for uncertain handoffs, and horizontal reveal. Numbers above nine have no direct shortcut but remain scrollable. Browser selection, retry, completion, and cancellation delegate to `LinkRoutingCoordinating`; the view model never writes History, opens a browser, or mutates the queue directly. Only the coordinator's terminal state dismisses the panel and advances.

- [ ] **Step 5: Translate the Figma node to SwiftUI**

- Root 425 × 200, white semantic surface, radius 15, and equivalent drop shadow.
- Top row starts at x 7/y 7: source 75 × 40, flexible URL field matching 248 at three items, Cancel 79 × 40, 5-point gaps.
- Browser viewport starts at x 7/y 52 and remains 412 × 142.
- For up to three items, render fixed 130-point cards.
- For more than three, use horizontal `ScrollView` + `ScrollViewReader`, width from `SelectorMetrics`, no indicators, and leave the fourth half-visible.
- `HorizontalScrollBridge` preserves native trackpad horizontal deltas, converts a conventional mouse wheel's vertical delta into horizontal movement while the pointer is over the browser viewport, and exposes click-drag scrolling without turning a drag into a browser selection. Arrow or numeric selection of an offscreen browser calls `scrollTo` so it becomes fully visible.
- Use system SF Pro and actual `NSWorkspace` icons; do not copy Figma's sample Chrome asset.
- Preserve URL truncation, selected background, 45-point icons in the three-column state, labels, and shortcut badges.
- When two or more requests wait, overlay a 14-point system-secondary badge on the source field's top-right corner with the exact pending count; it does not move or resize any Figma field and its VoiceOver value is “N links waiting.”
- Add a context menu to each browser card with “Always open this domain in [browser].” Add “Always open links from [source] in [browser]” only when the current source is Confirmed and its bundle ID is eligible. Either choice opens a prefilled rule editor and still requires explicit Save; the fixed panel gains no permanent controls.
- Present failure within the fixed height by tinting the failed item and URL status surface plus an accessible help popover; do not increase panel height.
- With no available browsers, replace the card strip inside the same 412 × 142 viewport with “No browser is available,” Rescan, and Open Browser Management. Rescan updates the same active request; opening management does not complete or cancel it. With `.outcomeUnknown`, show Retry, Mark Completed, and Cancel without automatically selecting a browser.

- [ ] **Step 6: Add accessibility and motion behavior**

Each browser exposes name, shortcut, selected state, and failure state to VoiceOver. Respect Reduce Motion by removing animated scroll transitions. Verify keyboard-only operation and increased-contrast borders.

- [ ] **Step 7: Run tests and visual comparison**

Run:

```bash
cd native
zsh scripts/generate-project.sh
xcodebuild -project PrismNative.xcodeproj -scheme PrismNative-Unit -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
zsh scripts/generate-project.sh
xcodebuild -project PrismNative.xcodeproj -scheme PrismNative-UI -destination 'platform=macOS' CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- test
```

Capture the rendered panel at 425 × 200 and compare side-by-side with Figma node `4:395` for three and five browsers. Record measured deviations in `native/docs/selector-visual-validation.md`; fix spacing or color differences before commit.

- [ ] **Step 8: Commit selector UI**

```bash
git add native/PrismNative/Features/Selector native/PrismNativeTests/SelectorViewModelTests.swift native/PrismNativeUITests/SelectorUITests.swift native/docs/selector-visual-validation.md
git commit -m "feat(native): build Figma browser selector"
```

### Task 12: Build Onboarding, App Shell, Navigation, and Menu Bar

**Files:**
- Create: `native/PrismNative/Features/Shell/AppShellView.swift`
- Create: `native/PrismNative/Features/Shell/SidebarView.swift`
- Create: `native/PrismNative/Features/Shell/PageStateView.swift`
- Create: `native/PrismNative/Features/Shell/RecoveryBanner.swift`
- Create: `native/PrismNative/Features/Onboarding/OnboardingViewModel.swift`
- Create: `native/PrismNative/Features/Onboarding/OnboardingView.swift`
- Create: `native/PrismNative/Features/Onboarding/OnboardingStep.swift`
- Create: `native/PrismNative/MenuBar/StatusItemController.swift`
- Test: `native/PrismNativeTests/OnboardingViewModelTests.swift`
- Test: `native/PrismNativeUITests/OnboardingUITests.swift`

**Interfaces:**
- Consumes: default handler, browser catalog, settings, window coordinator, update service.
- Produces: four-destination Native Clarity shell, four-step onboarding, menu bar routes, and automatic-rule pause state.

- [ ] **Step 1: Write failing onboarding gate tests**

```swift
@Test @MainActor func onboardingCannotCompleteWithoutAUsableBrowser() async {
    let model = OnboardingViewModel.fixture(browsers: [])
    await model.advanceFromBrowserScan()
    #expect(model.step == .browsers)
    #expect(model.alert == .noUsableBrowser)
}
```

- [ ] **Step 2: Run and verify failure**

Run: `cd native && zsh scripts/generate-project.sh && xcodebuild -project PrismNative.xcodeproj -scheme PrismNative-Unit -destination 'platform=macOS' -only-testing:PrismNativeTests CODE_SIGNING_ALLOWED=NO test`

Expected: FAIL because the onboarding model does not exist.

- [ ] **Step 3: Implement the four-step model**

Steps are Welcome, Link Handling, Browsers, and Test Link. The default-handler step shows HTTP/HTTPS separately and advances only after re-querying real state or the user chooses Finish Later. The browser step requires one usable browser. Test Link uses the real selector and real launch result.

- [ ] **Step 4: Implement Native Clarity shell**

Use `NavigationSplitView` with History, Rules, Browsers, and Settings, a 760 × 520 minimum content size, 190-point preferred sidebar, system window/content backgrounds, system fonts, restrained system blue accent, native focus rings and hover states, and keyboard navigation. `PageStateView` has explicit loading, empty, failed, and recovery variants. `RecoveryBanner` presents default-handler drift, recovered corrupt data, pending History reconciliation, and update failure with one primary recovery action. Do not reuse Electron CSS, Tailwind, remote fonts, fixed light-only colors, or color as the only status signal.

Keep the value-identified `WindowGroup(id: "main", for: MainWindowIdentity.self)` as the single main-window owner. Its root registers SwiftUI `openWindow` with the Task 10 `MainWindowOpening` adapter and binds navigation to the one shared `AppRoute`. `applicationShouldHandleReopen`, Dock activation, onboarding completion, and status-item destinations all call the adapter with `.singleton`. Replace `CommandGroup(replacing: .newItem)` with no New Window action. Add UI tests proving an already-open window is brought forward when History, Settings, and Open Prism are invoked repeatedly; closing then reopening creates one replacement; every point in the sequence has exactly one main window with the expected route. The selector panel is not counted as a main window.

Feature-state contract:

- History empty: “Handled links will appear here” plus Test Link.
- Rules empty: “Unmatched links use your selected fallback” plus Create Rule; a search with no matches instead shows Clear Search.
- Browsers empty: Rescan, Add Custom Browser, and Open Applications Folder.
- Settings: real HTTP/HTTPS drift, login approval, persistence recovery, and update errors use `RecoveryBanner` rather than a success-colored toggle.

Task 18 captures all four destinations in light and dark appearances and manually verifies Increased Contrast and Reduce Motion. Text, actions, focus order, and content hierarchy must remain usable in every state.

- [ ] **Step 5: Implement the AppKit status item**

Menu items: Open Prism, History, Rules, Browsers, Settings, Pause/Resume Automatic Rules, Check for Updates, separator, Quit Prism. Pause changes only rule evaluation; incoming links still show the selector.

- [ ] **Step 6: Run tests and onboarding UI flow**

Run:

```bash
cd native
zsh scripts/generate-project.sh
xcodebuild -project PrismNative.xcodeproj -scheme PrismNative-Unit -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
zsh scripts/generate-project.sh
xcodebuild -project PrismNative.xcodeproj -scheme PrismNative-UI -destination 'platform=macOS' CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- test
```

Verify a fresh store opens onboarding, default-handler failure does not show success, no-browser state is recoverable, test-link failure remains on the step, and completed onboarding opens History.

- [ ] **Step 7: Commit shell and onboarding**

```bash
git add native/PrismNative/Features/Shell native/PrismNative/Features/Onboarding native/PrismNative/MenuBar native/PrismNativeTests/OnboardingViewModelTests.swift native/PrismNativeUITests/OnboardingUITests.swift
git commit -m "feat(native): add onboarding and app shell"
```

### Task 13: Build History with Recovery Actions

**Files:**
- Create: `native/PrismNative/Features/History/HistoryViewModel.swift`
- Create: `native/PrismNative/Features/History/HistoryView.swift`
- Create: `native/PrismNative/Features/History/HistoryRow.swift`
- Modify: `native/PrismNative/System/LinkIntakeService.swift`
- Test: `native/PrismNativeTests/HistoryViewModelTests.swift`

**Interfaces:**
- Consumes: history repository, `LinkRoutingCoordinating`, link intake, browser catalog, clipboard, and URL sanitizer.
- Produces: recent history list, retry/reopen, copy, create-rule handoff, delete, clear, and empty/recovery states.

- [ ] **Step 1: Write failing retry and privacy tests**

```swift
@Test @MainActor func reopenUnavailableBrowserReturnsToSelector() async throws {
    let model = HistoryViewModel.fixture(entry: .cancelledFixture, availableBrowsers: [])
    let originalRequestID = model.entries[0].requestID
    await model.reopen(model.entries[0])
    let reopened = try #require(model.presentedSelectorRequest)
    #expect(reopened.id != originalRequestID)
    #expect(reopened.url == model.entries[0].sanitizedURL)
    #expect(reopened.reopenedFromHistoryEntryID == model.entries[0].id)
}
```

- [ ] **Step 2: Run and verify failure**

Run: `cd native && zsh scripts/generate-project.sh && xcodebuild -project PrismNative.xcodeproj -scheme PrismNative-Unit -destination 'platform=macOS' -only-testing:PrismNativeTests CODE_SIGNING_ALLOWED=NO test`

Expected: FAIL because `HistoryViewModel` does not exist.

- [ ] **Step 3: Implement one-row-per-request presentation**

Display source, target snapshot, routing method, result, time, and sanitized URL. Failure exposes reason and Retry through `LinkRoutingCoordinating` while the recovery queue still owns the complete URL. Cancelled exposes Reopen only when `sanitizedURL` exists; `LinkIntakeService.enqueueReopened(url:fromHistoryEntryID:)` creates and persists a new request ID from that exact persisted sanitized URL, sets `reopenedFromHistoryEntryID`, and returns it to the same routing coordinator. The view model never opens a browser or mutates the queue directly. The original cancelled row remains unchanged and the reopened request produces its own History row. If `sanitizedURL` is nil, disable Reopen and explain that URL history was disabled. Never invent removed query parameters or fragments.

When the list is empty, use the shared History empty state and Test Link action. A repository read failure uses the failed state with Retry and never substitutes the empty state.

- [ ] **Step 4: Implement actions and retention**

Copy uses the sanitized URL. Create Rule opens the rule editor with exact host prefilled. Delete and Clear require confirmation. Enforce 100 entries/30 days after every upsert and at startup.

- [ ] **Step 5: Run tests and commit**

Run: `cd native && zsh scripts/generate-project.sh && xcodebuild -project PrismNative.xcodeproj -scheme PrismNative-Unit -destination 'platform=macOS' -only-testing:PrismNativeTests CODE_SIGNING_ALLOWED=NO test`

Expected: PASS for retry, Reopen, deletion, clearing, privacy, and retention.

```bash
git add native/PrismNative/Features/History native/PrismNative/System/LinkIntakeService.swift native/PrismNativeTests/HistoryViewModelTests.swift
git commit -m "feat(native): add recoverable history"
```

### Task 14: Build Ordered URL and Source Rules

**Files:**
- Create: `native/PrismNative/Features/Rules/RulesViewModel.swift`
- Create: `native/PrismNative/Features/Rules/RulesView.swift`
- Create: `native/PrismNative/Features/Rules/RuleEditorView.swift`
- Create: `native/PrismNative/Features/Rules/RuleTesterView.swift`
- Test: `native/PrismNativeTests/RulesViewModelTests.swift`

**Interfaces:**
- Consumes: rule repository, RuleEngine, browser catalog, and current `SourceSupportManifest` eligibility.
- Produces: create, edit, enable, disable, delete, reorder, search, and test-rule flows.

- [ ] **Step 1: Write failing reorder and source-gate tests**

```swift
@Test @MainActor func ineligibleSourceCannotBeSaved() async {
    let model = RulesViewModel.fixture(sourceEligible: false)
    await model.save(.sourceFixture(bundleID: "com.example.Unverified"))
    #expect(model.validationError == .sourceNotEligible)
    #expect(model.rules.isEmpty)
}
```

- [ ] **Step 2: Run and verify failure**

Run: `cd native && zsh scripts/generate-project.sh && xcodebuild -project PrismNative.xcodeproj -scheme PrismNative-Unit -destination 'platform=macOS' -only-testing:PrismNativeTests CODE_SIGNING_ALLOWED=NO test`

Expected: FAIL because the rules view model does not exist.

- [ ] **Step 3: Implement explicit sections and ordering**

Show URL Rules above Source App Rules. Reorder only within the active section and rewrite contiguous priorities starting at zero in one repository transaction. The card displays matcher semantics, target browser, availability, enabled state, and priority. A genuinely empty repository uses Create Rule; a non-empty repository with no search matches uses Clear Search and never looks like the empty repository.

- [ ] **Step 4: Implement the editor and tester**

URL editor choices are Exact Domain, Domain and Subdomains, and Full URL Contains. Source picker lists only bundle IDs eligible in the bundled manifest for the current macOS version. The Test URL surface shows whether the draft matches, the final browser, and any earlier rule that wins first. Add tests proving a fresh install sees bundled approved sources, an unlisted source is hidden, and an existing rule stops automatic matching after its manifest entry is removed.

- [ ] **Step 5: Implement invalid-target recovery**

Keep rules whose browser disappears, mark Target unavailable, and offer Choose Another Browser. Do not silently mutate target IDs during rescan.

- [ ] **Step 6: Run tests and commit**

Run: `cd native && zsh scripts/generate-project.sh && xcodebuild -project PrismNative.xcodeproj -scheme PrismNative-Unit -destination 'platform=macOS' -only-testing:PrismNativeTests CODE_SIGNING_ALLOWED=NO test`

Expected: PASS for type precedence, reordering, eligibility, and unavailable targets.

```bash
git add native/PrismNative/Features/Rules native/PrismNativeTests/RulesViewModelTests.swift
git commit -m "feat(native): add ordered routing rules"
```

### Task 15: Build Browser Management

**Files:**
- Create: `native/PrismNative/Features/Browsers/BrowsersViewModel.swift`
- Create: `native/PrismNative/Features/Browsers/BrowsersView.swift`
- Create: `native/PrismNative/Features/Browsers/BrowserRow.swift`
- Create: `native/PrismNative/System/CustomBrowserPicker.swift`
- Test: `native/PrismNativeTests/BrowsersViewModelTests.swift`

**Interfaces:**
- Consumes: browser catalog, browser preference repository, rule repository, `NSOpenPanel` adapter.
- Produces: scan, rescan, add custom, remove custom, reorder selector, availability, shortcut, and rule-reference count.

- [ ] **Step 1: Write failing ordering and removal tests**

```swift
@Test @MainActor func removingCustomBrowserKeepsReferencedUnavailableRow() async throws {
    let model = BrowsersViewModel.fixture(customBrowserReferencedByRules: true)
    try await model.removeCustomBrowser(id: "com.example.Custom")
    #expect(model.unavailableReferenced.map(\.id) == ["com.example.Custom"])
}
```

- [ ] **Step 2: Run and verify failure**

Run: `cd native && zsh scripts/generate-project.sh && xcodebuild -project PrismNative.xcodeproj -scheme PrismNative-Unit -destination 'platform=macOS' -only-testing:PrismNativeTests CODE_SIGNING_ALLOWED=NO test`

Expected: FAIL because the browser management view model does not exist.

- [ ] **Step 3: Implement the three browser sections**

Detected, Custom, and Unavailable but Referenced. Each row shows native icon, display name, location, status, selector position, numeric shortcut when 1–9, and rule count. When no usable browser exists, show Rescan, Add Custom Browser, and Open Applications Folder; an actual scan error uses the failed state with Retry.

- [ ] **Step 4: Implement custom application selection**

`NSOpenPanel` accepts a single `.app`. Persist bundle ID and security-scoped bookmark. Validate the application before save; show a specific rejection if it cannot open HTTP/HTTPS.

- [ ] **Step 5: Implement ordering for selector scrolling**

Drag reorder updates stable order across all available browsers. The selector reads the same order and does not maintain a second list. More than three requires no extra setting; horizontal behavior is automatic.

- [ ] **Step 6: Run tests and commit**

Run: `cd native && zsh scripts/generate-project.sh && xcodebuild -project PrismNative.xcodeproj -scheme PrismNative-Unit -destination 'platform=macOS' -only-testing:PrismNativeTests CODE_SIGNING_ALLOWED=NO test`

Expected: PASS for scan, custom validation, removal, references, and selector order.

```bash
git add native/PrismNative/Features/Browsers native/PrismNative/System/CustomBrowserPicker.swift native/PrismNativeTests/BrowsersViewModelTests.swift
git commit -m "feat(native): add browser management"
```

### Task 16: Build Settings, Localization, and Accessibility Coverage

**Files:**
- Create: `native/PrismNative/Features/Settings/SettingsViewModel.swift`
- Create: `native/PrismNative/Features/Settings/SettingsView.swift`
- Create: `native/PrismNative/Resources/en.lproj/Localizable.strings`
- Create: `native/PrismNative/Resources/zh-Hans.lproj/Localizable.strings`
- Create: `native/PrismNative/Resources/Base.lproj/Main.strings`
- Test: `native/PrismNativeTests/SettingsViewModelTests.swift`
- Test: `native/PrismNativeUITests/AccessibilityUITests.swift`

**Interfaces:**
- Consumes: default handler, login item, settings repository, browser catalog, history repository, and `UpdateChecking`.
- Produces: settings groups, English/Simplified Chinese UI, accessibility identifiers, and user-driven system actions.

- [ ] **Step 1: Write failing real-state tests**

```swift
@Test @MainActor func requiresApprovalIsNotDisplayedAsEnabled() async {
    let model = SettingsViewModel.fixture(loginState: .requiresApproval)
    await model.refresh()
    #expect(model.loginStatusTextKey == "settings.login.requiresApproval")
    #expect(model.loginToggleIsOn == false)
}
```

- [ ] **Step 2: Run and verify failure**

Run: `cd native && zsh scripts/generate-project.sh && xcodebuild -project PrismNative.xcodeproj -scheme PrismNative-Unit -destination 'platform=macOS' -only-testing:PrismNativeTests CODE_SIGNING_ALLOWED=NO test`

Expected: FAIL because the settings model does not exist.

- [ ] **Step 3: Implement settings groups**

- Link Handling: separate HTTP/HTTPS status, Set as Default, Refresh.
- Unmatched Links: Always Ask, Preferred Browser, Last Used Browser.
- Startup and Interface: login item state, language, menu bar visibility.
- History and Privacy: enable history, 30-day/100-entry summary, Clear History.
- Updates: automatic checks, manual check, current version, last check result.

Show Preferred Browser picker only for that behavior. Last Used remains unavailable until one successful manual selection exists.

- [ ] **Step 4: Add complete localization keys**

Use `String(localized:)` and localized format arguments; no runtime language dictionary. Match key sets in English and Simplified Chinese using a script that sorts and diffs keys. Localize menu bar items, onboarding, selector accessibility labels, errors, empty states, and update states.

- [ ] **Step 5: Add accessibility identifiers and UI tests**

Automated tests assert accessibility identifiers, labels, values, keyboard traversal, semantic contrast variants, disabled animations when Reduce Motion is injected, and no color-only error communication. Task 18 separately records manual VoiceOver reading order, real Increased Contrast, and real Reduce Motion evidence; a normal XCUITest run is not accepted as proof of those system modes.

- [ ] **Step 6: Run tests and commit**

Run:

```bash
cd native
zsh scripts/generate-project.sh
xcodebuild -project PrismNative.xcodeproj -scheme PrismNative-Unit -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
zsh scripts/generate-project.sh
xcodebuild -project PrismNative.xcodeproj -scheme PrismNative-UI -destination 'platform=macOS' CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- test
```

Expected: PASS for real-state mapping, matching localization keys, keyboard access, VoiceOver labels, and injected contrast/motion variants. Real VoiceOver, Increased Contrast, and Reduce Motion evidence remains a required Task 18 physical check.

```bash
git add native/PrismNative/Features/Settings native/PrismNative/Resources native/PrismNativeTests/SettingsViewModelTests.swift native/PrismNativeUITests/AccessibilityUITests.swift
git commit -m "feat(native): add settings and localization"
```

---

## Phase D — Updates, End-to-End Verification, and Release

### Task 17: Integrate Signed Sparkle Updates

**Files:**
- Create: `native/PrismNative/Updates/UpdateController.swift`
- Create: `native/PrismNative/Updates/UpdateState.swift`
- Create: `native/PrismNative/Updates/SparkleUpdateDriver.swift`
- Create: `native/PrismNative/Updates/ObservableSparkleUserDriver.swift`
- Create: `native/PrismNativeTests/UpdateControllerTests.swift`
- Create: `native/UpdateFixtures/build-local-update-fixtures.sh`
- Create: `native/UpdateFixtures/run-local-update-test.sh`
- Create: `native/scripts/prepare-sparkle-tools.sh`
- Modify: `native/project.yml`
- Modify: `native/PrismNative/Resources/Info.plist`
- Modify: `native/PrismNative/App/AppEnvironment.swift`
- Modify: `native/PrismNative/App/PrismNativeApp.swift`
- Modify: `native/PrismNative/MenuBar/StatusItemController.swift`
- Modify: `native/PrismNative/Features/Settings/SettingsViewModel.swift`

**Interfaces:**
- Consumes: Sparkle 2.9.4 `SPUUpdater` and `SPUUserDriver`.
- Produces: event-driven `SparkleUpdateDriver`, observable `UpdateState`, visible user choices, and user-initiated `checkForUpdates()`.

- [ ] **Step 1: Write failing update-state mapping tests**

```swift
@Test @MainActor func signatureFailureNeverBecomesReady() async {
    let checker = StubUpdateChecker(events: [.checking, .failed(.signatureVerification)])
    let controller = UpdateController(checker: checker)
    controller.startObserving()
    checker.checkForUpdates()
    await checker.finishYielding()
    #expect(controller.state == .failed(.signatureVerification))
    #expect(controller.state != .readyToInstall)
}

@Test @MainActor func streamedProgressReachesReadyState() async {
    let checker = StubUpdateChecker(events: [
        .checking,
        .available(version: "1.1.0"),
        .downloading(progress: 0.5),
        .extracting(progress: 1.0),
        .readyToInstall
    ])
    let controller = UpdateController(checker: checker)
    controller.startObserving()
    checker.checkForUpdates()
    await checker.finishYielding()
    #expect(controller.state == .readyToInstall)
}

@Test @MainActor func liveCompositionSharesOneSparkleControllerAcrossSurfaces() throws {
    let environment = try AppEnvironment.fixture(updateMode: .sparkle)
    #expect(environment.settings.updateController === environment.statusItem.updateController)
    #expect(environment.updateChecker is SparkleUpdateDriver)

    let preview = AppEnvironment.preview
    #expect(preview.updateChecker is DisabledUpdateChecker)
}
```

- [ ] **Step 2: Run and verify failure**

Run: `cd native && zsh scripts/generate-project.sh && xcodebuild -project PrismNative.xcodeproj -scheme PrismNative-Unit -destination 'platform=macOS' -only-testing:PrismNativeTests CODE_SIGNING_ALLOWED=NO test`

Expected: FAIL because the update controller does not exist.

- [ ] **Step 3: Implement observable Sparkle state**

`UpdateController` consumes the Task 5 event stream and exposes `.idle`, `.checking`, `.current`, `.available(version:)`, `.downloading(progress:)`, `.extracting(progress:)`, `.readyToInstall`, `.installed(relaunched:)`, and `.failed(reason:)`. `StubUpdateChecker` is a same-file test implementation that yields deterministic events without network or installation side effects.

Add Sparkle to `project.yml` as an exact 2.9.4 package dependency in this task. `SparkleUpdateDriver` strongly owns an `ObservableSparkleUserDriver`, an `SPUUpdaterDelegate`, and `SPUUpdater(hostBundle:applicationBundle:userDriver:delegate:)`; call `start()` once and map `canCheckForUpdates` plus `automaticallyChecksForUpdates` directly to the updater. The user driver conforms to every required `SPUUserDriver` callback, presents Prism's update sheet, retains and invokes Sparkle's cancellation/reply closures, and yields checking, found version, expected/downloaded byte progress, extraction progress, ready, installed, cancelled, and typed error events. It supports release notes, information-only updates, authorization prompts, Skip, Later, Install, retry termination, and show-in-focus. It never chooses Install without an explicit user action and never enables automatic download/install.

`AppEnvironment.live` constructs and strongly owns exactly one `SparkleUpdateDriver` plus one `UpdateController`. The controller is the only consumer of the driver's `AsyncStream`; Settings and the status item observe and invoke that same controller instance, so events are never split between multiple consumers. `AppEnvironment.preview` and UI-test launch modes use `DisabledUpdateChecker`. Modify the formal composition files in this task and require the composition test above to pass; creating Sparkle types without replacing the live disabled driver is not completion.

- [ ] **Step 4: Configure feed and keys without committing secrets**

Keep `SUFeedURL` fixed to `https://github.com/Halewwang/Prism-Browser-switching/releases/latest/download/appcast.xml`, set `SUPublicEDKey` to `$(SPARKLE_PUBLIC_ED_KEY)`, `SUEnableAutomaticChecks` to true, `SUAllowsAutomaticUpdates` to false, and `SUAutomaticallyUpdate` to false. Generate the production EdDSA key with Sparkle's `generate_keys` on the release operator account, store its private half only in the account Keychain and CI encrypted secret, and supply it to `generate_appcast --ed-key-file -` through standard input. Commit only the public key build value. Release configuration fails before archive when key inputs are empty.

`prepare-sparkle-tools.sh` downloads the official `Sparkle-for-Swift-Package-Manager.zip` for 2.9.4 from `https://github.com/sparkle-project/Sparkle/releases/download/2.9.4/Sparkle-for-Swift-Package-Manager.zip`, verifies SHA-256 `cb6fdbdc8884f15d62a616e79face92b08322410fd2d425edc6596ccbf4ba3b0`, extracts into ignored `native/.tools/sparkle/2.9.4/`, normalizes the release's `generate_appcast`, `generate_keys`, and `sign_update` executables into a local `bin/`, verifies all three are executable, and prints the absolute tool root. It refuses a mismatched cached archive. Fixture, local, CI, and release scripts derive absolute tool paths from this output; they never call an unqualified Sparkle tool from the user's `PATH`.

- [ ] **Step 5: Verify update paths**

Run:

```bash
cd native
sparkle_tools="$(zsh scripts/prepare-sparkle-tools.sh)"
zsh scripts/generate-project.sh
xcodebuild -project PrismNative.xcodeproj -scheme PrismNative-Unit -destination 'platform=macOS' -only-testing:PrismNativeTests CODE_SIGNING_ALLOWED=NO test
SPARKLE_TOOLS_ROOT="$sparkle_tools" zsh UpdateFixtures/build-local-update-fixtures.sh
SPARKLE_TOOLS_ROOT="$sparkle_tools" zsh UpdateFixtures/run-local-update-test.sh
```

The fixture script creates temporary test-only EdDSA keys, builds ad-hoc signed 1.0 and 1.1 fixture apps, generates a valid appcast and a second appcast whose package signature is deliberately invalid, and serves them from `http://127.0.0.1` using a Debug-only local-network exception. The integration script launches the old fixture app and verifies no-update, valid download/install/relaunch, invalid EdDSA rejection, network failure, cancellation, and retry. It asserts the invalid update leaves the old bundle executable and provides the official release URL. No test key, built fixture, or private key is committed. Task 19 repeats the valid update test with Developer ID/notarized release artifacts.

- [ ] **Step 6: Commit update integration**

```bash
git add native/PrismNative/Updates native/PrismNativeTests/UpdateControllerTests.swift native/UpdateFixtures native/scripts/prepare-sparkle-tools.sh native/project.yml native/PrismNative/Resources/Info.plist native/PrismNative/App native/PrismNative/MenuBar/StatusItemController.swift native/PrismNative/Features/Settings/SettingsViewModel.swift .gitignore
git commit -m "feat(native): add signed Sparkle updates"
```

### Task 18: Add End-to-End, Multi-Display, Accessibility, and Recovery Tests

**Files:**
- Create: `native/PrismNativeUITests/LinkRoutingUITests.swift`
- Create: `native/PrismNativeUITests/MultiDisplayChecklist.md`
- Create: `native/PrismNativeTests/EndToEndRoutingTests.swift`
- Modify: `native/PrismNative/Resources/SupportedSources.json`
- Create: `native/docs/release-acceptance.md`

**Interfaces:**
- Consumes: complete native application.
- Produces: automated proof for routing story and manual evidence for hardware-dependent scenarios.

- [ ] **Step 1: Write the end-to-end integration test first**

```swift
@Test @MainActor func failedLaunchStaysRecoverableThenSucceedsOnce() async throws {
    let harness = RoutingHarness(firstLaunchFails: true, secondLaunchSucceeds: true)
    let request = try await harness.receive("https://example.com/work")

    await harness.select(browser: "com.apple.Safari")
    #expect(harness.history(request.id)?.result == .failure)
    #expect(await harness.queue.next()?.id == request.id)

    await harness.select(browser: "com.google.Chrome")
    #expect(harness.history(request.id)?.result == .success)
    #expect(harness.historyEntries.filter { $0.requestID == request.id }.count == 1)
    #expect(await harness.queue.next() == nil)
}
```

Define `RoutingHarness` in `EndToEndRoutingTests.swift` as the composition root for an in-memory pending store, queue, rule repository, history repository, browser catalog, and deterministic launcher. `firstLaunchFails` makes only attempt one throw; `secondLaunchSucceeds` makes attempt two complete. `receive` must call the real `LinkIntakeService.capture` and await `drainForTesting`; `select` must call the same selector action path used by the application. Do not duplicate routing logic inside the harness.

- [ ] **Step 2: Run and verify failure against any missing integration wiring**

Run `EndToEndRoutingTests`; the expected failure identifies the first unconnected boundary. Connect only that boundary and repeat until the story passes.

- [ ] **Step 3: Add automated lifecycle and rapid-link tests**

Cover cold start, running app, hidden main window, login launch, 20 sequential URLs, 10 rapid different URLs, cancel, missing browser, corrupt SwiftData, corrupt recovery journal, History disabled, paused automatic rules, and History upsert failure before attempt, after failed handoff, after successful handoff, and after cancellation. Give the pending-store fake a deterministic “fail on save N” mode and test failure while saving `.launching`, `.presenting`, the succeeded/cancelled terminal record, and journal compaction. Assert browser handoff count, current-session presentation, durable restart state, URL retention/removal, and that storage recovery retries persistence only. Inject termination before handoff, during handoff, after successful handoff but before terminal journal save, after terminal journal save but before History upsert, and after History upsert but before journal compaction. Assert no uncertain attempt is automatically replayed, terminal attempts never block the next request, and neither History nor recovery-store failure causes a second browser handoff.

- [ ] **Step 4: Add UI automation**

Use a test-only URL intake launch argument and injectable stub browsers so XCUITest can drive the real selector without changing the user's defaults or launching personal browsers. Verify Figma dimensions, the actual first three card frames fully visible, exactly 50% of the fourth visible, fifth initially hidden, offscreen selection auto-reveal, arrow keys, numbers, Enter, Escape, Cancel, no-browser recovery, failed handoff, and outcome-unknown recovery. Automate drag scrolling and synthetic precise/non-precise scroll events; record separate physical Trackpad horizontal swipe, conventional mouse wheel, and click-drag results because XCUITest alone cannot prove hardware behavior.

- [ ] **Step 5: Execute physical source and display matrices**

For each installed source application and cold/warm state, run at least 20 attempts on every macOS major version claimed by that manifest entry. Mark a bundle ID eligible only with zero false attribution and at least 95% confirmed attribution. Generate `SupportedSources.json` from approved matrix rows, including exact verified OS range and aggregate counts, then run fresh-install, unlisted-source, out-of-range-OS, and revoked-source tests against the bundled file. Commit anonymized totals without personal URLs or message content. Record real display evidence for main/right/left-negative/above/mixed-scale layouts with Dock bottom/left/right. Each display row records system version, arrangement, request count, duplicates, losses, panel bounds, and result. Untested or failed source applications remain unavailable in source-rule pickers.

Capture History, Rules, Browsers, and Settings in light and dark appearances for normal, empty, and recovery states. Manually record VoiceOver reading order, real Increased Contrast, real Reduce Motion, keyboard focus order, and absence of color-only status. Capture the Figma selector separately at three and five browsers.

- [ ] **Step 6: Run the complete verification suite**

```bash
cd native
swift test
zsh scripts/generate-project.sh
xcodebuild -project PrismNative.xcodeproj -scheme PrismNative-Unit -destination 'platform=macOS' clean test CODE_SIGNING_ALLOWED=NO
zsh scripts/generate-project.sh
xcodebuild -project PrismNative.xcodeproj -scheme PrismNative-UI -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-
zsh scripts/generate-project.sh
xcodebuild -project PrismNative.xcodeproj -scheme PrismNative-Unit -configuration Release CODE_SIGNING_ALLOWED=NO build
```

Expected: all tests pass, zero test failures, Release build completes, and unresolved warnings are documented and fixed before proceeding.

- [ ] **Step 7: Commit full-story verification**

```bash
git add native/PrismNativeTests native/PrismNativeUITests native/PrismNative/Resources/SupportedSources.json native/docs
git commit -m "test(native): verify complete routing story"
```

### Task 19: Build the Signed Universal Release Pipeline

**Files:**
- Create: `native/scripts/package-release.sh`
- Create: `native/scripts/verify-release.sh`
- Create: `native/Config/ExportOptions.plist`
- Create: `.github/workflows/native-release.yml`
- Create: `native/docs/signing-and-release.md`
- Modify: `native/PrismNative/App/PrismNativeApp.swift`
- Modify: `README.md`
- Modify: `RELEASE_GUIDE.md`

**Interfaces:**
- Consumes: validated application, Developer ID identity, notarization credentials, Sparkle EdDSA private key, GitHub release permissions.
- Produces: Universal archive, signed/notarized DMG, signed appcast, and release evidence.

- [ ] **Step 1: Write the release verifier before the packager**

```bash
#!/bin/zsh
set -euo pipefail
app="$1"
dmg="$2"
expected_version="$3"
expected_build="$4"
while IFS= read -r candidate; do
  if file -b "$candidate" | grep -q 'Mach-O'; then
    lipo -verify_arch arm64 x86_64 "$candidate"
  fi
done < <(find "$app/Contents" -type f -print)
codesign --verify --deep --strict --verbose=2 "$app"
codesign --verify --verbose=2 "$dmg"
codesign -d --verbose=4 "$app" 2>&1 | grep -q 'flags=.*runtime'
spctl --assess --type execute --verbose=4 "$app"
spctl --assess --type open --context context:primary-signature --verbose=4 "$dmg"
xcrun stapler validate "$app"
xcrun stapler validate "$dmg"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")" = "$expected_version"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")" = "$expected_build"
```

The verifier mounts the DMG into a `mktemp -d` mount point, finds exactly one `Prism.app`, repeats every architecture/signature/runtime/stapler/Gatekeeper/version assertion against that mounted copy, launches its smoke mode with both `arch -arm64` and `arch -x86_64`, then detaches the image in a trap. `--release-smoke-test` validates the application can load bundled frameworks, read its version and source manifest, construct `AppEnvironment`, and exit 0 without changing defaults, registering a login item, checking updates, or opening a window. Run the verifier against an unsigned Debug app and verify it fails at signature assessment. This proves the gate is active.

- [ ] **Step 2: Implement archive, export, notarization, and DMG creation**

`ExportOptions.plist` uses `method = developer-id`, `signingStyle = automatic`, `stripSwiftSymbols = true`, and `uploadSymbols = false`. The packaging script copies it into the versioned output directory and inserts the required `DEVELOPMENT_TEAM` as `teamID`; it never modifies the committed base file.

`package-release.sh` requires positional version/build values plus non-empty `DEVELOPER_ID_APPLICATION`, `DEVELOPMENT_TEAM`, `NOTARY_PROFILE`, `SPARKLE_PUBLIC_ED_KEY`, and `SPARKLE_ED_PRIVATE_KEY` environment values. It calls the Task 17 preparation script, receives the verified absolute tool root, and refuses to continue unless `bin/generate_appcast`, `bin/generate_keys`, and `bin/sign_update` exist there. Its production sequence is:

```bash
sparkle_tools="$(zsh scripts/prepare-sparkle-tools.sh)"
generate_appcast="$sparkle_tools/bin/generate_appcast"
zsh scripts/generate-project.sh
xcodebuild -project PrismNative.xcodeproj -scheme PrismNative-Unit -destination 'platform=macOS' clean test
zsh scripts/generate-project.sh
xcodebuild -project PrismNative.xcodeproj -scheme PrismNative-Release -configuration Release \
  -archivePath "$archive" archive \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$build" \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  SPARKLE_PUBLIC_ED_KEY="$SPARKLE_PUBLIC_ED_KEY" \
  CODE_SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION"
cp Config/ExportOptions.plist "$runtime_export_options"
/usr/libexec/PlistBuddy -c "Add :teamID string $DEVELOPMENT_TEAM" "$runtime_export_options"
xcodebuild -exportArchive -archivePath "$archive" \
  -exportPath "$export_dir" -exportOptionsPlist "$runtime_export_options"
ditto -c -k --keepParent "$app" "$notary_zip"
xcrun notarytool submit "$notary_zip" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$app"
hdiutil create -volname "Prism" -srcfolder "$app" -ov -format UDZO "$dmg"
codesign --force --sign "$DEVELOPER_ID_APPLICATION" --timestamp "$dmg"
xcrun notarytool submit "$dmg" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$dmg"
zsh scripts/verify-release.sh "$app" "$dmg" "$version" "$build"
```

The script resolves every path under a new version-specific `native/build/release/$version-$build/` directory, refuses to reuse a non-empty output directory, and stops on the first failure. It never reads credentials from repository files.

- [ ] **Step 3: Generate and verify the Sparkle appcast after artifact validation**

After signing/notarization gates pass, place only the verified DMG in a clean appcast input directory and pipe `SPARKLE_ED_PRIVATE_KEY` into `"$generate_appcast" --ed-key-file -`. Set the enclosure URL to the immutable tag asset `https://github.com/Halewwang/Prism-Browser-switching/releases/download/v$version/Prism-$version.dmg`. Parse the generated XML and verify version, build, URL, byte length, and EdDSA signature before any public release. Never write the private key to disk or commit a production appcast to the source tree. The GitHub workflow reruns the preparation script on a clean runner and records the verified Sparkle version and archive digest; it never installs or discovers Sparkle tools from global `PATH`.

- [ ] **Step 4: Implement a draft-first GitHub release workflow**

Workflow order:

1. Test and archive.
2. Sign, notarize, staple, and verify.
3. Create draft GitHub Release tagged `v$version`.
4. Upload `Prism-$version.dmg` and `appcast.xml` as draft assets.
5. Download both draft assets through the authenticated GitHub API; rerun DMG verification and appcast enclosure/signature checks against the downloaded bytes.
6. Publish the GitHub Release once, which atomically makes both the immutable DMG URL and `releases/latest/download/appcast.xml` public.
7. Poll both public URLs, require HTTP 200, and repeat version, byte length, architecture, signature, notarization, and EdDSA checks.

Any failure before step 6 leaves the release as a draft and the prior public feed unchanged. A failure while polling after step 6 is reported as a published-release incident; the workflow never claims it can make an already public GitHub Release invisible. Existing clients continue using the previous latest feed only until GitHub updates the `latest` redirect.

- [ ] **Step 5: Verify fresh install and update recovery on clean accounts**

Test first install, overwrite install, valid update, invalid update signature, interrupted update, uninstall/reinstall, login item approval, and default-handler prompt. Run the final mounted app under arm64 and Rosetta x86_64, and record at least one real Intel Mac or Intel CI result before claiming Intel support. Record target SHA, version/build, every embedded Mach-O architecture result, Gatekeeper results for DMG and app, notarization ID, update result, and public appcast URL in `native/docs/release-acceptance.md`.

- [ ] **Step 6: Update public documentation truthfully**

Document macOS 15+, Universal support, user-controlled default setup, supported source-rule applications from the verified matrix, Unknown behavior, Figma selector behavior, privacy, and signed installation. Remove `sudo xattr` instructions and unsupported claims about regex, profiles, universal precise source detection, and background behavior.

- [ ] **Step 7: Commit release tooling and documentation**

```bash
git add native/scripts native/Config/ExportOptions.plist native/PrismNative/App/PrismNativeApp.swift .github/workflows/native-release.yml native/docs README.md RELEASE_GUIDE.md
git commit -m "build(native): add verified macOS release pipeline"
```

### Task 20: Cut Over from Electron Only After Native Acceptance

**Files:**
- Move: Electron application source into `legacy/electron-prism/` or remove it after tagging the last Electron release
- Modify: root `README.md`
- Modify: root `.gitignore`
- Modify: root release scripts to point to `native/`
- Create: `docs/migrations/native-cutover.md`

**Interfaces:**
- Consumes: completed Task 19 evidence.
- Produces: native-first repository and a recoverable Electron archive/tag.

- [ ] **Step 1: Verify the cutover gate**

Require all Task 18 and 19 evidence: zero lost or automatically repeated links, explicit outcome-unknown recovery at crash boundaries, approved bundled source manifest, Figma comparison, accessibility pass, Universal binaries, Developer ID, notarization, stapling, Gatekeeper, Sparkle update, and published artifact verification. If any item is absent, stop and keep Electron as the active release.

- [ ] **Step 2: Tag the final Electron state without including unrelated worktree changes**

Create an annotated tag only from a reviewed commit containing the intended final Electron state. Never tag the current dirty working tree by assumption.

- [ ] **Step 3: Switch root documentation and commands to native**

The root build, test, run, and release instructions point to `native/`. Preserve Electron source under `legacy/` for one release cycle or in the final Electron tag; do not delete user application data.

- [ ] **Step 4: Test repository onboarding from a clean clone**

On a clean machine/account: install prerequisites, generate the Xcode project, run Swift/core/native tests, build Debug, and verify documentation paths. No command may depend on ignored local files or secrets.

- [ ] **Step 5: Commit the cutover**

```bash
git add README.md .gitignore docs/migrations native legacy
git commit -m "chore: make native Prism the primary app"
```

## Final Verification Checklist

- [ ] `cd native && swift test` passes with zero failures.
- [ ] Generated-project unit tests and separately signed UI tests pass with zero failures and recorded test counts.
- [ ] Release build completes without unresolved warnings.
- [ ] Twenty sequential and ten rapid links have exact counts, order, and one result per request.
- [ ] Every crash boundary either completes once or returns Outcome Unknown; no uncertain handoff is automatically repeated.
- [ ] Cold, warm, hidden-window, login-start, failure, cancellation, History-write failure, and restart flows pass.
- [ ] Source rules are enabled only for applications and macOS versions present in the bundled approved manifest.
- [ ] Selector matches Figma node `4:395` at 425 × 200.
- [ ] More than three browsers show exactly three full items plus half of the fourth; Trackpad, mouse wheel, drag, keyboard, and auto-reveal checks pass.
- [ ] VoiceOver, keyboard-only, light/dark appearance, increased contrast, and Reduce Motion checks pass for selector and all main destinations.
- [ ] Main/right/left-negative/above/mixed-scale display checks pass.
- [ ] Every embedded Mach-O is arm64+x86_64; app and DMG `codesign`, `spctl`, and `stapler` checks pass on the final download and mounted copy.
- [ ] Final app smoke mode passes under arm64 and Rosetta x86_64, plus one real Intel Mac or Intel CI run.
- [ ] Sparkle rejects invalid signatures and installs the validated update.
- [ ] Draft DMG and appcast are verified before one public release; the public `latest/download` feed and immutable DMG are reverified afterward.
- [ ] README and release notes contain no unverified capability claims.
