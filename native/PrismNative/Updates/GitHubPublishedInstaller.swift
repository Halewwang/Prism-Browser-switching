import Foundation

struct GitHubPublishedInstaller: Equatable, Sendable {
    let version: String
    let notes: String
    let downloadURL: URL
    let fileName: String
    var isPrerelease = false
    var manifestURL: URL? = nil
    var signatureURL: URL? = nil
    var fileByteCount: Int64? = nil

    // GitHub's /releases/latest excludes the native public-test prereleases.
    static let releasesAPIURL = URL(string: "https://api.github.com/repos/Halewwang/Prism-Browser-switching/releases?per_page=100")!
    static let releasesURL = URL(string: "https://github.com/Halewwang/Prism-Browser-switching/releases")!

    static func isNewer(_ candidate: String, than current: String) -> Bool? {
        guard let candidate = versionNumbers(candidate), let current = versionNumbers(current) else { return nil }
        return current.lexicographicallyPrecedes(candidate)
    }

    private static func versionNumbers(_ version: String) -> [Int]? {
        let components = version.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3,
              components.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } })
        else { return nil }
        let numbers = components.compactMap { Int($0) }
        return numbers.count == 3 ? numbers : nil
    }
}

enum GitHubPublishedInstallerLookup {
    static func load(
        from releasesURL: URL = GitHubPublishedInstaller.releasesAPIURL,
        session: URLSession = .shared
    ) async throws -> GitHubPublishedInstaller {
        var request = URLRequest(url: releasesURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Prism", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw GitHubPublishedInstallerError.unavailable
        }
        return try decode(data)
    }

    static func decode(_ data: Data) throws -> GitHubPublishedInstaller {
        let releases = try JSONDecoder().decode([Release].self, from: data)
        let installers = releases.compactMap { release -> GitHubPublishedInstaller? in
            let version = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
            // 1.11.0 is the first native release. Never offer an Electron installer.
            guard !release.draft,
                  GitHubPublishedInstaller.isNewer("1.11.0", than: version) == false
            else { return nil }
            let names = ["Prism-\(version).dmg", "Prism-\(version)-universal-test.dmg"]
            let dmgAssets = release.assets.filter { names.contains($0.name) }
            guard dmgAssets.count == 1, let asset = dmgAssets.first,
                  let url = URL(string: asset.browser_download_url),
                  url.scheme?.lowercased() == "https", url.host?.lowercased() == "github.com",
                  url.user == nil, url.password == nil, url.port == nil,
                  url.query == nil, url.fragment == nil,
                  url.path == "/Halewwang/Prism-Browser-switching/releases/download/\(release.tag_name)/\(asset.name)"
            else { return nil }
            return GitHubPublishedInstaller(
                version: version, notes: release.body ?? "", downloadURL: url, fileName: asset.name,
                isPrerelease: release.prerelease ?? false,
                manifestURL: trustedAssetURL("update-manifest.json", release: release),
                signatureURL: trustedAssetURL("update-manifest.sig", release: release),
                fileByteCount: asset.size
            )
        }
        guard let newest = installers.max(by: { GitHubPublishedInstaller.isNewer($1.version, than: $0.version) == true }) else {
            throw GitHubPublishedInstallerError.noCompatibleRelease
        }
        return newest
    }

    private static func trustedAssetURL(_ name: String, release: Release) -> URL? {
        let assets = release.assets.filter { $0.name == name }
        guard assets.count == 1, let asset = assets.first,
              let url = URL(string: asset.browser_download_url),
              url.scheme == "https", url.host == "github.com",
              url.user == nil, url.password == nil, url.port == nil,
              url.query == nil, url.fragment == nil,
              url.path == "/Halewwang/Prism-Browser-switching/releases/download/\(release.tag_name)/\(name)"
        else { return nil }
        return url
    }

    private struct Release: Decodable {
        let tag_name: String
        let draft: Bool
        let prerelease: Bool?
        let body: String?
        let assets: [Asset]
    }

    private struct Asset: Decodable {
        let name: String
        let browser_download_url: String
        let size: Int64?
    }
}

enum GitHubPublishedInstallerError: Error, Equatable {
    case unavailable
    case noCompatibleRelease
}
