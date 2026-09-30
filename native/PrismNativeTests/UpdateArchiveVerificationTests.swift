import CryptoKit
import Foundation
import Testing
@testable import PrismNative

@Suite("Installer independently verifies signed archive")
struct UpdateArchiveVerificationTests {
    @Test func acceptsOnlySignedMatchingManifestAndExactArchive() throws {
        let fixture = try SignedArchiveFixture()
        defer { fixture.remove() }
        let manifest = try UpdateArchiveVerification.verify(workspace: fixture.root, archiveURL: fixture.archive, expectedVersion: "1.14.2", publicKey: fixture.key.publicKey.rawRepresentation)
        #expect(manifest.version == "1.14.2")
        #expect(manifest.minimumSystemVersion == "15.0")
    }
    @Test func changedManifestCannotReuseOriginalSignature() throws {
        let fixture = try SignedArchiveFixture()
        defer { fixture.remove() }
        let data = try Data(contentsOf: fixture.root.appendingPathComponent("update-manifest.json"))
        try Data(String(decoding: data, as: UTF8.self).replacingOccurrences(of: "1.14.2", with: "1.14.3").utf8).write(to: fixture.root.appendingPathComponent("update-manifest.json"))
        #expect(throws: UpdateInstallationError.self) {
            try UpdateArchiveVerification.verify(workspace: fixture.root, archiveURL: fixture.archive, expectedVersion: "1.14.3", publicKey: fixture.key.publicKey.rawRepresentation)
        }
    }
    @Test func modifiedArchiveIsRejectedEvenWithUnchangedByteCount() throws {
        let fixture = try SignedArchiveFixture()
        defer { fixture.remove() }
        try Data("forged dmg".utf8).write(to: fixture.archive)
        #expect(throws: UpdateInstallationError.self) {
            try UpdateArchiveVerification.verify(workspace: fixture.root, archiveURL: fixture.archive, expectedVersion: "1.14.2", publicKey: fixture.key.publicKey.rawRepresentation)
        }
    }
    @Test func changedByteCountIsRejected() throws {
        let fixture = try SignedArchiveFixture()
        defer { fixture.remove() }
        try Data("longer modified dmg".utf8).write(to: fixture.archive)
        #expect(throws: UpdateInstallationError.self) {
            try UpdateArchiveVerification.verify(workspace: fixture.root, archiveURL: fixture.archive, expectedVersion: "1.14.2", publicKey: fixture.key.publicKey.rawRepresentation)
        }
    }
    @Test func signedWrongVersionBundleAndFilenameAreRejected() throws {
        for change in ["version", "bundleIdentifier", "fileName", "minimumSystemVersion"] {
            let fixture = try SignedArchiveFixture(change: change)
            defer { fixture.remove() }
            #expect(throws: UpdateInstallationError.self) {
                try UpdateArchiveVerification.verify(workspace: fixture.root, archiveURL: fixture.archive, expectedVersion: "1.14.2", publicKey: fixture.key.publicKey.rawRepresentation)
            }
        }
    }
    @Test func symlinkArchiveAndManifestAreRejected() throws {
        for name in ["update-manifest.json", "Prism-1.14.2-universal-test.dmg"] {
            let fixture = try SignedArchiveFixture()
            defer { fixture.remove() }
            let source = fixture.root.appendingPathComponent(name)
            let original = fixture.root.appendingPathComponent("original-" + name)
            try FileManager.default.moveItem(at: source, to: original)
            try FileManager.default.createSymbolicLink(at: source, withDestinationURL: original)
            #expect(throws: UpdateInstallationError.self) {
                try UpdateArchiveVerification.verify(workspace: fixture.root, archiveURL: fixture.archive, expectedVersion: "1.14.2", publicKey: fixture.key.publicKey.rawRepresentation)
            }
        }
    }
}

private struct SignedArchiveFixture {
    let root: URL
    let archive: URL
    let key: Curve25519.Signing.PrivateKey
    init(change: String? = nil) throws {
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        archive = root.appendingPathComponent("Prism-1.14.2-universal-test.dmg")
        key = Curve25519.Signing.PrivateKey()
        let bytes = Data("signed dmg".utf8)
        try bytes.write(to: archive)
        var manifest: [String: Any] = ["version": "1.14.2", "fileName": archive.lastPathComponent, "sha256": SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(), "size": bytes.count, "bundleIdentifier": "com.prism.app", "minimumSystemVersion": "15.0"]
        if let change { manifest[change] = change == "minimumSystemVersion" ? "999.0" : "unexpected" }
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
        try data.write(to: root.appendingPathComponent("update-manifest.json"))
        try Data(key.signature(for: data).base64EncodedString().utf8).write(to: root.appendingPathComponent("update-manifest.sig"))
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
}
