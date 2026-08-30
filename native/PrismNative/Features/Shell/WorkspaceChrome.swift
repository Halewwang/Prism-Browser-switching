import AppKit
import SwiftUI

enum WorkspacePalette {
    static let canvas = Color(nsColor: .underPageBackgroundColor)
    static let cardFill = Color(nsColor: .windowBackgroundColor)
    static let elevatedFill = Color(nsColor: .windowBackgroundColor)
    static let pillFill = Color(nsColor: .windowBackgroundColor)
    static let sceneFill = Color.primary.opacity(0.045)
    static let pageFill = Color(nsColor: .textBackgroundColor)
    static let recessedTrack = Color.primary.opacity(0.07)
    static let pillStroke = Color.primary.opacity(0.16)
    static let cardStroke = Color.primary.opacity(0.10)
    static let rowSelection = Color.primary.opacity(0.06)
    static let primaryFill = Color.primary
    static let primaryForeground = Color(nsColor: .windowBackgroundColor)
    static let productAccent = Color(red: 109 / 255, green: 93 / 255, blue: 254 / 255)
    static let accent = Color.accentColor
}

struct WorkspacePageHeader<Trailing: View>: View {
    let title: LocalizedStringKey
    let headingIdentifier: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(WorkspaceLayout.pageTitleFont)
                .accessibilityIdentifier(headingIdentifier)
            Spacer(minLength: 20)
            trailing()
        }
        .padding(.horizontal, WorkspaceLayout.contentInset)
        .padding(.top, WorkspaceLayout.headerVerticalInset)
        .padding(.bottom, 12)
    }
}

extension WorkspacePageHeader where Trailing == EmptyView {
    init(title: LocalizedStringKey, headingIdentifier: String) {
        self.init(title: title, headingIdentifier: headingIdentifier) { EmptyView() }
    }
}

struct WorkspaceSentence<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            content()
        }
        .font(.body)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct WorkspacePrimaryCapsuleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(WorkspacePalette.primaryForeground)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(WorkspacePalette.primaryFill, in: Capsule())
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

struct WorkspaceSecondaryCapsuleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(WorkspacePalette.elevatedFill, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(WorkspacePalette.pillStroke, lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

struct WorkspaceSegmentedTrack<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: LocalizedStringKey)]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                Button {
                    selection = option.value
                } label: {
                    Text(option.title)
                        .font(.body.weight(selection == option.value ? .semibold : .regular))
                        .foregroundStyle(selection == option.value ? Color.primary : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .background {
                            if selection == option.value {
                                Capsule()
                                    .fill(WorkspacePalette.elevatedFill)
                                    .shadow(color: .black.opacity(0.10), radius: 3, y: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(WorkspacePalette.recessedTrack, in: Capsule())
        .accessibilityElement(children: .contain)
    }
}

struct WorkspaceInlinePill<Selection: Hashable>: View {
    @Binding var selection: Selection
    var title: String
    var accessibilityIdentifier: String?
    var accessibilityLabel: LocalizedStringKey?
    var isDisabled = false
    var options: [WorkspaceInlineOption<Selection>]

    var body: some View {
        Menu {
            ForEach(options) { option in
                if let identifier = option.accessibilityIdentifier, !identifier.isEmpty {
                    Button(option.title) { selection = option.value }
                        .accessibilityIdentifier(identifier)
                } else {
                    Button(option.title) { selection = option.value }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(LocalizedStringKey(title))
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(WorkspacePalette.pillFill, in: RoundedRectangle(cornerRadius: WorkspaceLayout.pillRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: WorkspaceLayout.pillRadius, style: .continuous)
                    .stroke(WorkspacePalette.pillStroke, lineWidth: 1)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .tint(.primary)
        .disabled(isDisabled)
        .fixedSize()
        .opacity(isDisabled ? 0.45 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel ?? LocalizedStringKey(title))
        .accessibilityValue(Text(LocalizedStringKey(title)))
        .modifier(WorkspaceOptionalIdentifier(accessibilityIdentifier))
    }
}

struct WorkspaceInlineOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    var accessibilityIdentifier: String?
    var id: Value { value }
}

struct WorkspaceOnOffPill: View {
    @Binding var isOn: Bool
    var accessibilityIdentifier: String
    var accessibilityLabel: LocalizedStringKey
    var isDisabled = false
    var onTitle: String = String(localized: "On")
    var offTitle: String = String(localized: "Off")

    var body: some View {
        WorkspaceInlinePill(
            selection: $isOn,
            title: isOn ? onTitle : offTitle,
            accessibilityIdentifier: accessibilityIdentifier,
            accessibilityLabel: accessibilityLabel,
            isDisabled: isDisabled,
            options: [
                WorkspaceInlineOption(value: true, title: onTitle),
                WorkspaceInlineOption(value: false, title: offTitle),
            ]
        )
    }
}

