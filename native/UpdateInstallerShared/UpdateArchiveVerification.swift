import CryptoKit
import Foundation

struct InstallerSignedManifest: Decodable, Sendable {
    let version: String
    let fileName: String
    let sha256: String
    let size: Int64
    let bundleIdentifier: String
    let minimumSystemVersion: String
}

/// Independently checked by the separate installer process. A previously
/// extracted ad hoc application is not an authenticated source archive.
struct UpdateArchiveVerification {
    static func verify(workspace: URL, archiveURL: URL, expectedVersion: String, publicKey: Data = Data(base64Encoded: PrismUpdateTrust.publicKeyBase64) ?? Data()) throws -> InstallerSignedManifest {
        try InstallerSystem.validateControlDirectory(workspace)
        let manifestURL = workspace.appendingPathComponent("update-manifest.json")
        let signatureURL = workspace.appendingPathComponent("update-manifest.sig")
        try regularFile(manifestURL, maximumBytes: 64 * 1024)
        try regularFile(signatureURL, maximumBytes: 1024)
        let data = try Data(contentsOf: manifestURL)
        let signatureData = try Data(contentsOf: signatureURL)
        guard let signatureText = String(data: signatureData, encoding: .utf8),
              let signature = Data(base64Encoded: signatureText.trimmingCharacters(in: .whitespacesAndNewlines)),
              signature.count == 64,
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey),
              key.isValidSignature(signature, for: data),
              let fields = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(fields.keys) == Set(["version", "fileName", "sha256", "size", "bundleIdentifier", "minimumSystemVersion"]),
              let manifest = try? JSONDecoder().decode(InstallerSignedManifest.self, from: data),
              manifest.version == expectedVersion,
              manifest.bundleIdentifier == PrismUpdateTrust.bundleIdentifier,
              ["Prism-\(expectedVersion)-universal-test.dmg", "Prism-\(expectedVersion).dmg"].contains(manifest.fileName),
              archiveURL.path == workspace.appendingPathComponent(manifest.fileName).path,
              manifest.size > 0, manifest.size <= PrismUpdateTrust.maximumInstallerBytes,
              manifest.sha256.count == 64, manifest.sha256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw UpdateInstallationError.invalidApplication }
        _ = try InstallerSystem.versionParts(expectedVersion)
        let systemParts = manifest.minimumSystemVersion.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(systemParts.count), systemParts.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }) else { throw UpdateInstallationError.invalidApplication }
        let values = systemParts.compactMap { Int($0) }
        guard values.count == systemParts.count else { throw UpdateInstallationError.invalidApplication }
        let required = OperatingSystemVersion(majorVersion: values[0], minorVersion: values.count > 1 ? values[1] : 0, patchVersion: values.count > 2 ? values[2] : 0)
        guard ProcessInfo.processInfo.isOperatingSystemAtLeast(required) else { throw UpdateInstallationError.invalidApplication }
        try regularFile(archiveURL, maximumBytes: PrismUpdateTrust.maximumInstallerBytes)
        let attributes = try archiveURL.resourceValues(forKeys: [.fileSizeKey])
        guard Int64(attributes.fileSize ?? -1) == manifest.size else { throw UpdateInstallationError.invalidApplication }
        let input = try FileHandle(forReadingFrom: archiveURL)
        defer { try? input.close() }
        var hash = SHA256()
        while let bytes = try input.read(upToCount: 1024 * 1024), !bytes.isEmpty { hash.update(data: bytes) }
        guard hash.finalize().map({ String(format: "%02x", $0) }).joined() == manifest.sha256 else { throw UpdateInstallationError.invalidApplication }
        return manifest
    }

    private static func regularFile(_ url: URL, maximumBytes: Int64) throws {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              url.path == url.resolvingSymlinksInPath().path,
              Int64(values.fileSize ?? -1) >= 0, Int64(values.fileSize ?? -1) <= maximumBytes else { throw UpdateInstallationError.invalidApplication }
    }
}
