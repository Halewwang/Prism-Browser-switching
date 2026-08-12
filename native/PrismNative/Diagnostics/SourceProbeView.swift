#if DEBUG
import Foundation
import Observation
import PrismCore
import SwiftUI

enum SourceProbeRunState: String, Codable, CaseIterable, Identifiable {
    case cold
    case warm

    var id: String { rawValue }
}

enum SourceProbeExpectedSource: String, CaseIterable, Identifiable {
    case dingTalk = "DingTalk"
    case lark = "Lark"
    case weChat = "WeChat"
    case slack = "Slack"
    case finder = "Finder"
    case terminal = "Terminal"
    case safari = "Safari"
    case chrome = "Chrome"
    case arc = "Arc"

    var id: String { rawValue }

    static func matching(_ value: String) -> SourceProbeExpectedSource? {
        allCases.first { $0.rawValue.caseInsensitiveCompare(value) == .orderedSame }
    }
}

enum SourceProbeRecorderError: Error {
    case noCapturedSource
    case invalidExpectedSource
}

@MainActor
@Observable
final class SourceProbeRecorder {
    private struct EvidenceRow: Codable {
        let timestamp: Date
        let appName: String
        let bundleIdentifier: String?
        let senderPIDPresent: Bool
        let confidence: SourceConfidence
        let expectedSource: String
        let runState: SourceProbeRunState
        let passed: Bool
    }

    let fileURL: URL
    private(set) var latestCapture: LinkCaptureDiagnostic?
    private(set) var savedRowCount = 0

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    static func makeDefault() -> SourceProbeRecorder {
        SourceProbeRecorder(
            fileURL: URL.applicationSupportDirectory
                .appending(path: "Prism")
                .appending(path: "Diagnostics")
                .appending(path: "source-probe-v1.jsonl")
        )
    }

    func record(_ diagnostic: LinkCaptureDiagnostic) {
        latestCapture = diagnostic
    }

    func appendEvidence(
        expectedSource: String,
        runState: SourceProbeRunState,
        passed: Bool
    ) throws {
        guard let capture = latestCapture else {
            throw SourceProbeRecorderError.noCapturedSource
        }
        let candidate = expectedSource.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let expectedApplication = SourceProbeExpectedSource.matching(candidate) else {
            throw SourceProbeRecorderError.invalidExpectedSource
        }
        let expected = expectedApplication.rawValue

        let verifiedPass = passed
            && capture.confidence == .confirmed
            && capture.sourceBundleIdentifier?.isEmpty == false
            && capture.sourceDisplayName.localizedCaseInsensitiveContains(expected)
        let row = EvidenceRow(
            timestamp: capture.timestamp,
            appName: capture.sourceDisplayName,
            bundleIdentifier: capture.sourceBundleIdentifier,
            senderPIDPresent: capture.senderPIDPresent,
            confidence: capture.confidence,
            expectedSource: expected,
            runState: runState,
            passed: verifiedPass
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var data = try encoder.encode(row)
        data.append(0x0A)

        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            guard FileManager.default.createFile(atPath: fileURL.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try handle.synchronize()
        savedRowCount += 1
    }
}

struct SourceProbeView: View {
    let recorder: SourceProbeRecorder
    @State private var expectedSource = SourceProbeExpectedSource.safari
    @State private var runState = SourceProbeRunState.cold
    @State private var passed = true
    @State private var status = "Waiting for an HTTP or HTTPS link"

    var body: some View {
        Form {
            Section("Captured source") {
                LabeledContent("App", value: recorder.latestCapture?.sourceDisplayName ?? "Unknown")
                LabeledContent("Bundle ID", value: recorder.latestCapture?.sourceBundleIdentifier ?? "Unknown")
                LabeledContent("Sender PID present", value: recorder.latestCapture?.senderPIDPresent == true ? "Yes" : "No")
                LabeledContent("Confidence", value: recorder.latestCapture?.confidence.rawValue ?? "unknown")
            }
            Section("Evidence") {
                Picker("Expected source application", selection: $expectedSource) {
                    ForEach(SourceProbeExpectedSource.allCases) { source in
                        Text(source.rawValue).tag(source)
                    }
                }
                Picker("State", selection: $runState) {
                    ForEach(SourceProbeRunState.allCases) { state in
                        Text(state.rawValue.capitalized).tag(state)
                    }
                }
                Toggle("Attribution passed", isOn: $passed)
                Button("Save diagnostic row") {
                    do {
                        try recorder.appendEvidence(
                            expectedSource: expectedSource.rawValue,
                            runState: runState,
                            passed: passed
                        )
                        status = "Saved row \(recorder.savedRowCount)"
                    } catch {
                        status = "The diagnostic row was not saved"
                    }
                }
                .disabled(recorder.latestCapture == nil)
            }
            Text(status)
                .foregroundStyle(.secondary)
            Text(recorder.fileURL.path)
                .font(.caption.monospaced())
                .textSelection(.enabled)
        }
        .formStyle(.grouped)
        .frame(minWidth: 560, minHeight: 420)
    }
}
#endif
