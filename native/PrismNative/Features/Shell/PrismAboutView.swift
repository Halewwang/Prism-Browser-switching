import AppKit
import SwiftUI

@MainActor
final class PrismAboutWindowController: NSWindowController {
    static let shared = PrismAboutWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 666, height: 233),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.title = NSLocalizedString("About Prism", comment: "About window")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        let hostingView = NSHostingView(rootView: PrismAboutView())
        hostingView.sizingOptions = []
        window.contentView = hostingView
        window.setFrame(NSRect(origin: window.frame.origin, size: NSSize(width: 666, height: 233)), display: false)
        super.init(window: window)
        window.center()
    }

    required init?(coder: NSCoder) { nil }

    func present() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}

private struct PrismAboutView: View {
    private var version: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "Prism \(version) (\(build))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().scaledToFit()
                    .frame(width: 54, height: 54)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Prism")
                        .font(.system(size: 23, weight: .semibold))
                        .foregroundStyle(SettingsPalette.secondary)
                        .frame(height: 33, alignment: .leading)
                    Text("Smart browser routing for macOS")
                        .font(.system(size: 12))
                        .foregroundStyle(SettingsPalette.muted)
                        .frame(height: 17, alignment: .leading)
                }
            }
            .frame(height: 55, alignment: .leading)
            Text("Every link opens in the right browser.\nOpen source, local first.")
                .font(.system(size: 13))
                .lineSpacing(6)
                .foregroundStyle(SettingsPalette.muted)
                .frame(height: 42, alignment: .topLeading)
            HStack(spacing: 22) {
                Link("Project Homepage ↗", destination: URL(string: "https://github.com/Halewwang/Prism-Browser-switching")!)
                Link("Report an Issue ↗", destination: URL(string: "https://github.com/Halewwang/Prism-Browser-switching/issues")!)
            }
            .font(.system(size: 12))
            .foregroundStyle(SettingsPalette.primary)
            .buttonStyle(.plain)
            .tint(SettingsPalette.primary)
            .frame(height: 17, alignment: .leading)
            Text(version)
                .font(.system(size: 11))
                .foregroundStyle(SettingsPalette.muted)
                .frame(height: 16, alignment: .leading)
                .accessibilityIdentifier("about.version")
        }
        .padding(26)
        .frame(width: 666, height: 233, alignment: .topLeading)
        .background(SettingsPalette.elevated)
        .ignoresSafeArea(.container, edges: .top)
    }
}
