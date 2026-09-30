import Foundation
import Darwin

@_silgen_name("proc_pidpath")
private func installerProcPIDPath(_ pid: Int32, _ buffer: UnsafeMutableRawPointer, _ size: UInt32) -> Int32

@_silgen_name("prism_installer_pid_identity")
private func installerPIDIdentity(_ pid: Int32, _ seconds: UnsafeMutablePointer<UInt64>, _ microseconds: UnsafeMutablePointer<UInt64>, _ uid: UnsafeMutablePointer<UInt32>) -> Int32

struct InstallerSystem {
    static func run(_ executable: String, _ arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UpdateInstallationError.invalidApplication }
        return data
    }

    static func parentIdentity(pid: Int32) throws -> InstallerParentIdentity {
        guard pid > 1 else { throw UpdateInstallationError.parentMismatch }
        var buffer = [UInt8](repeating: 0, count: 4096)
        let count = buffer.withUnsafeMutableBytes { installerProcPIDPath(pid, $0.baseAddress!, UInt32($0.count)) }
        guard count > 0 else { throw UpdateInstallationError.parentMismatch }
        let path = String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
        var seconds: UInt64 = 0
        var microseconds: UInt64 = 0
        var uid: UInt32 = 0
        guard installerPIDIdentity(pid, &seconds, &microseconds, &uid) == 1 else { throw UpdateInstallationError.parentMismatch }
        return .init(pid: pid, startTime: "\(seconds).\(microseconds)", executablePath: path, userID: uid)
    }

    static func version(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url.appendingPathComponent("Contents/Info.plist"))
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any], let value = plist["CFBundleShortVersionString"] as? String else { throw UpdateInstallationError.invalidApplication }
        return value
    }

    static func versionParts(_ value: String) throws -> [Int] {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { throw UpdateInstallationError.invalidVersion }
        return try parts.map {
            guard !$0.isEmpty, $0.allSatisfy({ $0.isASCII && $0.isNumber }), let number = Int($0), number >= 0 else { throw UpdateInstallationError.invalidVersion }
            return number
        }
    }

    static func requireUpgrade(_ version: String, from current: String) throws {
        let candidate = try versionParts(version)
        let installed = try versionParts(current)
        guard installed.lexicographicallyPrecedes(candidate) else { throw UpdateInstallationError.invalidVersion }
    }

    static func validateApplication(_ url: URL, expectedVersion: String?) throws {
        let plistURL = url.appendingPathComponent("Contents/Info.plist")
        let data = try Data(contentsOf: plistURL)
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              plist["CFBundleIdentifier"] as? String == PrismUpdateTrust.bundleIdentifier,
              let version = plist["CFBundleShortVersionString"] as? String,
              let executable = plist["CFBundleExecutable"] as? String,
              executable == "Prism",
              let minimum = plist["LSMinimumSystemVersion"] as? String else { throw UpdateInstallationError.invalidApplication }
        _ = try versionParts(version)
        if let expectedVersion, expectedVersion != version { throw UpdateInstallationError.invalidApplication }
        let minimumTokens = minimum.split(separator: ".", omittingEmptySubsequences: false)
        let minimumParts = minimumTokens.compactMap { Int($0) }
        guard minimumParts.count == minimumTokens.count, minimumTokens.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }), minimumParts.count >= 1, minimumParts.count <= 3 else { throw UpdateInstallationError.invalidApplication }
        let required = OperatingSystemVersion(majorVersion: minimumParts[0], minorVersion: minimumParts.count > 1 ? minimumParts[1] : 0, patchVersion: minimumParts.count > 2 ? minimumParts[2] : 0)
        guard ProcessInfo.processInfo.isOperatingSystemAtLeast(required), FileManager.default.isExecutableFile(atPath: url.appendingPathComponent("Contents/MacOS/Prism").path) else { throw UpdateInstallationError.invalidApplication }
        _ = try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", url.path])
    }

    static func validateControlDirectory(_ url: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard url.path == url.resolvingSymlinksInPath().path,
              attributes[.type] as? FileAttributeType == .typeDirectory,
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
              ((attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0) & 0o077 == 0 else { throw UpdateInstallationError.unsafePath }
    }
}
