import AppKit
import Carbon
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
    #expect(AppleEventSenderPIDDecoder.attribute(descriptorType: DescType(typeType), int32Value: 42) == .wrongType)
}

@Test @MainActor func senderPIDAcceptsKernelProcessIDDescriptors() {
    #expect(
        AppleEventSenderPIDDecoder.attribute(descriptorType: DescType(typeKernelProcessID), int32Value: 88)
            == .signedInteger(88)
    )
    #expect(
        AppleEventSenderPIDDecoder.attribute(descriptorType: DescType(typeSInt32), int32Value: 88)
            == .signedInteger(88)
    )
    var unsignedPID = UInt32(72_110).littleEndian
    let data = Data(bytes: &unsignedPID, count: MemoryLayout<UInt32>.size)
    #expect(
        AppleEventSenderPIDDecoder.attribute(descriptorType: DescType(typeUInt32), int32Value: 0, data: data)
            == .signedInteger(72_110)
    )
}

@Test @MainActor func currentSenderPIDUsesCarbonValueWhenTheNSEventIsMissing() {
    #expect(AppleEventSenderReader.copySenderPID(nsEvent: nil, carbonPID: 77) == 77)
    #expect(AppleEventSenderReader.copySenderPID(nsEvent: nil, carbonPID: nil) == nil)
    #expect(AppleEventSenderReader.copySenderPID(nsEvent: nil, carbonPID: 0) == nil)
}

@Test @MainActor func getURLEventReadsTheDirectURLAndKernelProcessID() throws {
    let event = NSAppleEventDescriptor(
        eventClass: AEEventClass(kInternetEventClass),
        eventID: AEEventID(kAEGetURL),
        targetDescriptor: nil,
        returnID: AEReturnID(kAutoGenerateReturnID),
        transactionID: AETransactionID(kAnyTransactionID)
    )
    event.setParam(NSAppleEventDescriptor(string: "https://example.com/a"), forKeyword: keyDirectObject)
    var pid = Int32(88).bigEndian
    let pidData = Data(bytes: &pid, count: MemoryLayout<Int32>.size)
    let pidDescriptor = try #require(NSAppleEventDescriptor(descriptorType: DescType(typeKernelProcessID), data: pidData))

    #expect(GetURLEvent.urls(in: event) == [URL(string: "https://example.com/a")!])
    #expect(
        AppleEventSenderPIDDecoder.attribute(
            descriptorType: pidDescriptor.descriptorType,
            int32Value: pidDescriptor.int32Value,
            data: pidDescriptor.data
        ) == .signedInteger(88)
    )
}

@Test func claimedGetURLDoesNotOpenASecondTime() {
    var claimed = ClaimedLinkOpens()
    let url = URL(string: "https://example.com/a")!

    let firstClaim = claimed.claim(url)
    let secondClaim = claimed.claim(url)
    let firstConsume = claimed.consume(url)
    let secondConsume = claimed.consume(url)

    #expect(firstClaim)
    #expect(!secondClaim)
    #expect(firstConsume)
    #expect(!secondConsume)
}

@Test @MainActor func unsignedSenderPIDUsesTheCoercedInteger() throws {
    var pid = UInt32(1_603).littleEndian
    let data = Data(bytes: &pid, count: MemoryLayout<UInt32>.size)
    let attribute = try #require(
        NSAppleEventDescriptor(descriptorType: DescType(typeUInt32), data: data)
    )

    #expect(AppleEventSenderReader.pid(from: attribute) == 1_603)
}

@Test @MainActor func bundlelessHelperPIDConfirmsTheParentApplication() {
    let resolver = SourceAttributionProvider(
        runningApplications: StubRunningApplications(applications: [
            1332: SourceApplication(bundleIdentifier: "com.electron.lark", displayName: "飞书", confidence: .unknown)
        ]),
        processAncestry: StubProcessAncestry(parents: [1603: 1332]),
        prismBundleIdentifier: "com.prism.app"
    )

    #expect(resolver.resolve(senderPID: 1603, lastActivated: nil) == SourceApplication(
        bundleIdentifier: "com.electron.lark",
        displayName: "飞书",
        confidence: .confirmed
    ))
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

@Test @MainActor func teamPrefixedSenderPIDIsConfirmedAsTheApplicationBundle() {
    let resolver = SourceAttributionProvider(
        runningApplications: StubRunningApplications(applications: [
            42: SourceApplication(
                bundleIdentifier: "5ZSL2CJU2T.com.dingtalk.mac",
                displayName: "DingTalk",
                confidence: .unknown
            )
        ]),
        prismBundleIdentifier: "com.prism.app"
    )

    let result = resolver.resolve(senderPID: 42, lastActivated: nil)

    #expect(result == SourceApplication(
        bundleIdentifier: "com.dingtalk.mac",
        displayName: "DingTalk",
        confidence: .confirmed
    ))
}

@Test @MainActor func helperAndBundlelessSendersConfirmTheirHostApplication() {
    let resolver = SourceAttributionProvider(
        runningApplications: StubRunningApplications(applications: [
            10: SourceApplication(bundleIdentifier: "com.larksuite.larkApp.helper", displayName: "Lark Helper", confidence: .unknown),
            11: SourceApplication(bundleIdentifier: "com.larksuite.larkApp", displayName: "Lark", confidence: .unknown),
            20: SourceApplication(bundleIdentifier: "", displayName: "Bundleless", confidence: .unknown),
            21: SourceApplication(bundleIdentifier: "com.electron.lark", displayName: "Feishu", confidence: .unknown)
        ]),
        processAncestry: StubProcessAncestry(parents: [10: 11, 20: 21]),
        prismBundleIdentifier: "com.prism.app"
    )

    #expect(resolver.resolve(senderPID: 10, lastActivated: nil) == SourceApplication(
        bundleIdentifier: "com.larksuite.larkApp",
        displayName: "Lark",
        confidence: .confirmed
    ))
    #expect(resolver.resolve(senderPID: 20, lastActivated: nil) == SourceApplication(
        bundleIdentifier: "com.electron.lark",
        displayName: "Feishu",
        confidence: .confirmed
    ))
}

@Test @MainActor func helperWithoutAHostConfirmsTheBundleWithTheHelperSuffixRemoved() {
    let resolver = SourceAttributionProvider(
        runningApplications: StubRunningApplications(applications: [
            10: SourceApplication(bundleIdentifier: "com.larksuite.larkApp.helper.renderer", displayName: "Lark Helper", confidence: .unknown)
        ]),
        processAncestry: StubProcessAncestry(parents: [:]),
        prismBundleIdentifier: "com.prism.app"
    )

    #expect(resolver.resolve(senderPID: 10, lastActivated: nil) == SourceApplication(
        bundleIdentifier: "com.larksuite.larkApp",
        displayName: "Lark Helper",
        confidence: .confirmed
    ))
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

@Test @MainActor func backgroundSendersResolveAndTerminatedApplicationsDoNot() {
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

    #expect(lookup.sourceApplication(processIdentifier: 42) == SourceApplication(
        bundleIdentifier: "com.apple.Safari",
        displayName: "Safari",
        confidence: .unknown
    ))
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
    tracker.stop()
    observer.emit(safari)

    #expect(observer.removeCount == 1)
    #expect(tracker.lastActivatedApplication == nil)
}

@Test func activationTrackerSafelyCleansItsObserverWhenReleasedOffMainActor() async {
    let observer = await MainActor.run { StubActivationObserver() }

    await Task.detached { @Sendable in
        let tracker = await MainActor.run {
            ApplicationActivationTracker(observer: observer, prismBundleIdentifier: "com.prism.app")
        }
        withExtendedLifetime(tracker) {}
    }.value
    await observer.waitForRemoval()

    let removeCount = await MainActor.run { observer.removeCount }
    #expect(removeCount == 1)
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

@Test func manifestLoaderFailsClosedWithoutTrappingOnOverflowingSampleTotals() {
    let maxPlusTwenty = manifestData(sources: [
        validatedSource(coldSamples: Int.max, warmSamples: 20, confirmedCount: Int.max)
    ])
    let maxPlusMax = manifestData(sources: [
        validatedSource(coldSamples: Int.max, warmSamples: Int.max, confirmedCount: Int.max)
    ])

    let firstResult = SourceSupportManifest.loadBundled(resourceData: maxPlusTwenty)
    let secondResult = SourceSupportManifest.loadBundled(resourceData: maxPlusMax)

    #expect(firstResult == .disabled)
    #expect(secondResult == .disabled)
}

@Test func manifestLoaderStillDisablesInsufficientEvidenceAndAcceptsValidEvidence() {
    let insufficient = manifestData(sources: [validatedSource(coldSamples: 19, confirmedCount: 39)])
    let valid = manifestData(sources: [validatedSource()])

    #expect(SourceSupportManifest.loadBundled(resourceData: insufficient) == .disabled)
    #expect(
        SourceSupportManifest.loadBundled(resourceData: valid)
            .eligibleBundleIDs(for: OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0))
            == ["com.tinyspeck.slackmacgap"]
    )
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
private final class StubProcessAncestry: ProcessAncestryProviding {
    private let parents: [Int32: Int32]

    init(parents: [Int32: Int32]) {
        self.parents = parents
    }

    func parentProcessIdentifier(of processIdentifier: Int32) -> Int32? {
        parents[processIdentifier]
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
    private var removalContinuations: [CheckedContinuation<Void, Never>] = []
    private(set) var removeCount = 0

    func observeActivations(_ handler: @escaping @MainActor @Sendable (SourceApplication?) -> Void) -> NSObjectProtocol {
        self.handler = handler
        let token = NSObject()
        self.token = token
        return token
    }

    func removeObserver(_ observer: NSObjectProtocol) {
        MainActor.preconditionIsolated()
        if observer === token {
            removeCount += 1
            handler = nil
            token = nil
            let continuations = removalContinuations
            removalContinuations = []
            continuations.forEach { $0.resume() }
        }
    }

    func waitForRemoval() async {
        guard removeCount == 0 else { return }

        await withCheckedContinuation { continuation in
            removalContinuations.append(continuation)
        }
    }

    func emit(_ application: SourceApplication?) {
        handler?(application)
    }
}
