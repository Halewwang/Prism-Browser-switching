import SwiftUI
import Testing
@testable import PrismNative

@Suite("Searchable workspace picker")
@MainActor
struct WorkspacePickerFilteringTests {
    private let options = [
        WorkspacePickerOption(value: "com.example.notes", title: "Notes", searchText: "com.example.notes"),
        WorkspacePickerOption(value: "com.example.browser", title: "Browser", searchText: "com.example.browser"),
        WorkspacePickerOption(value: "com.example.other", title: "Other")
    ]

    @Test func findsAnApplicationByItsNameOrBundleIdentifier() {
        #expect(WorkspacePicker<String>.matchingOptions(options, query: "noTES").map(\.value) == ["com.example.notes"])
        #expect(WorkspacePicker<String>.matchingOptions(options, query: " example.browser ").map(\.value) == ["com.example.browser"])
    }

    @Test func blankQueryRestoresAllOptionsAndMissingQueryReturnsNone() {
        #expect(WorkspacePicker<String>.matchingOptions(options, query: " ").map(\.value) == options.map(\.value))
        #expect(WorkspacePicker<String>.matchingOptions(options, query: "missing").isEmpty)
    }
}
