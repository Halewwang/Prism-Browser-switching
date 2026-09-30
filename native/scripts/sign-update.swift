import CryptoKit
import Foundation

enum SigningError: Error { case usage, unsafeKey, invalidArchive, invalidSignature }

func loadKey(_ path: String) throws -> Curve25519.Signing.PrivateKey {
    let url = URL(fileURLWithPath: path)
    let attributes = try FileManager.default.attributesOfItem(atPath: path)
    guard attributes[.type] as? FileAttributeType == .typeRegular,
          (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600,
          (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid()
    else { throw SigningError.unsafeKey }
    return try Curve25519.Signing.PrivateKey(rawRepresentation: Data(contentsOf: url))
}

func run() throws {
    let args = Array(CommandLine.arguments.dropFirst())
    guard let command = args.first else { throw SigningError.usage }
    switch command {
    case "generate-key":
        guard args.count == 2 else { throw SigningError.usage }
        let file = URL(fileURLWithPath: args[1])
        guard !FileManager.default.fileExists(atPath: file.path) else { throw SigningError.unsafeKey }
        let directory = file.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        guard (try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber)?.intValue == 0o700 else { throw SigningError.unsafeKey }
        let key = Curve25519.Signing.PrivateKey()
        let descriptor = open(file.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw SigningError.unsafeKey }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        try handle.write(contentsOf: key.rawRepresentation)
        try handle.close()
        print(key.publicKey.rawRepresentation.base64EncodedString())
    case "public-key":
        guard args.count == 2 else { throw SigningError.usage }
        print(try loadKey(args[1]).publicKey.rawRepresentation.base64EncodedString())
    case "sign":
        guard args.count == 6 else { throw SigningError.usage }
        let key = try loadKey(args[1])
        let archive = URL(fileURLWithPath: args[2])
        let version = args[3]
        guard version.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression) != nil,
              ["Prism-\(version).dmg", "Prism-\(version)-universal-test.dmg"].contains(archive.lastPathComponent),
              args[5].range(of: #"^\d+\.\d+(\.\d+)?$"#, options: .regularExpression) != nil
        else { throw SigningError.invalidArchive }
        let bytes = try Data(contentsOf: archive, options: .mappedIfSafe)
        guard !bytes.isEmpty, bytes.count <= 536_870_912 else { throw SigningError.invalidArchive }
        let manifest: [String: Any] = [
            "version": version, "fileName": archive.lastPathComponent,
            "sha256": SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(),
            "size": bytes.count, "bundleIdentifier": "com.prism.app", "minimumSystemVersion": args[5],
        ]
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
        let signature = try key.signature(for: data).base64EncodedString() + "\n"
        let output = URL(fileURLWithPath: args[4], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try data.write(to: output.appendingPathComponent("update-manifest.json"), options: .atomic)
        try Data(signature.utf8).write(to: output.appendingPathComponent("update-manifest.sig"), options: .atomic)
        print("Signed update manifest for \(archive.lastPathComponent)")
    case "verify":
        guard args.count == 4,
              let publicBytes = Data(base64Encoded: args[1]),
              let signatureBytes = Data(base64Encoded: try String(contentsOfFile: args[3], encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines))
        else { throw SigningError.usage }
        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicBytes)
        guard publicKey.isValidSignature(signatureBytes, for: try Data(contentsOf: URL(fileURLWithPath: args[2]))) else { throw SigningError.invalidSignature }
    default:
        throw SigningError.usage
    }
}

do { try run() }
catch {
    // No private key bytes or caller-supplied paths in diagnostics.
    fputs("Update signing failed. Check arguments, key permissions, archive identity, and signature.\n", stderr)
    exit(1)
}
