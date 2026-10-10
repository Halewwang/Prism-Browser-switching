import SwiftUI

enum PageStateKind: String, Equatable, Sendable {
    case loading
    case empty
    case failed
    case recovery
}

struct PageStateAction: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let accessibilityIdentifier: String
}

struct PageStateModel: Equatable, Sendable {
    let kind: PageStateKind
    let iconSystemName: String?
    let title: String
    let message: String?
    let actions: [PageStateAction]
    let isPerformingAction: Bool

    private init(
        kind: PageStateKind,
        iconSystemName: String?,
        title: String,
        message: String?,
        actions: [PageStateAction],
        isPerformingAction: Bool = false
    ) {
        self.kind = kind
        self.iconSystemName = iconSystemName
        self.title = title
        self.message = message
        self.actions = actions
        self.isPerformingAction = isPerformingAction
    }

    var accessibilityIdentifier: String {
        "pageState.\(kind.rawValue)"
    }

    var canPerformActions: Bool {
        !isPerformingAction
    }

    static func loading(title: String, message: String? = nil) -> Self {
        Self(
            kind: .loading,
            iconSystemName: nil,
            title: title,
            message: message,
            actions: []
        )
    }

    static func empty(
        iconSystemName: String,
        title: String,
        message: String? = nil,
        actions: [PageStateAction] = []
    ) -> Self {
        Self(
            kind: .empty,
            iconSystemName: iconSystemName,
            title: title,
            message: message,
            actions: actions
        )
    }

    static func failed(
        title: String,
        message: String,
        action: PageStateAction
    ) -> Self {
        Self(
            kind: .failed,
            iconSystemName: "exclamationmark.triangle",
            title: title,
            message: message,
            actions: [action]
        )
    }

    static func recovery(
        title: String,
        message: String,
        action: PageStateAction,
        isPerformingAction: Bool = false
    ) -> Self {
        Self(
            kind: .recovery,
            iconSystemName: "arrow.clockwise.circle",
            title: title,
            message: message,
            actions: [action],
            isPerformingAction: isPerformingAction
        )
    }
}

struct PageStateView: View {
    let model: PageStateModel
    let onAction: (String) -> Void

    init(model: PageStateModel, onAction: @escaping (String) -> Void = { _ in }) {
        self.model = model
        self.onAction = onAction
    }

    var body: some View {
        VStack(spacing: 14) {
            stateSymbol

            Text(LocalizedStringKey(model.title))
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(SettingsPalette.tertiary)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("\(model.accessibilityIdentifier).title")

            if let message = model.message {
                Text(LocalizedStringKey(message))
                    .font(.system(size: 12))
                    .foregroundStyle(SettingsPalette.muted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("\(model.accessibilityIdentifier).message")
            }

            if model.kind == .loading {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(SettingsPalette.action)
                    .frame(width: 160, height: 4)
                    .clipShape(Capsule())
                    .accessibilityHidden(true)
            }

            if !model.actions.isEmpty {
                actionButtons
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .frame(height: 297)
        .background(SettingsPalette.elevated, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(SettingsPalette.borderSubtle, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var stateSymbol: some View {
        if model.kind == .loading || model.iconSystemName != nil {
            Group {
                if model.kind == .loading {
                    ProgressView()
                        .controlSize(.large)
                        .scaleEffect(0.875)
                        .accessibilityLabel("Loading")
                        .accessibilityIdentifier("\(model.accessibilityIdentifier).progress")
                } else if let iconSystemName = model.iconSystemName {
                    Image(systemName: iconSystemName)
                        .font(.system(size: 28, weight: .regular))
                        .foregroundStyle(model.kind == .failed ? SettingsPalette.danger : SettingsPalette.iconMuted)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: 54, height: 54)
            .background(SettingsPalette.iconWell, in: RoundedRectangle(cornerRadius: 18))
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            ForEach(model.actions) { action in
                actionButton(action)
                    .buttonStyle(WorkspaceButtonStyle(kind: .secondary, height: 39))
            }
        }
    }

    private func actionButton(_ action: PageStateAction) -> some View {
        Button {
            onAction(action.id)
        } label: {
            HStack(spacing: 6) {
                if model.isPerformingAction {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityHidden(true)
                }
                Text(LocalizedStringKey(action.title))
            }
        }
        .disabled(!model.canPerformActions)
        .accessibilityValue(model.isPerformingAction ? "Retrying" : "Ready")
        .accessibilityIdentifier(action.accessibilityIdentifier)
    }
}
