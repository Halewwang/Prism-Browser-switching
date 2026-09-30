import Foundation
import Testing
@testable import PrismNative

@Suite("Authenticated running update identity")
struct InstallerLaunchValidationTests {
    private let process = InstallerParentIdentity(pid: 321, startTime: "123.456", executablePath: "/private/var/folders/qa/AppTranslocation/A/d/Prism.app/Contents/MacOS/Prism", userID: 501)
    private var expected: InstallerCodeIdentity { .init(codeHash: Data(repeating: 0x41, count: 20), signingIdentifier: "com.prism.app", bundleIdentifier: "com.prism.app", version: "1.14.2", minimumSystemVersion: "15.0", executable: "Prism", executableHash: Data(repeating: 0x61, count: 32)) }

    @Test func identicalVerifiedCodeMayRunFromSystemProtectedLocation() throws {
        try InstallerLaunchValidation.compare(expected: expected, running: expected, before: process, after: process, expectedPID: 321, expectedUserID: 501)
    }
    @Test func matchingNameAndVersionNeverReplaceCodeHashVerification() {
        var forged = expected
        forged.codeHash = Data(repeating: 0x42, count: 20)
        #expect(throws: UpdateInstallationError.self) { try InstallerLaunchValidation.compare(expected: expected, running: forged, before: process, after: process, expectedPID: 321, expectedUserID: 501) }
    }
    @Test func otherUniversalSliceChangesCannotReuseNativeCodeHash() {
        var forged = expected
        forged.executableHash = Data(repeating: 0x62, count: 32)
        #expect(throws: UpdateInstallationError.self) { try InstallerLaunchValidation.compare(expected: expected, running: forged, before: process, after: process, expectedPID: 321, expectedUserID: 501) }
    }
    @Test func unsignedOrEmptyCodeIdentityIsRejected() {
        var unsigned = expected
        unsigned.codeHash = Data()
        #expect(throws: UpdateInstallationError.self) { try InstallerLaunchValidation.compare(expected: expected, running: unsigned, before: process, after: process, expectedPID: 321, expectedUserID: 501) }
    }
    @Test func changedSealedMetadataIsRejected() {
        for field in ["signingIdentifier", "bundleIdentifier", "version", "minimumSystemVersion", "executable"] {
            var forged = expected
            switch field {
            case "signingIdentifier": forged.signingIdentifier = "other"
            case "bundleIdentifier": forged.bundleIdentifier = "other"
            case "version": forged.version = "1.14.1"
            case "minimumSystemVersion": forged.minimumSystemVersion = "14.0"
            default: forged.executable = "Other"
            }
            #expect(throws: UpdateInstallationError.self) { try InstallerLaunchValidation.compare(expected: expected, running: forged, before: process, after: process, expectedPID: 321, expectedUserID: 501) }
        }
    }
    @Test func PIDReuseExecutableChangeOrDifferentUserFailsAttestation() {
        for after in [
            InstallerParentIdentity(pid: 322, startTime: process.startTime, executablePath: process.executablePath, userID: 501),
            InstallerParentIdentity(pid: 321, startTime: "123.457", executablePath: process.executablePath, userID: 501),
            InstallerParentIdentity(pid: 321, startTime: process.startTime, executablePath: "/other/Prism", userID: 501),
            InstallerParentIdentity(pid: 321, startTime: process.startTime, executablePath: process.executablePath, userID: 502)
        ] {
            #expect(throws: UpdateInstallationError.self) { try InstallerLaunchValidation.compare(expected: expected, running: expected, before: process, after: after, expectedPID: 321, expectedUserID: 501) }
        }
    }
}
