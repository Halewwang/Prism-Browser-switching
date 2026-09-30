import Foundation

enum PrismUpdateTrust {
    // Independent Ed25519 update key. Apple Developer ID is a separate identity.
    static let publicKeyBase64 = "6YfCe5PVj3eetCnUExyxe8pzBWQDy0YYT4wMPDf9m6w="
    #if DEBUG && PRISM_UPDATE_QA
    // Only a separately compiled QA helper can use this identity. Release
    // builds have no command-line or environment override for the bundle ID.
    static let bundleIdentifier = "com.prism.iterationqa.update"
    #else
    static let bundleIdentifier = "com.prism.app"
    #endif
    static let maximumInstallerBytes: Int64 = 512 * 1024 * 1024
}
