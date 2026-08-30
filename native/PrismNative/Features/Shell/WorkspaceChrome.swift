import AppKit
import SwiftUI

enum WorkspacePalette {
    static let canvas = Color(nsColor: .underPageBackgroundColor)
    static let cardFill = Color(nsColor: .windowBackgroundColor)
    static let elevatedFill = Color(nsColor: .windowBackgroundColor)
    static let pillFill = Color(nsColor: .windowBackgroundColor)
    static let tileFill = Color.primary.opacity(0.045)
    static let recessedTrack = Color.primary.opacity(0.07)
    static let pillStroke = Color.primary.opacity(0.16)
    static let cardStroke = Color.primary.opacity(0.10)
    static let rowSelection = Color.primary.opacity(0.06)
    static let primaryFill = Color.primary
    static let primaryForeground = Color(nsColor: .windowBackgroundColor)
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

struct WorkspaceWindowPreview<Content: View>: View {
    var accessibilityIdentifier: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(Color(red: 1, green: 0.38, blue: 0.37)).frame(width: 8, height: 8)
                Circle().fill(Color(red: 1, green: 0.76, blue: 0.23)).frame(width: 8, height: 8)
                Circle().fill(Color(red: 0.19, green: 0.80, blue: 0.35)).frame(width: 8, height: 8)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .accessibilityHidden(true)

            content()
                .frame(maxWidth: .infinity, minHeight: WorkspaceLayout.previewMinHeight - 40, maxHeight: .infinity)
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, minHeight: WorkspaceLayout.previewMinHeight)
        .background(WorkspacePalette.cardFill, in: RoundedRectangle(cornerRadius: WorkspaceLayout.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: WorkspaceLayout.cardRadius, style: .continuous)
                .stroke(WorkspacePalette.cardStroke, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.07), radius: 14, y: 5)
        .modifier(WorkspaceOptionalIdentifier(accessibilityIdentifier))
    }
}

struct WorkspacePreviewTile: View {
    var title: String
    var systemImage: String?
    var icon: NSImage?
    var isHighlighted = false

    var body: some View {
        VStack(spacing: 8) {
            Group {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 36, height: 36)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.title2)
                        .foregroundStyle(isHighlighted ? WorkspacePalette.accent : Color.secondary)
                }
            }
            .frame(width: 44, height: 44)

            Text(LocalizedStringKey(title))
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
            .frame(width: 92, height: 92)
        .background(WorkspacePalette.tileFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isHighlighted ? WorkspacePalette.accent : WorkspacePalette.cardStroke, lineWidth: isHighlighted ? 2 : 1)
        }
    }
}

private struct WorkspaceOptionalIdentifier: ViewModifier {
    let identifier: String?

    init(_ identifier: String?) {
        self.identifier = identifier
    }

    func body(content: Content) -> some View {
        if let identifier {
            content.accessibilityIdentifier(identifier)
        } else {
            content
        }
    }
}
