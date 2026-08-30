import AppKit
import Foundation
import UniformTypeIdentifiers

struct RunningSourceApplication: Identifiable, Equatable {
    var id: String { bundleIdentifier }
    let bundleIdentifier: String
    let displayName: String
}

@MainActor
protocol RunningSourceApplicationListing {
    func runningApplications(excludingBundleIDs: Set<String>) -> [RunningSourceApplication]
}

@MainActor
protocol SourceApplicationFileChoosing {
    func chooseApplication() -> URL?
}

@MainActor
final class WorkspaceRunningSourceApplicationCatalog: RunningSourceApplicationListing {
    private let prismBundleIdentifier: String

    init(prismBundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.prism.app") {
        self.prismBundleIdentifier = prismBundleIdentifier
    }

    func runningApplications(excludingBundleIDs: Set<String>) -> [RunningSourceApplication] {
        var seen = Set<String>()
        var applications: [RunningSourceApplication] = []
        for application in NSWorkspace.shared.runningApplications where application.activationPolicy == .regular {
            guard let bundleIdentifier = application.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !bundleIdentifier.isEmpty,
                  bundleIdentifier != prismBundleIdentifier,
                  !excludingBundleIDs.contains(bundleIdentifier),
                  seen.insert(bundleIdentifier).inserted
            else {
                continue
            }
            let displayName = application.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines)
            applications.append(
                RunningSourceApplication(
                    bundleIdentifier: bundleIdentifier,
                    displayName: displayName?.isEmpty == false
                        ? displayName!
                        : (InstalledApplicationLookup.displayName(forBundleIdentifier: bundleIdentifier) ?? bundleIdentifier)
                )
            )
        }
        return applications.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }
}

@MainActor
struct SystemSourceApplicationFileChooser: SourceApplicationFileChoosing {
    func chooseApplication() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.prompt = String(localized: "rules.source.chooseApplication", defaultValue: "Choose Application…")
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}
