import AppKit
import SwiftUI

@MainActor
final class InAppUpdateWindowController: NSWindowController, NSWindowDelegate {
    let session: InAppUpdateSession

    init(session: InAppUpdateSession) {
        self.session = session
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 460), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = NSLocalizedString("Update Prism", comment: "Update window")
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: InAppUpdateView(session: session))
        super.init(window: window)
        window.delegate = self
        window.center()
    }
    required init?(coder: NSCoder) { nil }
    func present() { showWindow(nil); window?.makeKeyAndOrderFront(nil); NSApp.activate() }
    func windowShouldClose(_ sender: NSWindow) -> Bool { session.stage != .installing }
    func windowWillClose(_ notification: Notification) { session.dispose() }
}

struct InAppUpdateView: View {
    let session: InAppUpdateSession
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.app.fill").font(.system(size: 32)).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Update Prism").font(.title2.bold())
                    Text("Prism \(session.installer.version)").foregroundStyle(.secondary)
                }
            }
            ScrollView {
                Text(session.installer.notes.isEmpty ? NSLocalizedString("A newer version of Prism is available.", comment: "Update notes") : session.installer.notes)
                    .font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
            }.frame(maxHeight: .infinity)
            if let message = session.message {
                Text(message).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("update.message")
            }
            status
            if session.stage == .ready {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Allow this unnotarized public-test update", isOn: Binding(
                        get: { session.allowUnnotarizedPublicTestUpdate },
                        set: { session.allowUnnotarizedPublicTestUpdate = $0 }
                    ))
                    .toggleStyle(.checkbox)
                    .accessibilityIdentifier("update.allowUnnotarizedPublicTestUpdate")
                    Text("This update has not been notarized by Apple. Permission applies only to this verified Prism update.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack {
                if session.stage == .ready {
                    Button("Show downloaded installer") { session.revealInstaller() }
                        .accessibilityIdentifier("update.revealInstaller")
                } else {
                    Text("Your rules and history are kept.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                action
            }
        }.padding(24).frame(width: 500, height: 460)
    }
    @ViewBuilder private var status: some View {
        switch session.stage {
        case .available, .failed:
            Text("Download and verify the update before installing.").font(.callout).foregroundStyle(.secondary)
        case .downloading:
            VStack(alignment: .leading, spacing: 8) {
                if let progress = session.progress {
                    ProgressView(value: progress).accessibilityIdentifier("update.progress")
                } else { ProgressView().controlSize(.small) }
                Text("Downloading and verifying update…").font(.callout)
            }
        case .ready:
            Label("Update verified. Ready to install.", systemImage: "checkmark.shield")
                .font(.callout).accessibilityIdentifier("update.ready")
        case .installing:
            HStack { ProgressView().controlSize(.small); Text("Preparing to install and restart…").font(.callout) }
        }
    }
    @ViewBuilder private var action: some View {
        switch session.stage {
        case .available:
            Button("Download update") { session.startDownload() }.buttonStyle(.borderedProminent).accessibilityIdentifier("update.download")
        case .failed:
            Button("Retry download") { session.startDownload() }.buttonStyle(.borderedProminent).accessibilityIdentifier("update.retry")
        case .downloading:
            Button("Cancel download") { session.cancelDownload() }.accessibilityIdentifier("update.cancel")
        case .ready:
            Button("Install and restart") { session.startInstall() }.buttonStyle(.borderedProminent).accessibilityIdentifier("update.install")
        case .installing:
            Button("Install and restart") {}.disabled(true).buttonStyle(.borderedProminent)
        }
    }
}
