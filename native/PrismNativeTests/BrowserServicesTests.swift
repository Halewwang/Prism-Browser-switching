import AppKit
import Foundation
import PrismCore
import Testing
@testable import PrismNative

@Test @MainActor func catalogDeduplicatesHandlersByBundleIdentifier() async throws {
    let fixtures = try TemporaryApplicationBundles([
        ("Safari.app", "com.apple.Safari"),
        ("Safari Copy.app", "com.apple.Safari"),
        ("Google Chrome.app", "com.google.Chrome")
    ])
    defer { fixtures.remove() }

    let workspace = StubWorkspaceClient(applicationURLs: fixtures.urls)
    let catalog = BrowserCatalogService(workspace: workspace, customBrowsers: [])

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
        prismBundleIdentifier: "com.prism.app"
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
        savedSelectorOrder: ["com.example.custom", "com.google.Chrome", "com.apple.Safari"]
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
    let catalog = BrowserCatalogService(workspace: workspace, browserPreferences: repository)

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
    let catalog = BrowserCatalogService(workspace: workspace, browserPreferences: repository)

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

@MainActor
private final class StubWorkspaceClient: WorkspaceClient {
    private let applicationURLsByScheme: [String: [URL]]
    private let openError: Error?
    private let applicationIcon: NSImage

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

    func open(_: URL, with _: URL) async throws {
        if let openError {
            throw openError
        }
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

    func remove() {
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
