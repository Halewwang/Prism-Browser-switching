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
        VStack(spacing: 12) {
            stateSymbol

            Text(model.title)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("\(model.accessibilityIdentifier).title")

            if let message = model.message {
                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
                    .accessibilityIdentifier("\(model.accessibilityIdentifier).message")
            }

            if !model.actions.isEmpty {
                actionButtons
                    .padding(.top, 4)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var stateSymbol: some View {
        if model.kind == .loading {
            ProgressView()
                .controlSize(.large)
                .accessibilityLabel("Loading")
                .accessibilityIdentifier("\(model.accessibilityIdentifier).progress")
        } else if let iconSystemName = model.iconSystemName {
            Image(systemName: iconSystemName)
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            ForEach(Array(model.actions.enumerated()), id: \.element.id) { index, action in
                if index == 0 {
                    actionButton(action)
                        .buttonStyle(.borderedProminent)
                } else {
                    actionButton(action)
                        .buttonStyle(.bordered)
                }
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
                Text(action.title)
            }
        }
        .disabled(!model.canPerformActions)
        .accessibilityValue(model.isPerformingAction ? "Retrying" : "Ready")
        .accessibilityIdentifier(action.accessibilityIdentifier)
    }
}
