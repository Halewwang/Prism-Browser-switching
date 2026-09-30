import CryptoKit
import Foundation

struct PreparedUpdate: Sendable {
    let applicationURL: URL
    let workspaceURL: URL
    let installerFileURL: URL
    let version: String
}

@MainActor protocol UpdatePackagePreparing {
    func prepare(_ installer: GitHubPublishedInstaller, progress: @escaping @Sendable (Double?) -> Void) async throws -> PreparedUpdate
    func cleanup(_ prepared: PreparedUpdate)
}

enum UpdatePreparationError: LocalizedError, Equatable {
    case unsignedRelease, invalidSignature, invalidManifest, integrityMismatch
    case untrustedDownload, downloadFailed, packageTooLarge, unsupportedSystem, invalidApplication
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsignedRelease: "该版本未提供可信更新签名，请从发布页手动安装。"
        case .invalidSignature: "更新签名验证失败，请稍后重试或从发布页下载。"
        case .invalidManifest: "更新信息与选中的版本不一致。"
        case .integrityMismatch: "安装包校验失败，请重新下载。"
        case .untrustedDownload: "更新下载地址不受信任。"
        case .downloadFailed: "更新下载失败，请检查网络后重试。"
        case .packageTooLarge: "更新安装包超出允许的大小。"
        case .unsupportedSystem: "此更新需要更新版本的 macOS。"
        case .invalidApplication: "安装包中的应用验证失败。"
        case .commandFailed: "无法准备安装包，请重试或手动安装。"
        }
    }
}

struct UpdateManifest: Decodable, Sendable {
    let version: String
    let fileName: String
    let sha256: String
    let size: Int64
    let bundleIdentifier: String
    let minimumSystemVersion: String

    static func verify(data: Data, signatureData: Data, publicKey: Data, installer: GitHubPublishedInstaller) throws -> Self {
        guard data.count <= 64 * 1024, signatureData.count <= 1024,
              let signatureString = String(data: signatureData, encoding: .utf8),
              let signature = Data(base64Encoded: signatureString.trimmingCharacters(in: .whitespacesAndNewlines)),
              signature.count == 64, let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey),
              key.isValidSignature(signature, for: data)
        else { throw UpdatePreparationError.invalidSignature }
        guard let value = try? JSONDecoder().decode(Self.self, from: data),
              value.version == installer.version, value.fileName == installer.fileName,
              value.bundleIdentifier == PrismUpdateTrust.bundleIdentifier,
              value.size > 0, value.size <= PrismUpdateTrust.maximumInstallerBytes,
              installer.fileByteCount == nil || installer.fileByteCount == value.size,
              value.sha256.count == 64, value.sha256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              !value.fileName.contains("/"), !value.fileName.contains("\\"),
              GitHubPublishedInstaller.isNewer(value.version, than: "0.0.0") == true
        else { throw UpdatePreparationError.invalidManifest }
        guard let minimum = systemVersion(value.minimumSystemVersion) else { throw UpdatePreparationError.invalidManifest }
        let current = ProcessInfo.processInfo.operatingSystemVersion
        guard ![current.majorVersion, current.minorVersion, current.patchVersion].lexicographicallyPrecedes(minimum)
        else { throw UpdatePreparationError.unsupportedSystem }
        return value
    }

    static func systemVersion(_ string: String) -> [Int]? {
        let parts = string.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }) else { return nil }
        let values = parts.compactMap { Int($0) }
        guard values.count == parts.count else { return nil }
        return values + Array(repeating: 0, count: 3 - values.count)
    }

    static func validateFile(_ url: URL, against manifest: Self) throws {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, Int64(values.fileSize ?? -1) == manifest.size else { throw UpdatePreparationError.integrityMismatch }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            try Task.checkCancellation()
            hash.update(data: chunk)
        }
        guard hash.finalize().map({ String(format: "%02x", $0) }).joined() == manifest.sha256 else { throw UpdatePreparationError.integrityMismatch }
    }
}

/// Only GitHub's documented release asset hosts are accepted, including every redirect hop.
final class UpdateAssetTransport: NSObject, URLSessionTaskDelegate, Sendable {
    static func permits(_ url: URL) -> Bool {
        url.scheme == "https" && ["github.com", "objects.githubusercontent.com", "release-assets.githubusercontent.com"].contains(url.host ?? "") && url.user == nil && url.password == nil && url.port == nil
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(request.url.map(Self.permits) == true ? request : nil)
    }

    static func download(_ url: URL, to file: URL, maximumBytes: Int64, expectedBytes: Int64? = nil, progress: @escaping @Sendable (Double?) -> Void = { _ in }) async throws {
        guard permits(url) else { throw UpdatePreparationError.untrustedDownload }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 15 * 60
        let session = URLSession(configuration: configuration, delegate: UpdateAssetTransport(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("Prism", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let finalURL = http.url, permits(finalURL) else { throw UpdatePreparationError.downloadFailed }
        guard http.expectedContentLength <= maximumBytes else { throw UpdatePreparationError.packageTooLarge }
        if let expectedBytes, http.expectedContentLength >= 0, http.expectedContentLength != expectedBytes { throw UpdatePreparationError.integrityMismatch }
        guard FileManager.default.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw UpdatePreparationError.downloadFailed }
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        var count: Int64 = 0
        var chunk = Data()
        chunk.reserveCapacity(64 * 1024)
        progress(expectedBytes == nil ? nil : 0)
        for try await byte in bytes {
            try Task.checkCancellation()
            count += 1
            guard count <= maximumBytes, expectedBytes == nil || count <= expectedBytes! else { throw UpdatePreparationError.packageTooLarge }
            chunk.append(byte)
            if chunk.count >= 64 * 1024 {
                try handle.write(contentsOf: chunk)
                chunk.removeAll(keepingCapacity: true)
                progress(expectedBytes.map { Double(count) / Double($0) })
            }
        }
        try handle.write(contentsOf: chunk)
        if let expectedBytes, count != expectedBytes { throw UpdatePreparationError.integrityMismatch }
        progress(expectedBytes.map { Double(count) / Double($0) })
    }
}

@MainActor final class GitHubUpdatePackagePreparer: UpdatePackagePreparing {
    private let publicKey: Data
    init(publicKey: Data? = nil) { self.publicKey = publicKey ?? Data(base64Encoded: PrismUpdateTrust.publicKeyBase64) ?? Data() }

    func prepare(_ installer: GitHubPublishedInstaller, progress: @escaping @Sendable (Double?) -> Void) async throws -> PreparedUpdate {
        guard let manifestURL = installer.manifestURL, let signatureURL = installer.signatureURL else { throw UpdatePreparationError.unsignedRelease }
        let base = installer.downloadURL.deletingLastPathComponent()
        let expectedDMG = "/Halewwang/Prism-Browser-switching/releases/download/v\(installer.version)/\(installer.fileName)"
        guard installer.downloadURL.host == "github.com", UpdateAssetTransport.permits(installer.downloadURL), installer.downloadURL.query == nil, installer.downloadURL.fragment == nil,
              installer.downloadURL.path == expectedDMG,
              manifestURL == base.appendingPathComponent("update-manifest.json"), signatureURL == base.appendingPathComponent("update-manifest.sig") else { throw UpdatePreparationError.untrustedDownload }
        let workspace = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("PrismUpdate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let mount = workspace.appendingPathComponent("mount", isDirectory: true)
        var didAttemptMount = false
        do {
            let manifestFile = workspace.appendingPathComponent("update-manifest.json")
            let signatureFile = workspace.appendingPathComponent("update-manifest.sig")
            try await UpdateAssetTransport.download(manifestURL, to: manifestFile, maximumBytes: 64 * 1024)
            try await UpdateAssetTransport.download(signatureURL, to: signatureFile, maximumBytes: 1024)
            let manifest = try UpdateManifest.verify(data: Data(contentsOf: manifestFile), signatureData: Data(contentsOf: signatureFile), publicKey: publicKey, installer: installer)
            let dmg = workspace.appendingPathComponent(installer.fileName)
            try await UpdateAssetTransport.download(installer.downloadURL, to: dmg, maximumBytes: manifest.size, expectedBytes: manifest.size, progress: progress)
            try Task.checkCancellation()
            try await Task.detached { try UpdateManifest.validateFile(dmg, against: manifest) }.value
            try await UpdateCommand.run("/usr/bin/xattr", ["-w", "com.apple.quarantine", Self.quarantineValue, dmg.path])
            try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: false)
            didAttemptMount = true
            try await UpdateCommand.run("/usr/bin/hdiutil", ["attach", "-readonly", "-nobrowse", "-noautoopen", "-mountpoint", mount.path, dmg.path])
            let source = mount.appendingPathComponent("Prism.app", isDirectory: true)
            try UpdateApplicationValidation.validateContainedLinks(source)
            let application = workspace.appendingPathComponent("Prism.app", isDirectory: true)
            try await UpdateCommand.run("/usr/bin/ditto", ["--rsrc", "--extattr", "--acl", source.path, application.path])
            try await UpdateCommand.run("/usr/bin/hdiutil", ["detach", mount.path])
            didAttemptMount = false
            try await UpdateApplicationValidation.validate(application, version: manifest.version, minimumSystemVersion: manifest.minimumSystemVersion)
            try await UpdateCommand.run("/usr/bin/xattr", ["-w", "com.apple.quarantine", Self.quarantineValue, application.path])
            try Task.checkCancellation()
            return PreparedUpdate(applicationURL: application, workspaceURL: workspace, installerFileURL: dmg, version: manifest.version)
        } catch {
            if didAttemptMount {
                do { try await UpdateCommand.run("/usr/bin/hdiutil", ["detach", mount.path], ignoreCancellation: true) }
                catch { _ = try? await UpdateCommand.run("/usr/bin/hdiutil", ["detach", "-force", mount.path], ignoreCancellation: true) }
            }
            try? FileManager.default.removeItem(at: workspace)
            if Task.isCancelled { throw CancellationError() }
            throw error
        }
    }

    func cleanup(_ prepared: PreparedUpdate) {
        // A caller cannot use cleanup to remove an arbitrary application or directory.
        let workspace = prepared.workspaceURL.standardizedFileURL
        guard workspace.deletingLastPathComponent() == FileManager.default.temporaryDirectory.resolvingSymlinksInPath(),
              workspace.lastPathComponent.hasPrefix("PrismUpdate-"),
              prepared.applicationURL.standardizedFileURL.path == workspace.appendingPathComponent("Prism.app").path,
              workspace.resolvingSymlinksInPath() == workspace else { return }
        try? FileManager.default.removeItem(at: workspace)
    }
    private static var quarantineValue: String { "0081;\(String(Int(Date().timeIntervalSince1970), radix: 16));Prism;\(UUID().uuidString)" }
}

// Internal pure filesystem checks are shared with tests; all process operations are absolute argv.
enum UpdateApplicationValidation {
    static func validateContainedLinks(_ application: URL) throws {
        let fm = FileManager.default
        let root = application.standardizedFileURL
        let values = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true, let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey], options: []) else { throw UpdatePreparationError.invalidApplication }
        let canonicalRoot = root.resolvingSymlinksInPath().path + "/"
        for case let item as URL in enumerator {
            if try item.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
                guard item.resolvingSymlinksInPath().path.hasPrefix(canonicalRoot) else { throw UpdatePreparationError.invalidApplication }
            }
        }
    }
    static func validate(_ application: URL, version: String, minimumSystemVersion: String) async throws {
        try validateContainedLinks(application)
        let infoURL = application.appendingPathComponent("Contents/Info.plist")
        guard let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: infoURL), format: nil) as? [String: Any],
              info["CFBundleIdentifier"] as? String == PrismUpdateTrust.bundleIdentifier,
              info["CFBundleShortVersionString"] as? String == version,
              info["LSMinimumSystemVersion"] as? String == minimumSystemVersion,
              let name = info["CFBundleExecutable"] as? String, !name.isEmpty, !name.contains("/"), !name.contains("\\"), name != ".", name != ".." else { throw UpdatePreparationError.invalidApplication }
        let executable = application.appendingPathComponent("Contents/MacOS/\(name)")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw UpdatePreparationError.invalidApplication }
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x86_64"
        #endif
        let architectures = try await UpdateCommand.run("/usr/bin/lipo", ["-archs", executable.path])
        guard architectures.split(whereSeparator: \.isWhitespace).contains(Substring(architecture)) else { throw UpdatePreparationError.invalidApplication }
        _ = try await UpdateCommand.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", application.path])
    }
}

private final class UpdateCommand: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    private func cancel() { lock.lock(); cancelled = true; let current = process; lock.unlock(); if current?.isRunning == true { current?.terminate() } }
    @discardableResult static func run(_ executable: String, _ arguments: [String], ignoreCancellation: Bool = false) async throws -> String {
        let command = UpdateCommand()
        return try await withTaskCancellationHandler {
            if !ignoreCancellation { try Task.checkCancellation() }
            return try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    let process = Process()
                    let output = Pipe()
                    process.executableURL = URL(fileURLWithPath: executable)
                    process.arguments = arguments
                    process.standardOutput = output
                    process.standardError = FileHandle.nullDevice
                    command.lock.lock()
                    if command.cancelled && !ignoreCancellation { command.lock.unlock(); continuation.resume(throwing: CancellationError()); return }
                    command.process = process
                    do { try process.run(); command.lock.unlock() } catch { command.lock.unlock(); continuation.resume(throwing: error); return }
                    // Drain before waiting so verbose process output cannot fill a pipe and deadlock.
                    let data = output.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    if process.terminationStatus == 0 { continuation.resume(returning: String(decoding: data, as: UTF8.self)) }
                    else { continuation.resume(throwing: UpdatePreparationError.commandFailed(executable)) }
                }
            }
        } onCancel: { if !ignoreCancellation { command.cancel() } }
    }
}
