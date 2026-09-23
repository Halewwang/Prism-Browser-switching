import AppKit
import Foundation

struct InstalledApplication: Identifiable, Hashable {
    let bundleIdentifier: String
    let displayName: String
    let applicationURL: URL

    var id: String { bundleIdentifier }
}

enum InstalledApplicationCatalog {
    static func load() -> [InstalledApplication] {
        let homeApplications = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
        let directories = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            homeApplications,
        ]
        var seen: Set<String> = []
        var applications: [InstalledApplication] = []
        for directory in directories {
            appendApplications(in: directory, depth: 0, seen: &seen, into: &applications)
        }
        return applications.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    private static func appendApplications(
        in directory: URL,
        depth: Int,
        seen: inout Set<String>,
        into applications: inout [InstalledApplication]
    ) {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        for url in contents {
            if url.pathExtension == "app" {
                guard let bundle = Bundle(url: url),
                      let bundleIdentifier = bundle.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !bundleIdentifier.isEmpty,
                      seen.insert(bundleIdentifier).inserted
                else { continue }
                let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                    ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                    ?? url.deletingPathExtension().lastPathComponent
                applications.append(InstalledApplication(
                    bundleIdentifier: bundleIdentifier,
                    displayName: displayName,
                    applicationURL: url
                ))
            } else if depth == 0 {
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if isDirectory {
                    appendApplications(in: url, depth: 1, seen: &seen, into: &applications)
                }
            }
        }
    }
}
