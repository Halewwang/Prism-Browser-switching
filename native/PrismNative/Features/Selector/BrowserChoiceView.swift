import AppKit
import PrismCore
import SwiftUI

struct BrowserChoiceView: View {
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.colorSchemeContrast) private var contrast

    let browser: BrowserDescriptor
    let icon: NSImage
    let width: CGFloat
    let height: CGFloat
    let shortcut: Int?
    let isSelected: Bool
    let isFailed: Bool
    let accessibilityLabel: String
    let onActivate: @MainActor () -> Void

    var body: some View {
        Button(action: onActivate) {
            VStack(spacing: 0) {
                Spacer(minLength: isRecoveryCompact ? 5 : 18)
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: iconSize, height: iconSize)
                    .accessibilityHidden(true)
                Text(browser.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SelectorPalette.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.top, isRecoveryCompact ? 3 : 7)
                if let shortcut {
                    KeyboardShortcutBadge(number: shortcut)
                        .padding(.top, isRecoveryCompact ? 3 : 11)
                        .padding(.bottom, isRecoveryCompact ? 5 : 10)
                } else {
                    Spacer(minLength: isRecoveryCompact ? 20 : 30)
                }
            }
            .frame(width: width, height: height)
            .background(isSelected ? SelectorPalette.selected : .clear)
            .clipShape(RoundedRectangle(cornerRadius: SelectorMetrics.cardRadius))
            .overlay {
                RoundedRectangle(cornerRadius: SelectorMetrics.cardRadius)
                    .stroke(borderColor, lineWidth: contrast == .increased ? 1 : 0.5)
            }
            .overlay(alignment: .topTrailing) {
                if isFailed {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(SelectorPalette.error)
                        .padding(8)
                        .accessibilityHidden(true)
                } else if isSelected, differentiateWithoutColor {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(SelectorPalette.secondaryText)
                        .padding(8)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: SelectorMetrics.cardRadius))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .help(Text(verbatim: browser.displayName))
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("selector.browser.\(browser.id.rawValue)")
    }

    private var iconSize: CGFloat {
        if isRecoveryCompact { return SelectorMetrics.recoveryIconSize }
        return width == SelectorMetrics.fixedItemWidth
            ? SelectorMetrics.iconSize
            : SelectorMetrics.compactIconSize
    }

    private var isRecoveryCompact: Bool {
        height < SelectorMetrics.itemHeight
    }

    private var borderColor: Color {
        if isFailed { return SelectorPalette.error }
        if contrast == .increased { return SelectorPalette.highContrastBorder }
        if isSelected { return SelectorPalette.selectionBorder }
        return .clear
    }
}
