import Foundation
import PrismCore

/// Reads only profile names and directory keys from Chromium's shared metadata.
/// It never opens files inside a profile directory.
struct ChromiumProfileDiscovery: Sendable {
    private static let supportedDirectories = [
        "com.google.Chrome": "Google/Chrome",
        "com.microsoft.edgemac": "Microsoft Edge"
    ]
    private let userDataDirectories: [String: URL]

    init(userDataDirectories: [String: URL]? = nil) {
        let support = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support", directoryHint: .isDirectory)
        self.userDataDirectories = userDataDirectories ?? Self.supportedDirectories.mapValues {
            support.appending(path: $0, directoryHint: .isDirectory)
        }
    }

    func profiles(for bundleIdentifier: String) -> [ChromiumProfileDescriptor] {
        guard Self.supportedDirectories[bundleIdentifier] != nil,
              let configuredRoot = userDataDirectories[bundleIdentifier],
              configuredRoot.isFileURL else { return [] }
        let root = configuredRoot.resolvingSymlinksInPath().standardizedFileURL
        let localState = root.appending(path: "Local State").resolvingSymlinksInPath().standardizedFileURL
        guard localState.deletingLastPathComponent() == root,
              let size = try? localState.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= 4 * 1_024 * 1_024,
              let data = try? Data(contentsOf: localState),
              let state = try? JSONDecoder().decode(LocalState.self, from: data),
              let cache = state.profile?.infoCache else { return [] }
        return cache.keys.sorted().compactMap { directory in
            guard Self.isSafeBasename(directory),
                  directoryExists(directory, under: root) else { return nil }
            let name = cache[directory]?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            return ChromiumProfileDescriptor(
                directoryName: directory,
                displayName: name.flatMap { $0.isEmpty ? nil : $0 } ?? directory,
                userDataDirectory: root
            )
        }
    }

    func isAvailable(_ profile: ChromiumProfileDescriptor, bundleIdentifier: String) -> Bool {
        profiles(for: bundleIdentifier).contains {
            $0.directoryName == profile.directoryName && $0.userDataDirectory == profile.userDataDirectory
        }
    }

    private static func isSafeBasename(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".."
            && !value.contains("/") && !value.contains("\\")
            && !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }

    private func directoryExists(_ directory: String, under root: URL) -> Bool {
        let candidate = root.appending(path: directory, directoryHint: .isDirectory)
            .resolvingSymlinksInPath().standardizedFileURL
        // Resolve links before checking containment so a cache key cannot escape the root.
        guard candidate.deletingLastPathComponent() == root else { return false }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory)
            && isDirectory.boolValue && FileManager.default.isReadableFile(atPath: candidate.path)
    }

    private struct LocalState: Decodable {
        let profile: ProfileCache?
    }

    private struct ProfileCache: Decodable {
        let infoCache: [String: ProfileName]?
        enum CodingKeys: String, CodingKey { case infoCache = "info_cache" }
    }

    private struct ProfileName: Decodable {
        let name: String?
    }
}
