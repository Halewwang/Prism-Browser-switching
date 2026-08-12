import SwiftUI

struct SelectorEmptyStateView: View {
    let isLoading: Bool
    let failureMessage: String?
    let onRescan: () -> Void
    let onOpenBrowserManagement: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: failureMessage == nil ? "safari" : "exclamationmark.triangle")
                .font(.title3)
                .foregroundStyle(SelectorPalette.secondaryText)
                .accessibilityHidden(true)
            Text(failureMessage ?? String(
                localized: "selector.empty.title",
                defaultValue: "No browser is available"
            ))
            .font(.callout)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            HStack(spacing: 8) {
                Button(action: onRescan) {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(String(localized: "selector.rescan", defaultValue: "Rescan"))
                    }
                }
                .disabled(isLoading)
                .accessibilityIdentifier("selector.rescan")
                Button(
                    String(localized: "selector.openBrowserManagement", defaultValue: "Open Browser Management"),
                    action: onOpenBrowserManagement
                )
                .accessibilityIdentifier("selector.openBrowserManagement")
            }
            .controlSize(.small)
        }
        .frame(width: SelectorMetrics.viewportSize.width, height: SelectorMetrics.viewportSize.height)
        .accessibilityElement(children: .contain)
    }
}
