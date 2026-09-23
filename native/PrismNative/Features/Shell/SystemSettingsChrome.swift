import AppKit
import SwiftUI

struct PageColumn<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    content()
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 24)
                .frame(width: proxy.size.width, alignment: .top)
            }
        }
        .background(SettingsPalette.canvas)
    }
}

struct SystemSettingsPageHeader: View {
    let title: String
    let subtitle: String
    let accessibilityIdentifier: String

    var body: some View {
        Text(LocalizedStringKey(subtitle))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .accessibilityIdentifier(accessibilityIdentifier)
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel(Text(LocalizedStringKey(title)))
    }
}

struct SettingsGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SettingsPalette.group, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct SettingsSeparator: View {
    var leadingInset: CGFloat = 52

    var body: some View {
        Divider()
            .padding(.leading, leadingInset)
    }
}

enum SettingsPalette {
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let group = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor.white.withAlphaComponent(0.06)
            : NSColor.black.withAlphaComponent(0.04)
    }))
    static let iconWell = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor.white.withAlphaComponent(0.12)
            : NSColor.black.withAlphaComponent(0.06)
    }))
}
