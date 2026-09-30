import AppKit
import CoreServices
import Foundation
import PrismCore
import Testing
import XCTest
@testable import PrismNative

@Test @MainActor func catalogDeduplicatesHandlersByBundleIdentifier() async throws {
    let fixtures = try TemporaryApplicationBundles([
        ("Safari.app", "com.apple.Safari"),
        ("Safari Copy.app", "com.apple.Safari"),
        ("Google Chrome.app", "com.google.Chrome")
    ])
    defer { fixtures.remove() }

    let workspace = StubWorkspaceClient(applicationURLs: fixtures.urls)
    let catalog = BrowserCatalogService(workspace: workspace, customBrowsers: [], profileDiscovery: ChromiumProfileDiscovery(userDataDirectories: [:]))

    let browsers = try await catalog.scan()

    #expect(browsers.map(\.id) == ["com.apple.Safari", "com.google.Chrome"])
}

@Test @MainActor func catalogUnionsProtocolsNormalizesAliasesAndDiscardsInvalidApplications() async throws {
    let fixtures = try TemporaryApplicationBundles([
        ("Safari.app", "com.apple.Safari"),
        ("Google Chrome.app", "com.google.Chrome"),
        ("Prism.app", "com.prism.app"),
        ("Empty Identifier.app", ""),
        ("Unreadable.app", "com.example.unreadable")
    ])
    defer { fixtures.remove() }

    let safari = fixtures.urls[0]
    let chrome = fixtures.urls[1]
    let prism = fixtures.urls[2]
    let emptyIdentifier = fixtures.urls[3]
    let unreadable = fixtures.urls[4]
    let safariAlias = try fixtures.makeSymbolicLink(named: "Safari Alias.app", to: safari)
    let missing = fixtures.root.appending(path: "Missing.app")
    try fixtures.makeInfoPlistUnreadable(at: unreadable)

    let workspace = StubWorkspaceClient(
        applicationURLsByScheme: [
            "http": [safariAlias, prism, missing, unreadable],
            "https": [safari, chrome, emptyIdentifier]
        ]
    )
    let catalog = BrowserCatalogService(
        workspace: workspace,
        customBrowsers: [],
        prismBundleIdentifier: "com.prism.app",
        profileDiscovery: ChromiumProfileDiscovery(userDataDirectories: [:])
    )

    let browsers = try await catalog.scan()

    #expect(browsers.map(\.id) == ["com.apple.Safari", "com.google.Chrome"])
    #expect(browsers[0].applicationURL == safari.standardizedFileURL)
    #expect(browsers.allSatisfy { $0.availability == .available && $0.origin == .system })
}

@Test @MainActor func catalogMergesValidCustomBrowsersAndAppliesSavedSelectorOrder() async throws {
    let fixtures = try TemporaryApplicationBundles([
        ("Safari.app", "com.apple.Safari"),
        ("Google Chrome.app", "com.google.Chrome"),
        ("Custom Browser.app", "com.example.custom"),
        ("Broken Custom.app", "")
    ])
    defer { fixtures.remove() }

    let custom = browserDescriptor(
        bundleIdentifier: "com.example.custom",
        applicationURL: fixtures.urls[2],
        origin: .custom,
        selectorOrder: 9
    )
    let invalidCustom = browserDescriptor(
        bundleIdentifier: "com.example.broken",
        applicationURL: fixtures.urls[3],
        origin: .custom,
        selectorOrder: 1
    )
    let workspace = StubWorkspaceClient(applicationURLs: [fixtures.urls[0], fixtures.urls[1]])
    let catalog = BrowserCatalogService(
        workspace: workspace,
        customBrowsers: [custom, invalidCustom],
        savedSelectorOrder: ["com.example.custom", "com.google.Chrome", "com.apple.Safari"],
        profileDiscovery: ChromiumProfileDiscovery(userDataDirectories: [:])
    )

    let browsers = try await catalog.scan()

    #expect(browsers.map(\.id) == ["com.example.custom", "com.google.Chrome", "com.apple.Safari"])
    #expect(browsers.map(\.origin) == [.custom, .system, .system])
    #expect(browsers.map(\.selectorOrder) == [0, 1, 2])
}

@Test @MainActor func catalogSavesCustomBrowserOnlyWhenItHandlesHTTPAndHTTPS() throws {
    let fixtures = try TemporaryApplicationBundles([
        ("Custom Browser.app", "com.example.custom")
    ])
    defer { fixtures.remove() }

    let customAlias = try fixtures.makeSymbolicLink(named: "Custom Alias.app", to: fixtures.urls[0])
    let repository = InMemoryBrowserPreferenceRepository()
    let workspace = StubWorkspaceClient(
        applicationURLsByScheme: [
            "http": [customAlias],
            "https": [fixtures.urls[0]]
        ]
    )
    let catalog = BrowserCatalogService(workspace: workspace, browserPreferences: repository, profileDiscovery: ChromiumProfileDiscovery(userDataDirectories: [:]))

    let saved = try catalog.saveCustomBrowser(at: customAlias)

    #expect(saved.id == "com.example.custom")
    #expect(saved.applicationURL == fixtures.urls[0].standardizedFileURL)
    #expect(saved.origin == .custom)
    #expect(saved.availability == .available)
    #expect(try repository.customBrowsers().map(\.id) == ["com.example.custom"])
}

@Test @MainActor func catalogRejectsCustomBrowserThatDoesNotHandleBothWebProtocols() throws {
    let fixtures = try TemporaryApplicationBundles([
        ("Custom Browser.app", "com.example.custom")
    ])
    defer { fixtures.remove() }

    let repository = InMemoryBrowserPreferenceRepository()
    let workspace = StubWorkspaceClient(
        applicationURLsByScheme: [
            "http": [fixtures.urls[0]],
            "https": []
        ]
    )
    let catalog = BrowserCatalogService(workspace: workspace, browserPreferences: repository, profileDiscovery: ChromiumProfileDiscovery(userDataDirectories: [:]))

    #expect(throws: BrowserCatalogError.cannotOpenWebLinks) {
        try catalog.saveCustomBrowser(at: fixtures.urls[0])
    }
    #expect(try repository.customBrowsers().isEmpty)
}

@Test @MainActor func launcherReportsHandoffOnlyAfterWorkspaceAcceptsIt() async throws {
    let fixtures = try TemporaryApplicationBundles([
        ("Safari.app", "com.apple.Safari")
    ])
    defer { fixtures.remove() }

    let workspace = DeferredWorkspaceClient()
    let launcher = BrowserLauncherService(workspace: workspace)
    let browser = browserDescriptor(bundleIdentifier: "com.apple.Safari", applicationURL: fixtures.urls[0])
    var didComplete = false
    let launchTask = Task { @MainActor in
        do {
            didComplete = try await launcher.open(URL(string: "https://example.com")!, with: browser) == .handoffSucceeded
        } catch {
            Issue.record("Expected a successful handoff")
        }
    }

    await Task.yield()
    #expect(workspace.hasPendingOpen)
    #expect(didComplete == false)
    workspace.succeed()
    await launchTask.value

    #expect(didComplete)
}

@Test @MainActor func launcherRejectsUnavailableApplicationsWithoutClaimingSuccess() async throws {
    let workspace = StubWorkspaceClient(applicationURLs: [])
    let launcher = BrowserLauncherService(workspace: workspace)
    let unavailable = browserDescriptor(
        bundleIdentifier: "com.example.missing",
        applicationURL: URL(fileURLWithPath: "/Applications/Missing.app"),
        availability: .unavailable
    )

    do {
        _ = try await launcher.open(URL(string: "https://example.com")!, with: unavailable)
        Issue.record("Expected an unavailable application error")
    } catch let error as BrowserLaunchError {
        guard case .applicationUnavailable = error else {
            Issue.record("Expected BrowserLaunchError.applicationUnavailable")
            return
        }
    }
}

@Test @MainActor func launcherMapsRejectedAndSystemWorkspaceResults() async throws {
    let fixtures = try TemporaryApplicationBundles([
        ("Safari.app", "com.apple.Safari")
    ])
    defer { fixtures.remove() }

    let browser = browserDescriptor(bundleIdentifier: "com.apple.Safari", applicationURL: fixtures.urls[0])
    let rejected = BrowserLauncherService(
        workspace: StubWorkspaceClient(applicationURLs: [], openError: WorkspaceClientError.rejected)
    )
    let system = BrowserLauncherService(
        workspace: StubWorkspaceClient(applicationURLs: [], openError: BrowserServiceTestError.unavailable)
    )

    do {
        _ = try await rejected.open(URL(string: "https://example.com")!, with: browser)
        Issue.record("Expected a rejected handoff error")
    } catch let error as BrowserLaunchError {
        guard case .rejected = error else {
            Issue.record("Expected BrowserLaunchError.rejected")
            return
        }
    }
    do {
        _ = try await system.open(URL(string: "https://example.com")!, with: browser)
        Issue.record("Expected the system workspace error to be surfaced")
    } catch let error as BrowserLaunchError {
        guard case .system = error else {
            Issue.record("Expected BrowserLaunchError.system")
            return
        }
    }
}

@Test @MainActor func iconProviderReadsTheNativeApplicationIcon() {
    let expectedSize = NSSize(width: 48, height: 48)
    let workspace = StubWorkspaceClient(applicationURLs: [], icon: NSImage(size: expectedSize))
    let provider = ApplicationIconProvider(workspace: workspace)

    let icon = provider.icon(for: URL(fileURLWithPath: "/Applications/Safari.app"))

    #expect(icon.size == expectedSize)
}

final class BrowserServiceContractTests: XCTestCase {
    func testWorkspaceCompletionAdapterClassifiesSuccessAndRejections() {
        let adapter = WorkspaceOpenCompletionAdapter()
        let cancelled = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
        let noLaunchPermission = NSError(
            domain: NSOSStatusErrorDomain,
            code: Int(kLSNoLaunchPermissionErr)
        )

        XCTAssertEqual(
            workspaceCompletionCategory(adapter.resolve(didLaunchApplication: true, error: nil)),
            .accepted
        )
        XCTAssertEqual(
            workspaceCompletionCategory(adapter.resolve(didLaunchApplication: false, error: nil)),
            .rejected
        )
        XCTAssertEqual(
            workspaceCompletionCategory(adapter.resolve(didLaunchApplication: false, error: cancelled)),
            .rejected
        )
        XCTAssertEqual(
            workspaceCompletionCategory(
                adapter.resolve(didLaunchApplication: false, error: noLaunchPermission)
            ),
            .rejected
        )
    }

    func testWorkspaceCompletionAdapterClassifiesUnavailableApplicationsAndPreservesUnknownErrors() {
        let adapter = WorkspaceOpenCompletionAdapter()
        let missingApplication = NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError)
        let missingExecutable = NSError(
            domain: NSOSStatusErrorDomain,
            code: Int(kLSNoExecutableErr)
        )
        let unreadableApplication = NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(POSIXErrorCode.EACCES.rawValue)
        )

        for error in [missingApplication, missingExecutable, unreadableApplication] {
            XCTAssertEqual(
                workspaceCompletionCategory(adapter.resolve(didLaunchApplication: false, error: error)),
                .applicationUnavailable
            )
        }

        let originalError = NSError(domain: "com.prism.tests.workspace", code: 73)
        let result = adapter.resolve(didLaunchApplication: false, error: originalError)
        guard case let .failure(.system(error)) = result else {
            return XCTFail("Expected the original unknown error to remain a system error")
        }
        let surfacedError = error as NSError
        XCTAssertEqual(surfacedError.domain, originalError.domain)
        XCTAssertEqual(surfacedError.code, originalError.code)
    }

    func testWorkspaceCompletionAdapterClassifiesIncompatibleApplicationErrors() {
        let adapter = WorkspaceOpenCompletionAdapter()
        let incompatibleErrors = [
            NSError(domain: NSCocoaErrorDomain, code: NSExecutableNotLoadableError),
            NSError(domain: NSCocoaErrorDomain, code: NSExecutableArchitectureMismatchError),
            NSError(domain: NSCocoaErrorDomain, code: NSExecutableRuntimeMismatchError),
            NSError(domain: NSCocoaErrorDomain, code: NSExecutableLoadError),
            NSError(domain: NSCocoaErrorDomain, code: NSExecutableLinkError),
            NSError(domain: NSOSStatusErrorDomain, code: Int(kLSNo32BitEnvironmentErr)),
            NSError(domain: NSOSStatusErrorDomain, code: Int(kLSExecutableIncorrectFormat)),
            NSError(domain: NSOSStatusErrorDomain, code: Int(kLSNoRosettaEnvironmentErr)),
            NSError(domain: NSOSStatusErrorDomain, code: Int(kLSGarbageCollectionUnsupportedErr)),
            NSError(domain: NSOSStatusErrorDomain, code: Int(kLSNoClassicEnvironmentErr))
        ]

        for error in incompatibleErrors {
            XCTAssertEqual(
                workspaceCompletionCategory(adapter.resolve(didLaunchApplication: false, error: error)),
                .applicationUnavailable,
                "Expected \(error.domain) \(error.code) to make the application unavailable"
            )
        }
    }

    func testWorkspaceCompletionAdapterClassifiesKnownUnderlyingErrorsAndPreservesOuterUnknownError() {
        let adapter = WorkspaceOpenCompletionAdapter()
        let incompatibleApplication = NSError(
            domain: NSCocoaErrorDomain,
            code: NSExecutableArchitectureMismatchError
        )
        let unavailableOuterError = NSError(
            domain: "com.prism.tests.outer",
            code: 100,
            userInfo: [NSUnderlyingErrorKey: incompatibleApplication]
        )
        let rejectionOuterError = NSError(
            domain: "com.prism.tests.outer",
            code: 101,
            userInfo: [
                NSUnderlyingErrorKey: NSError(
                    domain: NSCocoaErrorDomain,
                    code: NSUserCancelledError
                )
            ]
        )
        let unknownInnerError = NSError(domain: "com.prism.tests.inner", code: 102)
        let unknownOuterError = NSError(
            domain: "com.prism.tests.outer",
            code: 103,
            userInfo: [NSUnderlyingErrorKey: unknownInnerError]
        )
        let duplicateOuterError = NSError(
            domain: "com.prism.tests.duplicate",
            code: 104,
            userInfo: [
                NSUnderlyingErrorKey: NSError(
                    domain: "com.prism.tests.duplicate",
                    code: 104
                )
            ]
        )

        XCTAssertEqual(
            workspaceCompletionCategory(
                adapter.resolve(didLaunchApplication: false, error: unavailableOuterError)
            ),
            .applicationUnavailable
        )
        XCTAssertEqual(
            workspaceCompletionCategory(
                adapter.resolve(didLaunchApplication: false, error: rejectionOuterError)
            ),
            .rejected
        )
        assertOuterSystemError(
            adapter.resolve(didLaunchApplication: false, error: unknownOuterError),
            expected: unknownOuterError
        )
        assertOuterSystemError(
            adapter.resolve(didLaunchApplication: false, error: duplicateOuterError),
            expected: duplicateOuterError
        )
    }

    func testLauncherMapsWorkspaceFailureCategories() async throws {
        try await Task { @MainActor in
            let fixtures = try TemporaryApplicationBundles([
                ("Safari.app", "com.apple.Safari")
            ])
            defer { fixtures.remove() }

            let browser = browserDescriptor(
                bundleIdentifier: "com.apple.Safari",
                applicationURL: fixtures.urls[0]
            )
            let unavailable = BrowserLauncherService(
                workspace: StubWorkspaceClient(
                    applicationURLs: [],
                    openError: WorkspaceClientError.applicationUnavailable
                )
            )
            let rejected = BrowserLauncherService(
                workspace: StubWorkspaceClient(
                    applicationURLs: [],
                    openError: WorkspaceClientError.rejected
                )
            )
            let originalSystemError = NSError(domain: "com.prism.tests.workspace", code: 91)
            let system = BrowserLauncherService(
                workspace: StubWorkspaceClient(
                    applicationURLs: [],
                    openError: WorkspaceClientError.system(originalSystemError)
                )
            )

            do {
                _ = try await unavailable.open(URL(string: "https://example.com")!, with: browser)
                XCTFail("Expected an unavailable application error")
            } catch let error as BrowserLaunchError {
                guard case .applicationUnavailable = error else {
                    return XCTFail("Expected BrowserLaunchError.applicationUnavailable")
                }
            }

            do {
                _ = try await rejected.open(URL(string: "https://example.com")!, with: browser)
                XCTFail("Expected a rejected handoff error")
            } catch let error as BrowserLaunchError {
                guard case .rejected = error else {
                    return XCTFail("Expected BrowserLaunchError.rejected")
                }
            }

            do {
                _ = try await system.open(URL(string: "https://example.com")!, with: browser)
                XCTFail("Expected the original system error to be surfaced")
            } catch let error as BrowserLaunchError {
                guard case let .system(surfacedError) = error else {
                    return XCTFail("Expected BrowserLaunchError.system")
                }
                let surfacedNSError = surfacedError as NSError
                XCTAssertEqual(surfacedNSError.domain, originalSystemError.domain)
                XCTAssertEqual(surfacedNSError.code, originalSystemError.code)
            }
        }.value
    }

    func testLauncherDoesNotReportSuccessBeforeWorkspaceCompletion() async throws {
        try await Task { @MainActor in
            let fixtures = try TemporaryApplicationBundles([
                ("Safari.app", "com.apple.Safari")
            ])
            defer { fixtures.remove() }

            let workspace = DeferredWorkspaceClient()
            let launcher = BrowserLauncherService(workspace: workspace)
            let browser = browserDescriptor(
                bundleIdentifier: "com.apple.Safari",
                applicationURL: fixtures.urls[0]
            )
            var didComplete = false
            let launchTask = Task { @MainActor in
                didComplete = try await launcher.open(
                    URL(string: "https://example.com")!,
                    with: browser
                ) == .handoffSucceeded
            }

            await Task.yield()
            XCTAssertTrue(workspace.hasPendingOpen)
            XCTAssertFalse(didComplete)
            workspace.succeed()
            _ = try await launchTask.value
            XCTAssertTrue(didComplete)
        }.value
    }

    func testCatalogRejectsUnreadableBundleRootsAlongsideNonFileAndNonDirectoryURLs() async throws {
        try await Task { @MainActor in
            let fixtures = try TemporaryApplicationBundles([
                ("Safari.app", "com.apple.Safari"),
                ("Unreadable Root.app", "com.example.unreadable-root")
            ])
            defer { fixtures.remove() }

            let unreadableRoot = fixtures.urls[1]
            let nonDirectory = try fixtures.makePlainFile(named: "Not A Bundle.app")
            let remoteURL = try XCTUnwrap(URL(string: "https://example.com/Remote.app"))
            try fixtures.makeBundleRootUnreadable(at: unreadableRoot)

            XCTAssertFalse(FileManager.default.isReadableFile(atPath: unreadableRoot.path))
            XCTAssertTrue(
                FileManager.default.isReadableFile(
                    atPath: unreadableRoot.appending(path: "Contents/Info.plist").path
                )
            )

            let workspace = StubWorkspaceClient(
                applicationURLs: [fixtures.urls[0], unreadableRoot, nonDirectory, remoteURL]
            )
            let catalog = BrowserCatalogService(workspace: workspace, customBrowsers: [], profileDiscovery: ChromiumProfileDiscovery(userDataDirectories: [:]))

            let browsers = try await catalog.scan()

            XCTAssertEqual(browsers.map(\.bundleIdentifier), ["com.apple.Safari"])
        }.value
    }
}

@MainActor
private final class StubWorkspaceClient: WorkspaceClient {
    private let applicationURLsByScheme: [String: [URL]]
    private let openError: Error?
    private let applicationIcon: NSImage
    private(set) var openedURLs: [URL] = []
    private(set) var profileLaunches: [(URL, [String])] = []

    init(
        applicationURLs: [URL],
        openError: Error? = nil,
        icon: NSImage = NSImage(size: NSSize(width: 32, height: 32))
    ) {
        applicationURLsByScheme = ["http": applicationURLs, "https": applicationURLs]
        self.openError = openError
        applicationIcon = icon
    }

    init(
        applicationURLsByScheme: [String: [URL]],
        openError: Error? = nil,
        icon: NSImage = NSImage(size: NSSize(width: 32, height: 32))
    ) {
        self.applicationURLsByScheme = applicationURLsByScheme
        self.openError = openError
        applicationIcon = icon
    }

    func applicationURLs(toOpen url: URL) -> [URL] {
        applicationURLsByScheme[url.scheme ?? ""] ?? []
    }

    func open(_ url: URL, with _: URL) async throws {
        openedURLs.append(url)
        if let openError {
            throw openError
        }
    }

    func openApplication(at applicationURL: URL, arguments: [String]) async throws {
        profileLaunches.append((applicationURL, arguments))
        if let openError { throw openError }
    }

    func icon(for _: URL) -> NSImage {
        applicationIcon
    }
}

@MainActor
private final class DeferredWorkspaceClient: WorkspaceClient {
    private var continuation: CheckedContinuation<Void, Error>?
    private(set) var hasPendingOpen = false

    func applicationURLs(toOpen _: URL) -> [URL] {
        []
    }

    func open(_: URL, with _: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            hasPendingOpen = true
            self.continuation = continuation
        }
    }

    func icon(for _: URL) -> NSImage {
        NSImage(size: NSSize(width: 32, height: 32))
    }

    func openApplication(at _: URL, arguments _: [String]) async throws {
        try await open(URL(string: "https://example.com")!, with: URL(fileURLWithPath: "/test.app"))
    }

    func succeed() {
        continuation?.resume()
        continuation = nil
        hasPendingOpen = false
    }
}

private final class TemporaryApplicationBundles {
    let root: URL
    let urls: [URL]
    private var unreadableInfoPlists: [URL] = []
    private var unreadableBundleRoots: [URL] = []

    init(_ applications: [(name: String, bundleIdentifier: String)]) throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var applicationURLs: [URL] = []
        for application in applications {
            applicationURLs.append(try Self.makeApplication(
                named: application.name,
                bundleIdentifier: application.bundleIdentifier,
                in: directory
            ))
        }
        root = directory
        urls = applicationURLs
    }

    func makeSymbolicLink(named name: String, to destination: URL) throws -> URL {
        let alias = root.appending(path: name)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: destination)
        return alias
    }

    func makeInfoPlistUnreadable(at applicationURL: URL) throws {
        let infoPlist = applicationURL.appending(path: "Contents/Info.plist")
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: infoPlist.path)
        unreadableInfoPlists.append(infoPlist)
    }

    func makeBundleRootUnreadable(at applicationURL: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o111], ofItemAtPath: applicationURL.path)
        unreadableBundleRoots.append(applicationURL)
    }

    func makePlainFile(named name: String) throws -> URL {
        let fileURL = root.appending(path: name)
        try Data("not an application bundle".utf8).write(to: fileURL)
        return fileURL
    }

    func remove() {
        for bundleRoot in unreadableBundleRoots {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bundleRoot.path)
        }
        for infoPlist in unreadableInfoPlists {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: infoPlist.path)
        }
        try? FileManager.default.removeItem(at: root)
    }

    private static func makeApplication(named name: String, bundleIdentifier: String, in root: URL) throws -> URL {
        let applicationURL = root.appending(path: name)
        let contentsURL = applicationURL.appending(path: "Contents")
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)

        let info: [String: String] = [
            "CFBundleIdentifier": bundleIdentifier,
            "CFBundleName": applicationURL.deletingPathExtension().lastPathComponent
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: contentsURL.appending(path: "Info.plist"))
        return applicationURL
    }
}

private enum BrowserServiceTestError: Error {
    case unavailable
}

private enum WorkspaceCompletionCategory: Equatable {
    case accepted
    case rejected
    case applicationUnavailable
    case system
}

private func workspaceCompletionCategory(_ result: WorkspaceOpenCompletion) -> WorkspaceCompletionCategory {
    switch result {
    case .accepted:
        .accepted
    case .failure(.rejected):
        .rejected
    case .failure(.applicationUnavailable):
        .applicationUnavailable
    case .failure(.system):
        .system
    }
}

private func assertOuterSystemError(_ result: WorkspaceOpenCompletion, expected: NSError) {
    guard case let .failure(.system(error)) = result else {
        return XCTFail("Expected the unknown outer error to remain a system error")
    }
    XCTAssertTrue(error as NSError === expected)
}

private func browserDescriptor(
    bundleIdentifier: String,
    applicationURL: URL,
    origin: BrowserOrigin = .system,
    availability: BrowserAvailability = .available,
    selectorOrder: Int = 0
) -> BrowserDescriptor {
    BrowserDescriptor(
        id: BrowserID(rawValue: bundleIdentifier),
        bundleIdentifier: bundleIdentifier,
        displayName: bundleIdentifier,
        applicationURL: applicationURL,
        securityScopedBookmark: nil,
        origin: origin,
        availability: availability,
        selectorOrder: selectorOrder
    )
}

@Test func browserManagementKeepsSavedCustomEntryRemovableWhenSystemDiscoversSameApplication() throws {
    let applicationURL = URL(fileURLWithPath: "/Applications/Custom Browser.app")
    let discovered = browserDescriptor(
        bundleIdentifier: "com.example.custom",
        applicationURL: applicationURL
    )
    let custom = browserDescriptor(
        bundleIdentifier: "com.example.custom",
        applicationURL: applicationURL,
        origin: .custom,
        selectorOrder: 7
    )

    let browsers = BrowserManagementPresentation.browsers(discovered: [discovered], custom: [custom])

    #expect(browsers.count == 1)
    let row = try #require(browsers.first)
    #expect(row.id == custom.id)
    #expect(row.applicationURL == custom.applicationURL)
    #expect(row.origin == .custom)
    #expect(row.availability == .available)
    #expect(row.selectorOrder == custom.selectorOrder)
}

@Test func browserManagementPreservesAvailableSystemCopyAndMissingCustomPathForSameIdentifier() throws {
    let discovered = browserDescriptor(
        bundleIdentifier: "com.example.custom",
        applicationURL: URL(fileURLWithPath: "/Applications/Custom Browser.app")
    )
    let custom = browserDescriptor(
        bundleIdentifier: "com.example.custom",
        applicationURL: URL(fileURLWithPath: "/Users/test/Applications/Missing Custom Browser.app"),
        origin: .custom
    )

    let browsers = BrowserManagementPresentation.browsers(discovered: [discovered], custom: [custom])

    #expect(browsers.count == 2)
    let systemRow = try #require(browsers.first { $0.applicationURL == discovered.applicationURL })
    #expect(systemRow.origin == .system)
    #expect(systemRow.availability == .available)
    let customRow = try #require(browsers.first { $0.applicationURL == custom.applicationURL })
    #expect(customRow.id == systemRow.id)
    #expect(customRow.origin == .custom)
    #expect(customRow.availability == .unavailable)
}

@Test @MainActor func catalogAddsStableProfilesWhileKeepingLegacyBrowserTargets() async throws {
    let apps = try TemporaryApplicationBundles([("Chrome.app", "com.google.Chrome"), ("Edge.app", "com.microsoft.edgemac")])
    defer { apps.remove() }
    let profiles = try TemporaryChromiumProfiles(names: ["Default": "个人", "Profile 1": "工作"])
    defer { profiles.remove() }
    let discovery = ChromiumProfileDiscovery(userDataDirectories: ["com.google.Chrome": profiles.root, "com.microsoft.edgemac": profiles.root])
    let catalog = BrowserCatalogService(workspace: StubWorkspaceClient(applicationURLs: apps.urls), profileDiscovery: discovery)
    let first = try await catalog.scan()
    #expect(first.count == 6)
    #expect(first.filter { $0.profile == nil }.map(\.id) == ["com.google.Chrome", "com.microsoft.edgemac"])
    #expect(first.map(\.selectorOrder) == Array(0..<6))
    let work = try #require(first.first { $0.bundleIdentifier == "com.google.Chrome" && $0.profile?.directoryName == "Profile 1" })
    #expect(work.displayName == "Chrome · 工作")
    try profiles.writeMetadata(["Default": "个人", "Profile 1": "重命名"])
    let renamed = try await catalog.scan()
    #expect(renamed.first { $0.id == work.id }?.displayName == "Chrome · 重命名")
    let ordered = BrowserCatalogService(workspace: StubWorkspaceClient(applicationURLs: apps.urls), savedSelectorOrder: [work.id, "com.google.Chrome"], profileDiscovery: discovery)
    #expect(try await ordered.scan().prefix(2).map(\.id) == [work.id, "com.google.Chrome"])
}

@Test func profileDiscoveryRejectsMissingUnsafeAndEscapingDirectories() throws {
    let profiles = try TemporaryChromiumProfiles(names: ["Default": "个人"])
    defer { profiles.remove() }
    let outside = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: outside) }
    try FileManager.default.createSymbolicLink(at: profiles.root.appending(path: "Escape"), withDestinationURL: outside)
    try profiles.writeMetadata(["Default": "个人", "Escape": "Escape", "Missing": "Missing", "../Outside": "Bad", "/tmp": "Bad", ".": "Bad", "..": "Bad", "Profile\\1": "Bad", "Bad\u{0}": "Bad"])
    let discovery = ChromiumProfileDiscovery(userDataDirectories: ["com.google.Chrome": profiles.root])
    #expect(discovery.profiles(for: "com.google.Chrome").map(\.directoryName) == ["Default"])
    #expect(discovery.profiles(for: "com.example.unsupported").isEmpty)
    try Data("broken JSON".utf8).write(to: profiles.root.appending(path: "Local State"))
    #expect(discovery.profiles(for: "com.google.Chrome").isEmpty)
}

@Test func profileDiscoveryDoesNotFollowLocalStateOutsideTheRoot() throws {
    let profiles = try TemporaryChromiumProfiles(names: ["Default": "个人"])
    defer { profiles.remove() }
    let other = try TemporaryChromiumProfiles(names: ["Default": "Other"])
    defer { other.remove() }
    let state = profiles.root.appending(path: "Local State")
    try FileManager.default.removeItem(at: state)
    try FileManager.default.createSymbolicLink(at: state, withDestinationURL: other.root.appending(path: "Local State"))
    #expect(ChromiumProfileDiscovery(userDataDirectories: ["com.google.Chrome": profiles.root]).profiles(for: "com.google.Chrome").isEmpty)
}

@Test @MainActor func launcherPassesProfileAndURLAsArgumentsWithoutAnOrdinaryURLHandoff() async throws {
    let apps = try TemporaryApplicationBundles([("Chrome.app", "com.google.Chrome")])
    defer { apps.remove() }
    let profiles = try TemporaryChromiumProfiles(names: ["Profile 1": "工作"])
    defer { profiles.remove() }
    let workspace = StubWorkspaceClient(applicationURLs: apps.urls)
    let discovery = ChromiumProfileDiscovery(userDataDirectories: ["com.google.Chrome": profiles.root])
    let catalog = BrowserCatalogService(workspace: workspace, profileDiscovery: discovery)
    let browser = try #require(try await catalog.scan().first { $0.profile != nil })
    let url = URL(string: "https://example.com/work?a=1&b=中文")!
    #expect(try await BrowserLauncherService(workspace: workspace, profileDiscovery: discovery).open(url, with: browser) == .handoffSucceeded)
    #expect(workspace.openedURLs.isEmpty)
    #expect(workspace.profileLaunches.count == 1)
    #expect(workspace.profileLaunches.first?.0 == apps.urls[0].standardizedFileURL)
    #expect(workspace.profileLaunches.first?.1 == ["--profile-directory=Profile 1", url.absoluteString])
}

@Test @MainActor func launcherRejectsDeletedProfileWithoutFallbackOrRecreation() async throws {
    let apps = try TemporaryApplicationBundles([("Chrome.app", "com.google.Chrome")])
    defer { apps.remove() }
    let profiles = try TemporaryChromiumProfiles(names: ["Default": "个人"])
    defer { profiles.remove() }
    let workspace = StubWorkspaceClient(applicationURLs: apps.urls)
    let discovery = ChromiumProfileDiscovery(userDataDirectories: ["com.google.Chrome": profiles.root])
    let catalog = BrowserCatalogService(workspace: workspace, profileDiscovery: discovery)
    let browser = try #require(try await catalog.scan().first { $0.profile != nil })
    try FileManager.default.removeItem(at: profiles.root.appending(path: "Default"))
    do {
        _ = try await BrowserLauncherService(workspace: workspace, profileDiscovery: discovery).open(URL(string: "https://example.com")!, with: browser)
        Issue.record("Expected unavailable profile")
    } catch let error as BrowserLaunchError {
        guard case .applicationUnavailable = error else { Issue.record("Expected unavailable profile"); return }
    }
    #expect(workspace.openedURLs.isEmpty)
    #expect(workspace.profileLaunches.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: profiles.root.appending(path: "Default").path))
}

private final class TemporaryChromiumProfiles {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    init(names: [String: String]) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for directory in names.keys {
            try FileManager.default.createDirectory(at: root.appending(path: directory), withIntermediateDirectories: true)
        }
        try writeMetadata(names)
    }
    func writeMetadata(_ names: [String: String]) throws {
        let cache = names.mapValues { ["name": $0, "user_name": "must-not-display@example.com"] }
        try JSONSerialization.data(withJSONObject: ["profile": ["info_cache": cache], "ignored_private_key": "ignored"])
            .write(to: root.appending(path: "Local State"))
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
}

@Test @MainActor func catalogKeepsOrdinaryBrowserWhenProfileMetadataIsUnavailable() async throws {
    let apps = try TemporaryApplicationBundles([("Chrome.app", "com.google.Chrome")])
    defer { apps.remove() }
    let profiles = try TemporaryChromiumProfiles(names: ["Default": "个人"])
    defer { profiles.remove() }
    try Data("broken JSON".utf8).write(to: profiles.root.appending(path: "Local State"))
    let catalog = BrowserCatalogService(workspace: StubWorkspaceClient(applicationURLs: apps.urls), profileDiscovery: ChromiumProfileDiscovery(userDataDirectories: ["com.google.Chrome": profiles.root]))
    let browsers = try await catalog.scan()
    #expect(browsers.map(\.id) == ["com.google.Chrome"])
    #expect(browsers.first?.profile == nil)
}

@Test @MainActor func launcherRejectsRemovedMetadataEvenWhenTheDirectoryRemains() async throws {
    let apps = try TemporaryApplicationBundles([("Edge.app", "com.microsoft.edgemac")])
    defer { apps.remove() }
    let profiles = try TemporaryChromiumProfiles(names: ["Default": "个人"])
    defer { profiles.remove() }
    let workspace = StubWorkspaceClient(applicationURLs: apps.urls)
    let discovery = ChromiumProfileDiscovery(userDataDirectories: ["com.microsoft.edgemac": profiles.root])
    let browser = try #require(try await BrowserCatalogService(workspace: workspace, profileDiscovery: discovery).scan().first { $0.profile != nil })
    try profiles.writeMetadata([:])
    do {
        _ = try await BrowserLauncherService(workspace: workspace, profileDiscovery: discovery).open(URL(string: "https://example.com")!, with: browser)
        Issue.record("Expected unavailable profile")
    } catch let error as BrowserLaunchError {
        guard case .applicationUnavailable = error else { Issue.record("Expected unavailable profile"); return }
    }
    #expect(workspace.openedURLs.isEmpty)
    #expect(workspace.profileLaunches.isEmpty)
}

@Test @MainActor func launcherKeepsOrdinaryBrowserHandoffWithoutProfileArguments() async throws {
    let apps = try TemporaryApplicationBundles([("Chrome.app", "com.google.Chrome")])
    defer { apps.remove() }
    let workspace = StubWorkspaceClient(applicationURLs: apps.urls)
    let browser = browserDescriptor(bundleIdentifier: "com.google.Chrome", applicationURL: apps.urls[0])
    let url = URL(string: "https://example.com")!
    #expect(try await BrowserLauncherService(workspace: workspace).open(url, with: browser) == .handoffSucceeded)
    #expect(workspace.openedURLs == [url])
    #expect(workspace.profileLaunches.isEmpty)
}
