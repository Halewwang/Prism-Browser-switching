import Foundation
import PrismCore
import Testing
@testable import PrismNative

@Test @MainActor func senderPIDCopiesSigned32BitValueFromDescriptor() {
    let descriptor = StubAppleEventDescriptor(.signedInteger(4_242))

    #expect(AppleEventSenderReader.copySenderPID(from: descriptor) == 4_242)
}

@Test @MainActor func senderPIDRejectsMissingAndUnreadableDescriptors() {
    #expect(AppleEventSenderReader.copySenderPID(from: StubAppleEventDescriptor(.missing)) == nil)
    #expect(AppleEventSenderReader.copySenderPID(from: StubAppleEventDescriptor(.descriptorReadFailed)) == nil)
}

@Test @MainActor func senderPIDRejectsWrongDescriptorType() {
    #expect(AppleEventSenderReader.copySenderPID(from: StubAppleEventDescriptor(.wrongType)) == nil)
}

@Test @MainActor func senderPIDRejectsOutOfRangeValues() {
    #expect(AppleEventSenderReader.copySenderPID(from: StubAppleEventDescriptor(.signedInteger(Int64(Int32.max) + 1))) == nil)
    #expect(AppleEventSenderReader.copySenderPID(from: StubAppleEventDescriptor(.signedInteger(Int64(Int32.min) - 1))) == nil)
}

@Test @MainActor func resolvedPIDWithValidNonPrismBundleIsConfirmed() {
    let resolver = SourceAttributionProvider(
        runningApplications: StubRunningApplications(applications: [
            42: SourceApplication(bundleIdentifier: "com.tinyspeck.slackmacgap", displayName: "Slack", confidence: .unknown)
        ]),
        prismBundleIdentifier: "com.prism.app"
    )

    let result = resolver.resolve(senderPID: 42, lastActivated: nil)

    #expect(result == SourceApplication(bundleIdentifier: "com.tinyspeck.slackmacgap", displayName: "Slack", confidence: .confirmed))
}

@Test @MainActor func unknownPIDNeverFallsBackToAnUnrelatedVisibleApplication() {
    let slack = SourceApplication(bundleIdentifier: "com.tinyspeck.slackmacgap", displayName: "Slack", confidence: .low)
    let resolver = SourceAttributionProvider(
        runningApplications: StubRunningApplications(applications: [:]),
        prismBundleIdentifier: "com.prism.app"
    )

    let result = resolver.resolve(senderPID: 999_999, lastActivated: slack)

    #expect(result.displayName == "Unknown")
    #expect(result.bundleIdentifier == nil)
    #expect(result.confidence == .unknown)
}

@Test @MainActor func lastActivationIsLowConfidenceInferenceOnlyWhenNoPIDExists() {
    let slack = SourceApplication(bundleIdentifier: "com.tinyspeck.slackmacgap", displayName: "Slack", confidence: .confirmed)
    let resolver = SourceAttributionProvider(
        runningApplications: StubRunningApplications(applications: [:]),
        prismBundleIdentifier: "com.prism.app"
    )

    let result = resolver.resolve(senderPID: nil, lastActivated: slack)

    #expect(result == SourceApplication(bundleIdentifier: "com.tinyspeck.slackmacgap", displayName: "Slack", confidence: .low))
}

@Test @MainActor func prismAndBundlelessPIDCandidatesNeverBecomeConfirmed() {
    let resolver = SourceAttributionProvider(
        runningApplications: StubRunningApplications(applications: [
            1: SourceApplication(bundleIdentifier: "com.prism.app", displayName: "Prism", confidence: .unknown),
            2: SourceApplication(bundleIdentifier: "", displayName: "Bundleless", confidence: .unknown)
        ]),
        prismBundleIdentifier: "com.prism.app"
    )

    #expect(resolver.resolve(senderPID: 1, lastActivated: nil) == .unknown)
    #expect(resolver.resolve(senderPID: 2, lastActivated: nil) == .unknown)
}

@Test @MainActor func inactiveOrTerminatedApplicationsCannotResolveToSources() {
    let inactive = RunningApplicationSnapshot(
        bundleIdentifier: "com.apple.Safari",
        displayName: "Safari",
        isActive: false,
        isTerminated: false
    )
    let terminated = RunningApplicationSnapshot(
        bundleIdentifier: "com.google.Chrome",
        displayName: "Chrome",
        isActive: true,
        isTerminated: true
    )
    let lookup = SystemRunningApplicationLookup(
        inspector: StubRunningApplicationInspector(snapshots: [42: inactive, 43: terminated])
    )

    #expect(lookup.sourceApplication(processIdentifier: 42) == nil)
    #expect(lookup.sourceApplication(processIdentifier: 43) == nil)
}

@Test @MainActor func activationTrackerRecordsOnlyObservedNonPrismActivationsIncludingTerminal() {
    let observer = StubActivationObserver()
    let tracker = ApplicationActivationTracker(observer: observer, prismBundleIdentifier: "com.prism.app")
    let terminal = SourceApplication(bundleIdentifier: "com.apple.Terminal", displayName: "Terminal", confidence: .unknown)

    #expect(tracker.lastActivatedApplication == nil)
    observer.emit(terminal)

    #expect(tracker.lastActivatedApplication == terminal)
}

@Test @MainActor func activationTrackerIgnoresPrismWithoutDiscardingLastExternalApplication() {
    let observer = StubActivationObserver()
    let tracker = ApplicationActivationTracker(observer: observer, prismBundleIdentifier: "com.prism.app")
    let safari = SourceApplication(bundleIdentifier: "com.apple.Safari", displayName: "Safari", confidence: .unknown)
    let prism = SourceApplication(bundleIdentifier: "com.prism.app", displayName: "Prism", confidence: .unknown)

    observer.emit(safari)
    observer.emit(prism)

    #expect(tracker.lastActivatedApplication == safari)
}

@Test @MainActor func activationTrackerStopsItsObserverAndNoLongerAcceptsEvents() {
    let observer = StubActivationObserver()
    let tracker = ApplicationActivationTracker(observer: observer, prismBundleIdentifier: "com.prism.app")
    let safari = SourceApplication(bundleIdentifier: "com.apple.Safari", displayName: "Safari", confidence: .unknown)

    tracker.stop()
    observer.emit(safari)

    #expect(observer.removeCount == 1)
    #expect(tracker.lastActivatedApplication == nil)
}

@Test func freshInstallUsesOnlyBundledApprovedSourcesForCurrentOS() throws {
    let json = Data(#"""
    {"schemaVersion":1,"sources":[{"bundleIdentifier":"com.tinyspeck.slackmacgap","minimumMacOS":"15.0.0","maximumMacOS":"15.9.99","coldSamples":20,"warmSamples":20,"confirmedCount":40,"falseAttributionCount":0,"validatedAt":"2026-08-12T00:00:00Z"}]}
    """#.utf8)
    let manifest = try SourceSupportManifest.decode(json)

    #expect(manifest.eligibleBundleIDs(for: OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0)) == ["com.tinyspeck.slackmacgap"])
    #expect(manifest.eligibleBundleIDs(for: OperatingSystemVersion(majorVersion: 15, minorVersion: 9, patchVersion: 99)) == ["com.tinyspeck.slackmacgap"])
    #expect(manifest.eligibleBundleIDs(for: OperatingSystemVersion(majorVersion: 16, minorVersion: 0, patchVersion: 0)).isEmpty)
}

@Test func bundledManifestStartsWithNoEligibleSources() {
    let manifest = SourceSupportManifest.bundled(in: .main)

    #expect(manifest.eligibleBundleIDs(for: OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0)).isEmpty)
}

@Test func manifestLoaderFailsClosedWhenBundledDataCannotBeDecoded() {
    let manifest = SourceSupportManifest.loadBundled(resourceData: Data("not json".utf8))

    #expect(manifest.eligibleBundleIDs(for: OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0)).isEmpty)
}

@Test func manifestRejectsMalformedAndWrongSchema() {
    expectManifestRejection(Data("not json".utf8))
    expectManifestRejection(manifestData(schemaVersion: 2, sources: []))
}

@Test func manifestRejectsDuplicateBlankAndInsufficientEvidenceEntries() {
    let valid = validatedSource()
    expectManifestRejection(manifestData(sources: [valid, valid]))
    expectManifestRejection(manifestData(sources: [validatedSource(bundleIdentifier: "  ")]))
    expectManifestRejection(manifestData(sources: [validatedSource(coldSamples: 19)]))
    expectManifestRejection(manifestData(sources: [validatedSource(warmSamples: 19)]))
    expectManifestRejection(manifestData(sources: [validatedSource(confirmedCount: 39)]))
    expectManifestRejection(manifestData(sources: [validatedSource(coldSamples: 21, warmSamples: 20, confirmedCount: 40)]))
    expectManifestRejection(manifestData(sources: [validatedSource(falseAttributionCount: 1)]))
    expectManifestRejection(manifestData(sources: [validatedSource(coldSamples: 0)]))
}

@Test func manifestRejectsInvalidDatesAndOperatingSystemBounds() {
    expectManifestRejection(manifestData(sources: [validatedSource(minimumMacOS: "invalid")]))
    expectManifestRejection(manifestData(sources: [validatedSource(maximumMacOS: "15.0")]))
    expectManifestRejection(manifestData(sources: [validatedSource(minimumMacOS: "15.1.0", maximumMacOS: "15.0.0")]))
    expectManifestRejection(manifestData(sources: [validatedSource(validatedAt: "not-a-date")]))
}

@Test func manifestNeverMakesUnlistedOrOutOfRangeSourcesEligible() throws {
    let manifest = try SourceSupportManifest.decode(manifestData(sources: [validatedSource()]))

    #expect(!manifest.eligibleBundleIDs(for: OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0)).contains("com.example.unlisted"))
    #expect(manifest.eligibleBundleIDs(for: OperatingSystemVersion(majorVersion: 14, minorVersion: 9, patchVersion: 9)).isEmpty)
}

private func expectManifestRejection(_ data: Data, sourceLocation: SourceLocation = #_sourceLocation) {
    do {
        _ = try SourceSupportManifest.decode(data)
        Issue.record("Expected manifest to be rejected", sourceLocation: sourceLocation)
    } catch {
        // Rejection is the expected fail-closed result.
    }
}

private func manifestData(schemaVersion: Int = 1, sources: [[String: Any]]) -> Data {
    try! JSONSerialization.data(withJSONObject: ["schemaVersion": schemaVersion, "sources": sources], options: [.sortedKeys])
}

private func validatedSource(
    bundleIdentifier: String = "com.tinyspeck.slackmacgap",
    minimumMacOS: String = "15.0.0",
    maximumMacOS: String = "15.9.99",
    coldSamples: Int = 20,
    warmSamples: Int = 20,
    confirmedCount: Int = 40,
    falseAttributionCount: Int = 0,
    validatedAt: String = "2026-08-12T00:00:00Z"
) -> [String: Any] {
    [
        "bundleIdentifier": bundleIdentifier,
        "minimumMacOS": minimumMacOS,
        "maximumMacOS": maximumMacOS,
        "coldSamples": coldSamples,
        "warmSamples": warmSamples,
        "confirmedCount": confirmedCount,
        "falseAttributionCount": falseAttributionCount,
        "validatedAt": validatedAt
    ]
}

@MainActor
private final class StubAppleEventDescriptor: AppleEventSenderPIDDescriptorReading {
    let result: AppleEventSenderPIDAttribute

    init(_ result: AppleEventSenderPIDAttribute) {
        self.result = result
    }

    func senderPIDAttribute() -> AppleEventSenderPIDAttribute {
        result
    }
}

@MainActor
private final class StubRunningApplications: RunningApplicationLookup {
    private let applications: [Int32: SourceApplication]

    init(applications: [Int32: SourceApplication]) {
        self.applications = applications
    }

    func sourceApplication(processIdentifier: Int32) -> SourceApplication? {
        applications[processIdentifier]
    }
}

@MainActor
private final class StubRunningApplicationInspector: RunningApplicationInspecting {
    private let snapshots: [Int32: RunningApplicationSnapshot]

    init(snapshots: [Int32: RunningApplicationSnapshot]) {
        self.snapshots = snapshots
    }

    func snapshot(processIdentifier: Int32) -> RunningApplicationSnapshot? {
        snapshots[processIdentifier]
    }
}

@MainActor
private final class StubActivationObserver: ApplicationActivationObserving {
    private var handler: (@MainActor @Sendable (SourceApplication?) -> Void)?
    private var token: NSObject?
    private(set) var removeCount = 0

    func observeActivations(_ handler: @escaping @MainActor @Sendable (SourceApplication?) -> Void) -> NSObjectProtocol {
        self.handler = handler
        let token = NSObject()
        self.token = token
        return token
    }

    func removeObserver(_ observer: NSObjectProtocol) {
        if observer === token {
            removeCount += 1
            handler = nil
            token = nil
        }
    }

    func emit(_ application: SourceApplication?) {
        handler?(application)
    }
}
