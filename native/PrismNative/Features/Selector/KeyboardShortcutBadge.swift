import AppKit
import SwiftUI

struct KeyboardShortcutBadge: View {
    @Environment(\.colorSchemeContrast) private var contrast

    let number: Int

    var body: some View {
        Text(String(number))
            .font(.caption2.monospacedDigit())
            .foregroundStyle(SelectorPalette.secondaryText)
            .frame(width: SelectorMetrics.shortcutSize, height: SelectorMetrics.shortcutSize)
            .background(SelectorPalette.shortcutBackground, in: RoundedRectangle(cornerRadius: 5))
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(
                        contrast == .increased ? SelectorPalette.highContrastBorder : SelectorPalette.border,
                        lineWidth: contrast == .increased ? 1 : 0.5
                    )
            }
            .accessibilityHidden(true)
    }
}

enum SelectorPalette {
    static let surface = Color(nsColor: .windowBackgroundColor)

    static let fieldNSColor = dynamic(
        light: rgb(248, 248, 248),
        dark: rgb(44, 44, 46)
    )
    static let selectedNSColor = dynamic(
        light: rgb(238, 238, 238),
        dark: rgb(58, 58, 60)
    )
    static let borderNSColor = dynamic(
        light: rgb(225, 225, 225),
        dark: rgb(122, 122, 126)
    )
    static let selectionBorderNSColor = dynamic(
        light: rgb(225, 225, 225),
        dark: rgb(209, 209, 214)
    )
    static let highContrastBorderNSColor = dynamic(
        light: rgb(84, 84, 88),
        dark: rgb(245, 245, 247)
    )
    static let primaryTextNSColor = dynamic(
        light: rgb(29, 29, 31),
        dark: rgb(245, 245, 247)
    )
    static let secondaryTextNSColor = dynamic(
        light: rgb(75, 75, 79),
        dark: rgb(209, 209, 214)
    )
    static let shortcutBackgroundNSColor = dynamic(
        light: rgb(255, 255, 255),
        dark: rgb(28, 28, 30)
    )
    static let badgeBackgroundNSColor = dynamic(
        light: rgb(84, 84, 88),
        dark: rgb(209, 209, 214)
    )
    static let badgeForegroundNSColor = dynamic(
        light: rgb(255, 255, 255),
        dark: rgb(28, 28, 30)
    )
    static let errorNSColor = dynamic(
        light: rgb(190, 38, 51),
        dark: rgb(255, 105, 97)
    )

    static let field = Color(nsColor: fieldNSColor)
    static let selected = Color(nsColor: selectedNSColor)
    static let border = Color(nsColor: borderNSColor)
    static let selectionBorder = Color(nsColor: selectionBorderNSColor)
    static let highContrastBorder = Color(nsColor: highContrastBorderNSColor)
    static let primaryText = Color(nsColor: primaryTextNSColor)
    static let secondaryText = Color(nsColor: secondaryTextNSColor)
    static let shortcutBackground = Color(nsColor: shortcutBackgroundNSColor)
    static let badgeBackground = Color(nsColor: badgeBackgroundNSColor)
    static let badgeForeground = Color(nsColor: badgeForegroundNSColor)
    static let error = Color(nsColor: errorNSColor)

    private static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }

    private static func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
        NSColor(
            srgbRed: red / 255,
            green: green / 255,
            blue: blue / 255,
            alpha: 1
        )
    }
}
