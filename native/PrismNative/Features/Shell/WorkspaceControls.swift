import SwiftUI

struct WorkspaceButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, quiet }
    let kind: Kind
    var height: CGFloat = 37
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, kind == .quiet ? 0 : 16)
            .frame(height: height)
            .foregroundStyle(kind == .primary ? SettingsPalette.actionText : SettingsPalette.primary)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(kind == .primary ? SettingsPalette.action : kind == .secondary ? SettingsPalette.group : .clear)
            }
            .overlay {
                if kind == .secondary {
                    RoundedRectangle(cornerRadius: 8).stroke(SettingsPalette.border, lineWidth: 1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .opacity(isEnabled ? configuration.isPressed ? 0.72 : 1 : 0.4)
    }
}

struct WorkspaceToggleStyle: ToggleStyle {
    var showsLabel = false
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            if showsLabel {
                configuration.label.font(.system(size: 13))
                Spacer(minLength: 12)
            }
            Button {
                configuration.isOn.toggle()
            } label: {
                Capsule()
                    .fill(configuration.isOn ? SettingsPalette.action : SettingsPalette.switchOff)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle().fill(configuration.isOn ? SettingsPalette.actionText : .white).frame(width: 14, height: 14).padding(2)
                    }
                    .frame(width: 34, height: 18)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
                .toggleStyle(.switch)
        }
    }
}

struct WorkspaceInputField: View {
    let placeholder: String
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(LocalizedStringKey(placeholder), text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .focused($isFocused)
            .padding(.horizontal, 11)
            .frame(height: 36)
            .background(SettingsPalette.group, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isFocused ? SettingsPalette.primary : SettingsPalette.border, lineWidth: isFocused ? 2 : 1)
            }
    }
}

struct WorkspacePickerOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    var accessibilityIdentifier: String? = nil
    var id: Value { value }
}

struct WorkspacePicker<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [WorkspacePickerOption<Value>]
    @State private var isPresented = false
    @State private var highlightedIndex = 0
    @FocusState private var optionsFocused: Bool
    @FocusState private var triggerFocused: Bool

    var body: some View {
        Button(action: toggleOptions) {
            HStack(spacing: 12) {
                Text(LocalizedStringKey(options.first(where: { $0.value == selection })?.title ?? title))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(SettingsPalette.secondary)
            }
            .font(.system(size: 13))
            .foregroundStyle(SettingsPalette.primary)
            .padding(.horizontal, 11)
            .frame(height: 36)
            .background(SettingsPalette.group, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(triggerFocused ? SettingsPalette.primary : SettingsPalette.border, lineWidth: triggerFocused ? 2 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .focusable()
        .focused($triggerFocused)
        .onKeyPress(.space) {
            toggleOptions()
            return .handled
        }
        .onKeyPress(.return) {
            toggleOptions()
            return .handled
        }
        .onKeyPress(.escape) {
            guard isPresented else { return .ignored }
            isPresented = false
            return .handled
        }
        .help(LocalizedStringKey(options.first(where: { $0.value == selection })?.title ?? title))
        .accessibilityLabel(LocalizedStringKey(title))
        .accessibilityValue(Text(LocalizedStringKey(options.first(where: { $0.value == selection })?.title ?? title)))
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            ScrollViewReader { proxy in
              ScrollView {
               VStack(spacing: 3) {
                ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                    Button {
                        selection = option.value
                        isPresented = false
                    } label: {
                        HStack(spacing: 12) {
                            Text(LocalizedStringKey(option.title))
                                .lineLimit(1)
                            Spacer(minLength: 12)
                            Image(systemName: "checkmark")
                                .opacity(option.value == selection ? 1 : 0)
                        }
                        .font(.system(size: 13))
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                        .foregroundStyle(index == highlightedIndex ? SettingsPalette.actionText : SettingsPalette.primary)
                        .background(index == highlightedIndex ? SettingsPalette.action : .clear, in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(LocalizedStringKey(option.title))
                    .accessibilityIdentifier(option.accessibilityIdentifier ?? "")
                    .accessibilityAddTraits(option.value == selection ? .isSelected : [])
                    .onHover { if $0 { highlightedIndex = index } }
                    .id(index)
                }
               }
               .padding(6)
              }
              .frame(width: 260, height: min(320, CGFloat(options.count) * 35 + 9))
              .onChange(of: highlightedIndex) { _, index in proxy.scrollTo(index) }
            }
            .background(SettingsPalette.group)
            .focusable()
            .focused($optionsFocused)
            .defaultFocus($optionsFocused, true)
            .onAppear { optionsFocused = true }
            .onDisappear {
                guard !isPresented else { return }
                optionsFocused = false
                triggerFocused = true
            }
            .onKeyPress(.upArrow) {
                highlightedIndex = max(0, highlightedIndex - 1)
                return .handled
            }
            .onKeyPress(.downArrow) {
                highlightedIndex = min(options.count - 1, highlightedIndex + 1)
                return .handled
            }
            .onKeyPress(.return) {
                if options.indices.contains(highlightedIndex) { selection = options[highlightedIndex].value }
                isPresented = false
                return .handled
            }
            .onKeyPress(.escape) {
                isPresented = false
                return .handled
            }
        }
        .onChange(of: isPresented) { _, presented in
            if !presented {
                optionsFocused = false
                triggerFocused = true
            }
        }
    }

    private func toggleOptions() {
        highlightedIndex = options.firstIndex(where: { $0.value == selection }) ?? 0
        optionsFocused = false
        triggerFocused = false
        isPresented.toggle()
    }
}
