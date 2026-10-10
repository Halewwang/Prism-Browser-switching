import AppKit
import SwiftUI

@MainActor
final class InAppUpdateWindowController: NSWindowController, NSWindowDelegate {
    let session: InAppUpdateSession

    init(session: InAppUpdateSession) {
        self.session = session
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 666, height: 315), styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = NSLocalizedString("Update Prism", comment: "Update window")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        let hostingView = NSHostingView(rootView: InAppUpdateView(
            session: session,
            onClose: { [weak window] in window?.close() },
            onSizeChange: { [weak window] height in
                guard let window else { return }
                var frame = window.frame
                frame.origin.y += frame.height - height
                frame.size = NSSize(width: 666, height: height)
                window.setFrame(frame, display: true)
            }
        ))
        hostingView.sizingOptions = []
        window.contentView = hostingView
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
    var onClose: () -> Void = {}
    var onSizeChange: (CGFloat) -> Void = { _ in }

    var body: some View {
        Group {
            if session.stage == .available { availableContent }
            else { progressContent }
        }
        .foregroundStyle(SettingsPalette.primary)
        .background(SettingsPalette.elevated)
        .ignoresSafeArea(.container, edges: .top)
        .tint(SettingsPalette.action)
        .onChange(of: session.stage, initial: true) { _, stage in
            onSizeChange((stage == .available ? 315 : 460) + WorkspaceLayout.windowControlClearance)
        }
    }

    private var availableContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "arrow.down.to.line")
                .font(.system(size: 28))
                .foregroundStyle(SettingsPalette.iconStrong)
                .frame(width: 28, height: 28)
            Text("A new version is available")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(SettingsPalette.secondary)
                .frame(height: 30, alignment: .leading)
            Text("Upgrade Prism for the latest features and fixes.")
                .font(.system(size: 13))
                .foregroundStyle(SettingsPalette.muted)
                .frame(height: 19, alignment: .leading)
            VStack(alignment: .leading, spacing: 8) {
                Text(String(format: String(localized: "update.releaseNotesVersion"), session.installer.version))
                    .font(.system(size: 12))
                    .foregroundStyle(SettingsPalette.tertiary)
                ScrollView {
                    Text(session.installer.notes.isEmpty ? NSLocalizedString("A newer version of Prism is available.", comment: "Update notes") : session.installer.notes)
                        .font(.system(size: 11))
                        .foregroundStyle(SettingsPalette.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
            .padding(16)
            .frame(height: 75)
            .background(SettingsPalette.window, in: RoundedRectangle(cornerRadius: 8))
            HStack(spacing: 10) {
                Spacer()
                Button("Remind me later", action: onClose)
                    .buttonStyle(WorkspaceButtonStyle(kind: .secondary, height: 39))
                    .keyboardShortcut(.cancelAction)
                action
            }
            .frame(height: 39)
        }
        .padding(26)
        .padding(.top, WorkspaceLayout.windowControlClearance)
        .frame(width: 666, height: 315 + WorkspaceLayout.windowControlClearance, alignment: .topLeading)
    }

    private var progressContent: some View {
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
                Text(message).font(.callout).foregroundStyle(SettingsPalette.danger).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("update.message")
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
        }
        .buttonStyle(WorkspaceButtonStyle(kind: .secondary, height: 39))
        .padding(26)
        .padding(.top, WorkspaceLayout.windowControlClearance)
        .frame(width: 666, height: 460 + WorkspaceLayout.windowControlClearance)
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
            Button("Download update") { session.startDownload() }.buttonStyle(WorkspaceButtonStyle(kind: .primary, height: 39)).accessibilityIdentifier("update.download")
        case .failed:
            Button("Retry download") { session.startDownload() }.buttonStyle(WorkspaceButtonStyle(kind: .primary, height: 39)).accessibilityIdentifier("update.retry")
        case .downloading:
            Button("Cancel download") { session.cancelDownload() }.accessibilityIdentifier("update.cancel")
        case .ready:
            Button("Install and restart") { session.startInstall() }.buttonStyle(WorkspaceButtonStyle(kind: .primary, height: 39)).accessibilityIdentifier("update.install")
        case .installing:
            Button("Install and restart") {}.disabled(true).buttonStyle(WorkspaceButtonStyle(kind: .primary, height: 39))
        }
    }
}
