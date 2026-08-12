import Foundation

struct SourceSupportManifest: Equatable {
    static let schemaVersion = 1
    static let disabled = SourceSupportManifest(sources: [])

    let sources: [SourceSupportEntry]

    static func decode(_ data: Data) throws -> SourceSupportManifest {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document = try decoder.decode(Document.self, from: data)
        guard document.schemaVersion == schemaVersion else {
            throw ValidationError.unsupportedSchema
        }

        let sourceIDs = document.sources.map(\.bundleIdentifier)
        guard Set(sourceIDs).count == sourceIDs.count else {
            throw ValidationError.duplicateBundleIdentifier
        }

        let entries = try document.sources.map(SourceSupportEntry.init(validating:))
        return SourceSupportManifest(sources: entries)
    }

    static func bundled(in bundle: Bundle = .main) -> SourceSupportManifest {
        guard let resourceURL = bundle.url(forResource: "SupportedSources", withExtension: "json") else {
            return .disabled
        }

        return loadBundled(resourceData: try? Data(contentsOf: resourceURL))
    }

    static func loadBundled(resourceData: Data?) -> SourceSupportManifest {
        guard let resourceData, let manifest = try? decode(resourceData) else {
            return .disabled
        }

        return manifest
    }

    func eligibleBundleIDs(for operatingSystemVersion: OperatingSystemVersion) -> Set<String> {
        Set(sources.compactMap { entry in
            entry.isEligible(on: operatingSystemVersion) ? entry.bundleIdentifier : nil
        })
    }

    enum ValidationError: Error {
        case unsupportedSchema
        case duplicateBundleIdentifier
        case invalidBundleIdentifier
        case insufficientEvidence
        case invalidOperatingSystemBounds
    }

    fileprivate struct Document: Decodable {
        let schemaVersion: Int
        let sources: [DocumentSource]
    }

    fileprivate struct DocumentSource: Decodable {
        let bundleIdentifier: String
        let minimumMacOS: String
        let maximumMacOS: String
        let coldSamples: Int
        let warmSamples: Int
        let confirmedCount: Int
        let falseAttributionCount: Int
        let validatedAt: Date
    }
}

struct SourceSupportEntry: Equatable {
    let bundleIdentifier: String
    let minimumMacOS: SourceSupportVersion
    let maximumMacOS: SourceSupportVersion
    let coldSamples: Int
    let warmSamples: Int
    let confirmedCount: Int
    let falseAttributionCount: Int
    let validatedAt: Date

    fileprivate init(validating source: SourceSupportManifest.DocumentSource) throws {
        let bundleIdentifier = source.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bundleIdentifier.isEmpty else {
            throw SourceSupportManifest.ValidationError.invalidBundleIdentifier
        }

        let minimumMacOS = try SourceSupportVersion(source.minimumMacOS)
        let maximumMacOS = try SourceSupportVersion(source.maximumMacOS)
        guard minimumMacOS <= maximumMacOS else {
            throw SourceSupportManifest.ValidationError.invalidOperatingSystemBounds
        }

        let totalSamples = source.coldSamples.addingReportingOverflow(source.warmSamples)
        guard !totalSamples.overflow,
              source.coldSamples >= 20,
              source.warmSamples >= 20,
              source.confirmedCount >= 40,
              source.confirmedCount == totalSamples.partialValue,
              source.falseAttributionCount == 0
        else {
            throw SourceSupportManifest.ValidationError.insufficientEvidence
        }

        self.bundleIdentifier = bundleIdentifier
        self.minimumMacOS = minimumMacOS
        self.maximumMacOS = maximumMacOS
        self.coldSamples = source.coldSamples
        self.warmSamples = source.warmSamples
        self.confirmedCount = source.confirmedCount
        self.falseAttributionCount = source.falseAttributionCount
        self.validatedAt = source.validatedAt
    }

    fileprivate func isEligible(on operatingSystemVersion: OperatingSystemVersion) -> Bool {
        let version = SourceSupportVersion(operatingSystemVersion)
        return minimumMacOS <= version && version <= maximumMacOS
    }
}

struct SourceSupportVersion: Comparable, Equatable {
    let major: Int
    let minor: Int
    let patch: Int

    init(_ value: String) throws {
        let components = value.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3,
              let major = Int(components[0]),
              let minor = Int(components[1]),
              let patch = Int(components[2]),
              major >= 0,
              minor >= 0,
              patch >= 0
        else {
            throw SourceSupportManifest.ValidationError.invalidOperatingSystemBounds
        }

        self.major = major
        self.minor = minor
        self.patch = patch
    }

    init(_ value: OperatingSystemVersion) {
        major = value.majorVersion
        minor = value.minorVersion
        patch = value.patchVersion
    }

    static func < (lhs: SourceSupportVersion, rhs: SourceSupportVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}
