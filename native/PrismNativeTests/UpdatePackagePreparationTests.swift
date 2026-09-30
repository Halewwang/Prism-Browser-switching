import CryptoKit
import Foundation
import Testing
@testable import PrismNative

@Suite("Signed update packages")
struct UpdatePackagePreparationTests {
    private func installer() -> GitHubPublishedInstaller {
        let base = "https://github.com/Halewwang/Prism-Browser-switching/releases/download/v1.15.0/"
        return GitHubPublishedInstaller(version: "1.15.0", notes: "", downloadURL: URL(string: base + "Prism-1.15.0-universal-test.dmg")!, fileName: "Prism-1.15.0-universal-test.dmg", manifestURL: URL(string: base + "update-manifest.json"), signatureURL: URL(string: base + "update-manifest.sig"), fileByteCount: 3)
    }
    private func manifest(version: String = "1.15.0", size: Int = 3, minimum: String = "15.0") -> Data {
        Data("""
        {"version":"\(version)","fileName":"Prism-1.15.0-universal-test.dmg","sha256":"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad","size":\(size),"bundleIdentifier":"com.prism.app","minimumSystemVersion":"\(minimum)"}
        """.utf8)
    }
    @Test func verifiesOriginalBytesAndRejectsOtherKeysOrModifiedBytes() throws {
        let key = Curve25519.Signing.PrivateKey()
        let bytes = manifest()
        let signature = try key.signature(for: bytes).base64EncodedString()
        let verified = try UpdateManifest.verify(data: bytes, signatureData: Data((signature + "\n").utf8), publicKey: key.publicKey.rawRepresentation, installer: installer())
        #expect(verified.size == 3)
        for (message, publicKey) in [(bytes + Data(" ".utf8), key.publicKey.rawRepresentation), (bytes, Curve25519.Signing.PrivateKey().publicKey.rawRepresentation)] {
            #expect(throws: UpdatePreparationError.invalidSignature) {
                try UpdateManifest.verify(data: message, signatureData: Data(signature.utf8), publicKey: publicKey, installer: installer())
            }
        }
    }
    @Test func rejectsSignedButMismatchedMetadataAndUnsupportedSystem() throws {
        let key = Curve25519.Signing.PrivateKey()
        for bytes in [manifest(version: "1.14.0"), manifest(size: 4), manifest(size: -1), manifest(minimum: "99.0")] {
            #expect(throws: UpdatePreparationError.self) {
                try UpdateManifest.verify(data: bytes, signatureData: Data(try key.signature(for: bytes).base64EncodedString().utf8), publicKey: key.publicKey.rawRepresentation, installer: installer())
            }
        }
    }
    @Test func acceptsOnlyHTTPSGitHubAssetRedirectDomains() {
        for url in ["http://github.com/file", "https://evil.example/file", "https://github.com.evil.example/file", "https://user@github.com/file", "https://github.com:443/file", "https://objects.githubusercontent.com.evil.example/file"] {
            #expect(!UpdateAssetTransport.permits(URL(string: url)!))
        }
        for host in ["github.com", "objects.githubusercontent.com", "release-assets.githubusercontent.com"] {
            #expect(UpdateAssetTransport.permits(URL(string: "https://\(host)/asset")!))
        }
    }
    @Test func rejectsCorruptFilesAndAcceptsMatchingHashAndSize() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("installer.dmg")
        let key = Curve25519.Signing.PrivateKey()
        let bytes = manifest()
        let manifest = try UpdateManifest.verify(data: bytes, signatureData: Data(try key.signature(for: bytes).base64EncodedString().utf8), publicKey: key.publicKey.rawRepresentation, installer: installer())
        try Data("abc".utf8).write(to: file)
        try UpdateManifest.validateFile(file, against: manifest)
        for corrupt in ["abd", "abcd"] {
            try Data(corrupt.utf8).write(to: file)
            #expect(throws: UpdatePreparationError.integrityMismatch) {
                try UpdateManifest.validateFile(file, against: manifest)
            }
        }
    }
    @Test @MainActor func refusesUnsignedReleasesBeforeDownloading() async {
        let unsigned = GitHubPublishedInstaller(version: "1.15.0", notes: "", downloadURL: URL(string: "https://github.com/Halewwang/Prism-Browser-switching/releases/download/v1.15.0/Prism-1.15.0.dmg")!, fileName: "Prism-1.15.0.dmg")
        await #expect(throws: UpdatePreparationError.unsignedRelease) {
            try await GitHubUpdatePackagePreparer().prepare(unsigned) { _ in }
        }
    }
    @Test @MainActor func cleanupRemovesOnlyItsCanonicalTemporaryWorkspace() throws {
        let base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        let owned = base.appendingPathComponent("PrismUpdate-\(UUID().uuidString)")
        let foreign = base.appendingPathComponent("OtherApp-\(UUID().uuidString)")
        for url in [owned, foreign] { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false) }
        defer { try? FileManager.default.removeItem(at: owned); try? FileManager.default.removeItem(at: foreign) }
        let preparer = GitHubUpdatePackagePreparer()
        for directory in [owned, foreign] {
            preparer.cleanup(PreparedUpdate(applicationURL: directory.appendingPathComponent("Prism.app", isDirectory: true), workspaceURL: directory, installerFileURL: directory.appendingPathComponent("package.dmg"), version: "1.15.0"))
        }
        #expect(!FileManager.default.fileExists(atPath: owned.path))
        #expect(FileManager.default.fileExists(atPath: foreign.path))
    }
    @Test func rejectsEscapingSymlinksInsideAnApplication() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("escape"), withDestinationURL: URL(fileURLWithPath: "/etc/passwd"))
        #expect(throws: UpdatePreparationError.invalidApplication) { try UpdateApplicationValidation.validateContainedLinks(root) }
    }
}
