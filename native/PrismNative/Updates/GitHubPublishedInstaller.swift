import Foundation

struct GitHubPublishedInstaller: Equatable, Sendable {
    let version: String
    let notes: String
    let downloadURL: URL
    let fileName: String

    static let manifestURL = URL(string: "https://raw.githubusercontent.com/Halewwang/Prism-Browser-switching/main/latest-release.json")!
    static let releasesURL = URL(string: "https://github.com/Halewwang/Prism-Browser-switching/releases")!
}

enum GitHubPublishedInstallerLookup {
    static func load(from manifestURL: URL = GitHubPublishedInstaller.manifestURL) async throws -> GitHubPublishedInstaller {
        let (data, response) = try await URLSession.shared.data(from: manifestURL)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw GitHubPublishedInstallerError.unavailable
        }
        let payload = try JSONDecoder().decode(Manifest.self, from: data)
        guard let downloadURL = URL(string: payload.url), downloadURL.scheme?.lowercased() == "https" else {
            throw GitHubPublishedInstallerError.unavailable
        }
        let fileName = payload.fileName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return GitHubPublishedInstaller(
            version: payload.version,
            notes: payload.notes,
            downloadURL: downloadURL,
            fileName: (fileName?.isEmpty == false ? fileName! : downloadURL.lastPathComponent)
        )
    }

    private struct Manifest: Decodable {
        let version: String
        let notes: String
        let url: String
        let fileName: String?
    }
}

enum GitHubPublishedInstallerError: Error {
    case unavailable
}
