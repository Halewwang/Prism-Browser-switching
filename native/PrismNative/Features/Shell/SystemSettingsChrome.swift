import AppKit
import SwiftUI

struct PageColumn<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    content()
                }
                .frame(maxWidth: 880, alignment: .leading)
                .padding(.horizontal, WorkspaceLayout.contentInset)
                .padding(.top, 32)
                .padding(.bottom, 24)
                .frame(width: proxy.size.width, alignment: .topLeading)
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
        VStack(alignment: .leading, spacing: 7) {
            Text(LocalizedStringKey(title))
                .font(WorkspaceLayout.pageTitleFont)
                .frame(minHeight: 39, alignment: .leading)
                .foregroundStyle(SettingsPalette.primary)
                .accessibilityIdentifier(accessibilityIdentifier)
                .accessibilityAddTraits(.isHeader)
            Text(LocalizedStringKey(subtitle))
                .font(.system(size: 14))
                .foregroundStyle(SettingsPalette.tertiary)
                .frame(minHeight: 20, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WorkspaceSectionHeader: View {
    let title: String
    var detail: String? = nil
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 7) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 14))
                    .frame(width: 16, height: 16)
                    .foregroundStyle(SettingsPalette.iconDefault)
                    .accessibilityHidden(true)
            }
            Text(LocalizedStringKey(title))
                .font(.system(size: 14, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let detail {
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(SettingsPalette.secondary)
            }
        }
        .foregroundStyle(SettingsPalette.tertiary)
        .frame(minHeight: 20)
    }
}

struct WorkspaceSearchField: View {
    let placeholder: String
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16))
                .frame(width: 16, height: 16)
                .foregroundStyle(SettingsPalette.iconMuted)
                .accessibilityHidden(true)
            TextField(LocalizedStringKey(placeholder), text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($isFocused)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(SettingsPalette.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
                .accessibilityIdentifier("workspace.search.clear.\(placeholder)")
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 35)
        .background(SettingsPalette.group, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isFocused ? SettingsPalette.primary : SettingsPalette.border, lineWidth: isFocused ? 2 : 1)
        }
    }
}

struct SettingsGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SettingsPalette.group, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(contrast == .increased ? SettingsPalette.borderStrong : SettingsPalette.borderSubtle, lineWidth: 1)
        }
    }
}

struct SettingsSeparator: View {
    var leadingInset: CGFloat = 0
    var color: Color = SettingsPalette.border

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(height: 1)
            .padding(.leading, leadingInset)
            .accessibilityHidden(true)
    }
}

enum SettingsPalette {
    static let window = adaptive(light: 0xF6F6F6, dark: 0x1C1C1E)
    static let canvas = adaptive(light: 0xFCFCFC, dark: 0x303032)
    static let elevated = canvas
    static let sidebar = adaptive(light: 0xEFEFEF, dark: 0x3A3A3C)
    static let group = adaptive(light: 0xFFFFFF, dark: 0x2A2A2C)
    static let iconWell = window
    static let border = adaptive(light: 0xE7E7E7, dark: 0x3F3F42)
    static let borderSubtle = adaptive(light: 0xEFEFEF, dark: 0x343437)
    static let borderStrong = adaptive(light: 0xD7D7D7, dark: 0x5A5A5E)
    static let action = adaptive(light: 0x262626, dark: 0xF0F0F0)
    static let actionText = adaptive(light: 0xFFFFFF, dark: 0x111111)
    static let switchOff = borderStrong
    static let toggleKnob = adaptive(light: 0xFFFFFF, dark: 0x1C1C1E)
    static let primary = adaptive(light: 0x2C2C2C, dark: 0xF2F2F2)
    static let secondary = adaptive(light: 0x4A4A4A, dark: 0xD4D4D4)
    static let tertiary = adaptive(light: 0x686868, dark: 0xA3A3A3)
    static let muted = adaptive(light: 0x7A7A7A, dark: 0x8A8A8A)
    static let danger = adaptive(light: 0xB3261E, dark: 0xFF6961)
    static let surfacePressed = adaptive(light: 0xE7E7E7, dark: 0x48484A)
    static let statusOK = adaptive(light: 0x3C3C3C, dark: 0xDADADA)
    static let iconStrong = adaptive(light: 0x333333, dark: 0xE6E6E6)
    static let iconDefault = adaptive(light: 0x777777, dark: 0xA8A8A8)
    static let iconMuted = adaptive(light: 0x999999, dark: 0x7C7C7C)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(
                red: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: 1
            )
        }))
    }
}
