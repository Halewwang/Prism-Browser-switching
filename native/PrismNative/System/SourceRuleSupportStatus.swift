import Foundation

/// Physical evidence for this OS is independent from a single link's source confidence.
enum SourceRuleSupportStatus: Equatable {
    case verified
    case pendingVerification

    init(bundleIdentifier: String, verifiedBundleIDs: Set<String>) {
        self = verifiedBundleIDs.contains(bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines))
            ? .verified : .pendingVerification
    }

    var message: String {
        switch self {
        case .verified:
            String(
                localized: "rules.sourceSupport.verified",
                defaultValue: "Verified on this macOS version; runs only when macOS confirms the source."
            )
        case .pendingVerification:
            String(
                localized: "rules.sourceSupport.pending",
                defaultValue: "Pending verification: runs only when macOS confirms the source."
            )
        }
    }
}
