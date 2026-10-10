import SwiftUI

struct WorkspaceButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, quiet }
    let kind: Kind
    var height: CGFloat = 37
    var horizontalPadding: CGFloat? = nil
    var fontSize: CGFloat = 13
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: fontSize, weight: .medium))
            .padding(.horizontal, horizontalPadding ?? (kind == .quiet ? 0 : 16))
            .frame(height: height)
            .foregroundStyle(kind == .primary ? SettingsPalette.actionText : kind == .secondary ? SettingsPalette.secondary : SettingsPalette.tertiary)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(kind == .primary ? SettingsPalette.action : kind == .secondary ? SettingsPalette.group : .clear)
            }
            .overlay {
                if kind == .secondary {
                    RoundedRectangle(cornerRadius: 8).stroke(SettingsPalette.borderStrong, lineWidth: 1)
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
                        Circle().fill(SettingsPalette.toggleKnob).frame(width: 16, height: 16).padding(2)
                    }
                    .frame(width: 34, height: 20)
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
            .font(.system(size: 14))
            .focused($isFocused)
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(SettingsPalette.group, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isFocused ? SettingsPalette.action : SettingsPalette.border, lineWidth: isFocused ? 2 : 1)
            }
    }
}

struct WorkspacePickerOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    var accessibilityIdentifier: String? = nil
    var searchText: String? = nil
    var id: Value { value }
}

struct WorkspacePicker<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [WorkspacePickerOption<Value>]
    var compact = false
    var searchPlaceholder: String? = nil
    @State private var searchQuery = ""
    @State private var isPresented = false
    @State private var highlightedIndex = 0
    @FocusState private var optionsFocused: Bool
    @FocusState private var triggerFocused: Bool

    var body: some View {
        Button(action: toggleOptions) {
            HStack(spacing: compact ? 6 : 12) {
                Text(LocalizedStringKey(options.first(where: { $0.value == selection })?.title ?? title))
                    .lineLimit(1)
                if !compact { Spacer(minLength: 0) }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: compact ? 12 : 14, weight: .regular))
                    .foregroundStyle(SettingsPalette.iconMuted)
                    .frame(width: 14, height: 14)
            }
            .font(.system(size: compact ? 13 : 14))
            .foregroundStyle(compact ? SettingsPalette.tertiary : SettingsPalette.secondary)
            .padding(.horizontal, compact ? 10 : 14)
            .frame(height: compact ? 31 : 44)
            .background(compact ? SettingsPalette.elevated : SettingsPalette.group, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(triggerFocused ? SettingsPalette.action : SettingsPalette.border, lineWidth: triggerFocused ? 2 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .focusable()
        .focusEffectDisabled()
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
          VStack(spacing: 0) {
            if let searchPlaceholder {
                WorkspaceSearchField(placeholder: searchPlaceholder, text: $searchQuery)
                    .padding(6)
                    .onSubmit { selectHighlightedOption() }
                    .accessibilityIdentifier("workspace.picker.search.\(title)")
            }
            ScrollViewReader { proxy in
              ScrollView {
               VStack(spacing: 3) {
                ForEach(Array(filteredOptions.enumerated()), id: \.element.id) { index, option in
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
                if filteredOptions.isEmpty {
                    Text(String(localized: "picker.search.empty", defaultValue: "No matching options"))
                        .font(.system(size: 13))
                        .foregroundStyle(SettingsPalette.tertiary)
                        .padding(10)
                }
               }
               .padding(6)
              }
              .frame(width: 260, height: min(320, max(44, CGFloat(filteredOptions.count) * 35 + 9)))
              .onChange(of: highlightedIndex) { _, index in proxy.scrollTo(index) }
            }
          }
            .background(SettingsPalette.group)
            .onChange(of: searchQuery) { _, _ in highlightedIndex = 0 }
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
                highlightedIndex = min(max(0, filteredOptions.count - 1), highlightedIndex + 1)
                return .handled
            }
            .onKeyPress(.return) {
                selectHighlightedOption()
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

    private var filteredOptions: [WorkspacePickerOption<Value>] {
        Self.matchingOptions(options, query: searchPlaceholder == nil ? "" : searchQuery)
    }

    static func matchingOptions(_ options: [WorkspacePickerOption<Value>], query: String) -> [WorkspacePickerOption<Value>] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? options : options.filter {
            $0.title.localizedStandardContains(query) || ($0.searchText?.localizedStandardContains(query) ?? false)
        }
    }

    private func selectHighlightedOption() {
        guard filteredOptions.indices.contains(highlightedIndex) else { return }
        selection = filteredOptions[highlightedIndex].value
        isPresented = false
    }

    private func toggleOptions() {
        searchQuery = ""
        highlightedIndex = options.firstIndex(where: { $0.value == selection }) ?? 0
        optionsFocused = false
        triggerFocused = false
        isPresented.toggle()
    }
}
