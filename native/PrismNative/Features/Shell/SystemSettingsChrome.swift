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
                .padding(.horizontal, WorkspaceLayout.contentInset)
                .padding(.top, 32)
                .padding(.bottom, 28)
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
                .foregroundStyle(SettingsPalette.primary)
                .accessibilityIdentifier(accessibilityIdentifier)
                .accessibilityAddTraits(.isHeader)
            Text(LocalizedStringKey(subtitle))
                .font(.system(size: 14))
                .foregroundStyle(SettingsPalette.secondary)
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
                    .font(.system(size: 13))
                    .foregroundStyle(SettingsPalette.secondary)
                    .accessibilityHidden(true)
            }
            Text(LocalizedStringKey(title))
                .font(.system(size: 14, weight: .medium))
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let detail {
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(SettingsPalette.secondary)
            }
        }
        .foregroundStyle(SettingsPalette.primary)
        .padding(.horizontal, 2)
    }
}

struct WorkspaceSearchField: View {
    let placeholder: String
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(SettingsPalette.secondary)
                .accessibilityHidden(true)
            TextField(LocalizedStringKey(placeholder), text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
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
        .padding(.horizontal, 11)
        .frame(height: 36)
        .background(SettingsPalette.group, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isFocused ? SettingsPalette.primary : SettingsPalette.border, lineWidth: isFocused ? 2 : 1)
        }
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
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct SettingsSeparator: View {
    var leadingInset: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(SettingsPalette.border)
            .frame(height: 1)
            .padding(.leading, leadingInset)
            .accessibilityHidden(true)
    }
}

enum SettingsPalette {
    static let canvas = adaptive(light: 0.988, dark: 0.10)
    static let sidebar = adaptive(light: 0.937, dark: 0.14)
    static let group = adaptive(light: 1, dark: 0.135)
    static let iconWell = adaptive(light: 0.965, dark: 0.19)
    static let border = adaptive(light: 0.937, dark: 0.22)
    static let action = adaptive(light: 0.149, dark: 0.87)
    static let actionText = adaptive(light: 1, dark: 0.12)
    static let switchOff = adaptive(light: 0.82, dark: 0.32)
    static let primary = Color(nsColor: .labelColor)
    static let secondary = adaptive(light: 0.40, dark: 0.64)

    private static func adaptive(light: CGFloat, dark: CGFloat) -> Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(white: value, alpha: 1)
        }))
    }
}
