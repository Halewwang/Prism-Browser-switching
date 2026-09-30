import CryptoKit
import Darwin
import Foundation
import Security

@_silgen_name("prism_installer_pid_architecture")
private func installerPIDArchitecture(_ pid: Int32, _ type: UnsafeMutablePointer<Int32>, _ subtype: UnsafeMutablePointer<Int32>) -> Int32

struct InstallerCodeIdentity: Sendable, Equatable {
    var codeHash: Data
    var signingIdentifier: String
    var bundleIdentifier: String
    var version: String
    var minimumSystemVersion: String
    var executable: String
    var executableHash: Data = Data()
}

/// Verifies a kernel guest against the authenticated installed code. No private
/// translocation API, path-string bypass, or quarantine removal is used.
struct InstallerLaunchValidation {
    static let installedPathEnvironmentKey = "PRISM_UPDATE_INSTALLED_APP_PATH"
    private static let strictFlags = SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckNestedCode | kSecCSCheckAllArchitectures)

    static func currentInstallationURL(bundleURL: URL = Bundle.main.bundleURL, pid: Int32 = getpid(), environment: [String: String] = ProcessInfo.processInfo.environment) throws -> URL {
        let parent = try InstallerSystem.parentIdentity(pid: pid)
        let runningURL = applicationURL(for: parent.executablePath)
        let isProtected = try isProtectedRuntimeLocation(runningURL)
        let target: URL
        if isProtected {
            guard let hint = environment[installedPathEnvironmentKey] else { throw UpdateInstallationError.unsafePath }
            target = URL(fileURLWithPath: hint).standardizedFileURL
        } else {
            target = bundleURL.standardizedFileURL
            // A foreign environment hint must never redirect a normally running
            // instance to replace another copy, even with identical code.
            if let hint = environment[installedPathEnvironmentKey], URL(fileURLWithPath: hint).standardizedFileURL.path != target.path {
                throw UpdateInstallationError.unsafePath
            }
        }
        try validateTargetLocation(target)
        let version = try InstallerSystem.version(bundleURL)
        try validateRunningApplication(pid: pid, targetURL: target, expectedVersion: version)
        return target
    }

    @discardableResult
    static func validateRunningApplication(pid: Int32, targetURL: URL, expectedVersion: String) throws -> InstallerCodeIdentity {
        try validateTargetLocation(targetURL)
        let before = try InstallerSystem.parentIdentity(pid: pid)
        guard before.userID == getuid() else { throw UpdateInstallationError.parentMismatch }
        let runningURL = applicationURL(for: before.executablePath)
        let normalExecutable = targetURL.appendingPathComponent("Contents/MacOS/Prism").resolvingSymlinksInPath().path
        if URL(fileURLWithPath: before.executablePath).resolvingSymlinksInPath().path != normalExecutable {
            guard try isProtectedRuntimeLocation(runningURL) else { throw UpdateInstallationError.parentMismatch }
        }
        var type: Int32 = 0
        var subtype: Int32 = 0
        guard installerPIDArchitecture(pid, &type, &subtype) == 1 else { throw UpdateInstallationError.parentMismatch }
        var targetCode: SecStaticCode?
        let attributes = [kSecCodeAttributeArchitecture as String: NSNumber(value: type), kSecCodeAttributeSubarchitecture as String: NSNumber(value: subtype)] as CFDictionary
        guard SecStaticCodeCreateWithPathAndAttributes(targetURL as CFURL, SecCSFlags(), attributes, &targetCode) == errSecSuccess,
              let targetCode,
              SecStaticCodeCheckValidity(targetCode, strictFlags, nil) == errSecSuccess else { throw UpdateInstallationError.invalidApplication }
        let expected = try identity(targetCode)
        guard expected.bundleIdentifier == PrismUpdateTrust.bundleIdentifier, expected.signingIdentifier == PrismUpdateTrust.bundleIdentifier,
              expected.version == expectedVersion, expected.executable == "Prism" else { throw UpdateInstallationError.invalidApplication }
        var guest: SecCode?
        let guestAttributes = [kSecGuestAttributePid as String: NSNumber(value: pid)] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, guestAttributes, SecCSFlags(), &guest) == errSecSuccess, let guest else { throw UpdateInstallationError.parentMismatch }
        var requirement: SecRequirement?
        let hash = expected.codeHash.map { String(format: "%02x", $0) }.joined()
        guard !hash.isEmpty,
              SecRequirementCreateWithString("cdhash H\"\(hash)\"" as CFString, SecCSFlags(), &requirement) == errSecSuccess,
              let requirement,
              SecCodeCheckValidity(guest, SecCSFlags(), requirement) == errSecSuccess else { throw UpdateInstallationError.invalidApplication }
        var guestCode: SecStaticCode?
        guard SecCodeCopyStaticCode(guest, SecCSFlags(), &guestCode) == errSecSuccess, let guestCode,
              SecStaticCodeCheckValidity(guestCode, strictFlags, nil) == errSecSuccess else { throw UpdateInstallationError.invalidApplication }
        let running = try identity(guestCode)
        let after = try InstallerSystem.parentIdentity(pid: pid)
        try compare(expected: expected, running: running, before: before, after: after, expectedPID: pid, expectedUserID: getuid())
        // The dynamic requirement check binds disk signing information to the
        // actual kernel guest, rather than trusting a static path conversion.
        guard SecCodeCheckValidity(guest, SecCSFlags(), requirement) == errSecSuccess else { throw UpdateInstallationError.invalidApplication }
        return expected
    }

    static func compare(expected: InstallerCodeIdentity, running: InstallerCodeIdentity, before: InstallerParentIdentity, after: InstallerParentIdentity, expectedPID: Int32, expectedUserID: UInt32) throws {
        guard before == after, before.pid == expectedPID, before.userID == expectedUserID,
              !expected.codeHash.isEmpty, !running.codeHash.isEmpty, !expected.executableHash.isEmpty, !running.executableHash.isEmpty, expected == running else { throw UpdateInstallationError.parentMismatch }
    }

    /// Pins all executable slices and the sealed resource identity across the
    /// parent wait; same-directory rewrites cannot reuse an inode check.
    static func diskFingerprint(_ url: URL) throws -> Data {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, SecCSFlags(), &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, strictFlags, nil) == errSecSuccess else { throw UpdateInstallationError.invalidApplication }
        let value = try identity(code)
        var hash = SHA256()
        hash.update(data: value.codeHash)
        let file = try FileHandle(forReadingFrom: url.appendingPathComponent("Contents/MacOS/Prism"))
        defer { try? file.close() }
        while let chunk = try file.read(upToCount: 1024 * 1024), !chunk.isEmpty { hash.update(data: chunk) }
        return Data(hash.finalize())
    }

    private static func identity(_ code: SecStaticCode) throws -> InstallerCodeIdentity {
        var result: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &result) == errSecSuccess,
              let info = result as? [String: Any], let hash = info[kSecCodeInfoUnique as String] as? Data,
              let identifier = info[kSecCodeInfoIdentifier as String] as? String,
              let plist = info[kSecCodeInfoPList as String] as? [String: Any],
              let bundleIdentifier = plist["CFBundleIdentifier"] as? String,
              let version = plist["CFBundleShortVersionString"] as? String,
              let minimum = plist["LSMinimumSystemVersion"] as? String,
              let executable = plist["CFBundleExecutable"] as? String else { throw UpdateInstallationError.invalidApplication }
        guard let mainURL = info[kSecCodeInfoMainExecutable as String] as? URL else { throw UpdateInstallationError.invalidApplication }
        let file = try FileHandle(forReadingFrom: mainURL)
        defer { try? file.close() }
        var executableHash = SHA256()
        while let bytes = try file.read(upToCount: 1024 * 1024), !bytes.isEmpty { executableHash.update(data: bytes) }
        return .init(codeHash: hash, signingIdentifier: identifier, bundleIdentifier: bundleIdentifier, version: version, minimumSystemVersion: minimum, executable: executable, executableHash: Data(executableHash.finalize()))
    }

    private static func applicationURL(for executablePath: String) -> URL {
        URL(fileURLWithPath: executablePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private static func isProtectedRuntimeLocation(_ url: URL) throws -> Bool {
        guard url.lastPathComponent == "Prism.app", url.pathComponents.contains("AppTranslocation") else { return false }
        return try url.resourceValues(forKeys: [.volumeIsReadOnlyKey]).volumeIsReadOnly == true
    }

    private static func validateTargetLocation(_ url: URL) throws {
        guard url.isFileURL, url.lastPathComponent == "Prism.app", url.path == url.standardizedFileURL.path,
              url.path == url.resolvingSymlinksInPath().path,
              !url.pathComponents.contains("AppTranslocation"), !url.pathComponents.contains("Volumes") else { throw UpdateInstallationError.unsafePath }
        let parent = url.deletingLastPathComponent()
        let values = try parent.resourceValues(forKeys: [.volumeIsReadOnlyKey, .isDirectoryKey])
        guard values.isDirectory == true, values.volumeIsReadOnly != true,
              FileManager.default.isWritableFile(atPath: parent.path), FileManager.default.isWritableFile(atPath: url.path) else { throw UpdateInstallationError.notWritable }
    }
}
