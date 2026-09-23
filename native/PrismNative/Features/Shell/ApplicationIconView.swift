import AppKit
import SwiftUI

struct ApplicationIconView: View {
    let bundleIdentifier: String?
    let applicationURL: URL?
    let fallbackSymbol: String
    var side: CGFloat = 20

    init(
        bundleIdentifier: String? = nil,
        applicationURL: URL? = nil,
        fallbackSymbol: String,
        side: CGFloat = 20
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.applicationURL = applicationURL
        self.fallbackSymbol = fallbackSymbol
        self.side = side
    }

    var body: some View {
        Group {
            if let image = resolvedImage {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: fallbackSymbol)
                    .font(.system(size: side * 0.72))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }

    private var resolvedImage: NSImage? {
        if let applicationURL {
            return NSWorkspace.shared.icon(forFile: applicationURL.path)
        }
        guard let bundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
