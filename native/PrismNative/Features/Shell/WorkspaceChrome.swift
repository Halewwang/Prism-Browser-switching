import SwiftUI

struct WorkspacePageHeader<Trailing: View>: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let headingIdentifier: String
    @ViewBuilder var trailing: () -> Trailing

    init(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        headingIdentifier: String,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.headingIdentifier = headingIdentifier
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(WorkspaceLayout.pageTitleFont)
                    .accessibilityIdentifier(headingIdentifier)
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 20)
            trailing()
        }
        .padding(.horizontal, WorkspaceLayout.contentInset)
        .padding(.vertical, WorkspaceLayout.headerVerticalInset)
    }
}

extension WorkspacePageHeader where Trailing == EmptyView {
    init(title: LocalizedStringKey, subtitle: LocalizedStringKey, headingIdentifier: String) {
        self.init(
            title: title,
            subtitle: subtitle,
            headingIdentifier: headingIdentifier
        ) {
            EmptyView()
        }
    }
}

struct WorkspaceSettingsGroup<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WorkspaceSentence<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            content()
            Spacer(minLength: 0)
        }
        .font(.body)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct WorkspaceSentenceRow<Control: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var control: () -> Control

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
            control()
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct WorkspaceMenuPill<Selection: Hashable, Content: View>: View {
    @Binding var selection: Selection
    var accessibilityIdentifier: String?
    var isDisabled = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        Picker("", selection: $selection) {
            content()
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .disabled(isDisabled)
        .fixedSize()
        .modifier(WorkspaceOptionalIdentifier(accessibilityIdentifier))
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

struct WorkspaceOnOffPill: View {
    @Binding var isOn: Bool
    var accessibilityIdentifier: String
    var accessibilityLabel: LocalizedStringKey
    var isDisabled = false

    var body: some View {
        Picker(accessibilityLabel, selection: $isOn) {
            Text("On").tag(true)
            Text("Off").tag(false)
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
        .disabled(isDisabled)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isOn ? Text("On") : Text("Off"))
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

struct WorkspaceStatusPill: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(LocalizedStringKey(title), systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary, in: Capsule())
    }
}

struct WorkspaceInspectorColumn<Content: View>: View {
    let accessibilityIdentifier: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            content()
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(
            minWidth: WorkspaceLayout.inspectorMinWidth,
            idealWidth: WorkspaceLayout.inspectorIdealWidth,
            maxWidth: WorkspaceLayout.inspectorMaxWidth
        )
        .frame(maxHeight: .infinity)
        .background {
            Rectangle()
                .fill(.regularMaterial)
        }
        .overlay(alignment: .leading) {
            Divider()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

struct WorkspaceInspectorPlaceholder: View {
    let systemImage: String
    let message: LocalizedStringKey

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 220)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }
}

struct WorkspaceMasterDetail<ListContent: View, InspectorContent: View>: View {
    let inspectorIdentifier: String
    @ViewBuilder var list: () -> ListContent
    @ViewBuilder var inspector: () -> InspectorContent

    var body: some View {
        HStack(spacing: 0) {
            list()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            WorkspaceInspectorColumn(accessibilityIdentifier: inspectorIdentifier) {
                inspector()
            }
        }
    }
}
