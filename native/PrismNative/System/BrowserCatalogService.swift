import Foundation
import PrismCore

@MainActor
protocol BrowserCataloging: AnyObject {
    func scan() async throws -> [BrowserDescriptor]
    func scanForSelector() async throws -> [BrowserDescriptor]
}

extension BrowserCataloging {
    func scanForSelector() async throws -> [BrowserDescriptor] { try await scan() }
}

enum BrowserCatalogError: Error, Equatable {
    case cannotOpenWebLinks
    case invalidApplication
    case preferenceStorageUnavailable
}

@MainActor
final class BrowserCatalogService: BrowserCataloging {
    private static let httpProbeURL = URL(string: "http://example.com")!
    private static let httpsProbeURL = URL(string: "https://example.com")!

    private let workspace: any WorkspaceClient
    private let configuredCustomBrowsers: [BrowserDescriptor]
    private let configuredSelectorOrder: [BrowserID]
    private let browserPreferences: (any BrowserPreferenceRepository)?
    private let prismBundleIdentifier: String
    private let profileDiscovery: ChromiumProfileDiscovery

    init(
        workspace: any WorkspaceClient = SystemWorkspaceClient(),
        customBrowsers: [BrowserDescriptor] = [],
        savedSelectorOrder: [BrowserID] = [],
        browserPreferences: (any BrowserPreferenceRepository)? = nil,
        prismBundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.prism.app",
        profileDiscovery: ChromiumProfileDiscovery = ChromiumProfileDiscovery()
    ) {
        self.workspace = workspace
        configuredCustomBrowsers = customBrowsers
        configuredSelectorOrder = savedSelectorOrder
        self.browserPreferences = browserPreferences
        self.prismBundleIdentifier = prismBundleIdentifier
        self.profileDiscovery = profileDiscovery
    }

    func scan() async throws -> [BrowserDescriptor] {
        let customBrowsers = try browserPreferences?.customBrowsers() ?? configuredCustomBrowsers
        let savedSelectorOrder = try browserPreferences?.orderedBrowserIDs() ?? configuredSelectorOrder
        var byBundleIdentifier: [String: BrowserDescriptor] = [:]
        var identifiersInDiscoveryOrder: [String] = []

        for applicationURL in uniqueApplicationURLs(
            workspace.applicationURLs(toOpen: Self.httpProbeURL)
                + workspace.applicationURLs(toOpen: Self.httpsProbeURL)
        ) {
            add(
                browserDescriptor(at: applicationURL, origin: .system),
                to: &byBundleIdentifier,
                discoveryOrder: &identifiersInDiscoveryOrder
            )
        }

        for customBrowser in customBrowsers {
            add(
                browserDescriptor(
                    at: customBrowser.applicationURL,
                    origin: .custom,
                    bookmark: customBrowser.securityScopedBookmark
                ),
                to: &byBundleIdentifier,
                discoveryOrder: &identifiersInDiscoveryOrder
            )
        }

        return ordered(
            identifiersInDiscoveryOrder.compactMap { byBundleIdentifier[$0] }.flatMap { browser in
                [browser] + profileDiscovery.profiles(for: browser.bundleIdentifier).map { profile in
                    BrowserDescriptor(
                        id: profile.browserID(bundleIdentifier: browser.bundleIdentifier),
                        bundleIdentifier: browser.bundleIdentifier,
                        displayName: "\(browser.displayName) · \(profile.displayName)",
                        applicationURL: browser.applicationURL,
                        securityScopedBookmark: browser.securityScopedBookmark,
                        origin: browser.origin,
                        availability: .available,
                        selectorOrder: 0,
                        profile: profile
                    )
                }
            },
            savedSelectorOrder: savedSelectorOrder
        )
    }

    func scanForSelector() async throws -> [BrowserDescriptor] {
        let hidden = Set(try browserPreferences?.hiddenBrowserIDs() ?? [])
        return try await scan().filter { !hidden.contains($0.id) }
    }

    func saveCustomBrowser(at applicationURL: URL) throws -> BrowserDescriptor {
        guard let browserPreferences else {
            throw BrowserCatalogError.preferenceStorageUnavailable
        }
        guard let candidate = browserDescriptor(at: applicationURL, origin: .custom) else {
            throw BrowserCatalogError.invalidApplication
        }

        let resolvedCandidateURL = resolvedApplicationURL(applicationURL)
        let httpApplications = Set(
            workspace.applicationURLs(toOpen: Self.httpProbeURL).map(resolvedApplicationURL)
        )
        let httpsApplications = Set(
            workspace.applicationURLs(toOpen: Self.httpsProbeURL).map(resolvedApplicationURL)
        )
        guard httpApplications.contains(resolvedCandidateURL), httpsApplications.contains(resolvedCandidateURL) else {
            throw BrowserCatalogError.cannotOpenWebLinks
        }

        let existingBrowsers = try browserPreferences.customBrowsers()
        let selectorOrder = existingBrowsers.first(where: { $0.id == candidate.id })?.selectorOrder
            ?? (existingBrowsers.map(\.selectorOrder).max().map { $0 + 1 } ?? 0)
        let saved = BrowserDescriptor(
            id: candidate.id,
            bundleIdentifier: candidate.bundleIdentifier,
            displayName: candidate.displayName,
            applicationURL: candidate.applicationURL,
            securityScopedBookmark: candidate.securityScopedBookmark,
            origin: .custom,
            availability: .available,
            selectorOrder: selectorOrder
        )
        try browserPreferences.upsertCustomBrowser(saved)
        return saved
    }

    private func add(
        _ browser: BrowserDescriptor?,
        to browsers: inout [String: BrowserDescriptor],
        discoveryOrder: inout [String]
    ) {
        guard let browser, browsers[browser.bundleIdentifier] == nil else { return }
        browsers[browser.bundleIdentifier] = browser
        discoveryOrder.append(browser.bundleIdentifier)
    }

    private func browserDescriptor(
        at applicationURL: URL,
        origin: BrowserOrigin,
        bookmark: Data? = nil
    ) -> BrowserDescriptor? {
        guard applicationURL.isFileURL else { return nil }

        let resolvedURL = resolvedApplicationURL(applicationURL)
        var isDirectory: ObjCBool = false
        let fileManager = FileManager.default
        guard resolvedURL.isFileURL,
              resolvedURL.pathExtension == "app",
              fileManager.fileExists(atPath: resolvedURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              fileManager.isReadableFile(atPath: resolvedURL.path),
              let bundle = Bundle(url: resolvedURL),
              fileManager.isReadableFile(atPath: resolvedURL.appending(path: "Contents/Info.plist").path),
              let bundleIdentifier = bundle.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !bundleIdentifier.isEmpty,
              bundleIdentifier != prismBundleIdentifier else {
            return nil
        }

        let displayName = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? resolvedURL.deletingPathExtension().lastPathComponent
        return BrowserDescriptor(
            id: BrowserID(rawValue: bundleIdentifier),
            bundleIdentifier: bundleIdentifier,
            displayName: displayName,
            applicationURL: resolvedURL,
            securityScopedBookmark: bookmark,
            origin: origin,
            availability: .available,
            selectorOrder: 0
        )
    }

    private func uniqueApplicationURLs(_ applicationURLs: [URL]) -> [URL] {
        var seen: Set<URL> = []
        return applicationURLs.filter { seen.insert(resolvedApplicationURL($0)).inserted }
    }

    private func resolvedApplicationURL(_ url: URL) -> URL {
        guard url.isFileURL else { return url }
        return url.resolvingSymlinksInPath().standardizedFileURL
    }

    private func ordered(
        _ browsers: [BrowserDescriptor],
        savedSelectorOrder: [BrowserID]
    ) -> [BrowserDescriptor] {
        var positions: [BrowserID: Int] = [:]
        for id in savedSelectorOrder where positions[id] == nil {
            positions[id] = positions.count
        }
        let defaultPosition = positions.count
        let sorted = browsers.enumerated().sorted { lhs, rhs in
            let lhsPosition = positions[lhs.element.id] ?? (defaultPosition + lhs.offset)
            let rhsPosition = positions[rhs.element.id] ?? (defaultPosition + rhs.offset)
            if lhsPosition != rhsPosition {
                return lhsPosition < rhsPosition
            }
            return lhs.offset < rhs.offset
        }
        return sorted.enumerated().map { index, element in
            let browser = element.element
            return BrowserDescriptor(
                id: browser.id,
                bundleIdentifier: browser.bundleIdentifier,
                displayName: browser.displayName,
                applicationURL: browser.applicationURL,
                securityScopedBookmark: browser.securityScopedBookmark,
                origin: browser.origin,
                availability: browser.availability,
                selectorOrder: index,
                profile: browser.profile
            )
        }
    }
}
