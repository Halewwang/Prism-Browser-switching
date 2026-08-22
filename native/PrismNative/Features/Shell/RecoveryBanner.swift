import SwiftUI

enum RecoveryBannerKind: String, CaseIterable, Equatable, Sendable {
    case defaultHandlerDrift
    case corruptDataRecovered
    case historyReconciliationPending
    case updateFailure

    var iconSystemName: String {
        switch self {
        case .defaultHandlerDrift:
            "link.badge.plus"
        case .corruptDataRecovered:
            "externaldrive.badge.exclamationmark"
        case .historyReconciliationPending:
            "clock.arrow.circlepath"
        case .updateFailure:
            "arrow.clockwise.circle"
        }
    }
}

struct RecoveryBannerModel: Equatable, Sendable {
    let kind: RecoveryBannerKind
    let title: String
    let message: String
    let primaryAction: PageStateAction
    let isPerformingAction: Bool

    init(
        kind: RecoveryBannerKind,
        title: String,
        message: String,
        actionTitle: String,
        actionAccessibilityIdentifier: String,
        isPerformingAction: Bool = false
    ) {
        self.kind = kind
        self.title = title
        self.message = message
        primaryAction = PageStateAction(
            id: actionAccessibilityIdentifier,
            title: actionTitle,
            accessibilityIdentifier: actionAccessibilityIdentifier
        )
        self.isPerformingAction = isPerformingAction
    }

    var iconSystemName: String {
        kind.iconSystemName
    }

    var canPerformAction: Bool {
        !isPerformingAction
    }

    var accessibilityIdentifier: String {
        "recoveryBanner.\(kind.rawValue)"
    }
}

struct RecoveryBanner: View {
    let model: RecoveryBannerModel
    let onAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: model.iconSystemName)
                .font(.title3)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(model.title))
                    .font(.headline)
                    .accessibilityLabel(model.title)
                    .accessibilityIdentifier("\(model.accessibilityIdentifier).title")
                Text(LocalizedStringKey(model.message))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(model.message)
                    .accessibilityIdentifier("\(model.accessibilityIdentifier).message")
            }

            Spacer(minLength: 12)

            Button {
                guard model.canPerformAction else { return }
                onAction()
            } label: {
                HStack(spacing: 6) {
                    if model.isPerformingAction {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityHidden(true)
                    }
                    Text(LocalizedStringKey(model.primaryAction.title))
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canPerformAction)
            .accessibilityValue(model.isPerformingAction ? "Retrying" : "Ready")
            .accessibilityIdentifier(model.primaryAction.accessibilityIdentifier)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }
}
