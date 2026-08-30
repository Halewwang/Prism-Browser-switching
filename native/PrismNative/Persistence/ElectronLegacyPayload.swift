import Foundation
import PrismCore

struct ElectronRoutingRulePayload: Decodable, Equatable {
    var id: String?
    var type: String?
    var value: String?
    var targetBrowserId: String?
    var description: String?
    var active: Bool?
    var appName: String?
}

struct ElectronHistoryPayload: Decodable, Equatable {
    var id: String?
    var timestamp: ElectronFlexibleDate?
    var url: String?
    var sourceApp: String?
    var sourceBundleId: String?
    var routedToBrowserId: String?
    var method: String?
}

struct ElectronCustomBrowserPayload: Decodable, Equatable {
    var id: String?
    var name: String?
    var bundleId: String?
    var path: String?
    var selectorOrder: Int?
}

enum ElectronFlexibleDate: Decodable, Equatable {
    case value(Date)

    var date: Date {
        switch self {
        case let .value(date):
            return date
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let date = try? container.decode(Date.self) {
            self = .value(date)
            return
        }
        if let string = try? container.decode(String.self), let date = Self.parse(string) {
            self = .value(date)
            return
        }
        if let number = try? container.decode(Double.self) {
            self = .value(Self.parse(number))
            return
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported Electron date")
    }

    private static func parse(_ string: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: string) {
            return date
        }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: string) {
            return date
        }
        if let number = Double(string) {
            return parse(number)
        }
        return nil
    }

    private static func parse(_ number: Double) -> Date {
        if number > 1_000_000_000_000 {
            return Date(timeIntervalSince1970: number / 1000)
        }
        return Date(timeIntervalSince1970: number)
    }
}

enum ElectronLegacyMapping {
    static let builtInBrowserIDs: [String: String] = [
        "b1": "company.thebrowser.Browser",
        "b2": "com.google.Chrome",
        "b3": "com.apple.Safari",
        "b4": "org.mozilla.firefox",
        "b5": "com.microsoft.edgemac",
        "b6": "com.brave.Browser",
        "b7": "com.vivaldi.Vivaldi",
        "b8": "com.google.Chrome.canary",
        "b9": "com.comet.browser",
        "b10": "com.operasoftware.Opera",
        "b11": "com.operasoftware.OperaGX",
        "b12": "org.chromium.Chromium",
        "b13": "org.mozilla.firefoxdeveloperedition",
        "b14": "org.mozilla.nightly",
        "b15": "com.microsoft.edgemac.Canary",
        "b16": "com.kagi.kagimacOS",
        "b17": "com.sigmaos.sigmaos.macos",
        "arc": "company.thebrowser.Browser",
        "chrome": "com.google.Chrome",
        "safari": "com.apple.Safari",
        "firefox": "org.mozilla.firefox",
        "edge": "com.microsoft.edgemac",
        "brave": "com.brave.Browser",
        "vivaldi": "com.vivaldi.Vivaldi",
        "comet": "com.comet.browser",
        "opera": "com.operasoftware.Opera"
    ]

    static let knownSourceBundleIDs: [String: String] = [
        "slack": "com.tinyspeck.slackmacgap",
        "feishu": "com.electron.lark",
        "lark": "com.larksuite.lark",
        "dingtalk": "com.alibaba.DingTalkMac",
        "钉钉": "com.alibaba.DingTalkMac",
        "wechat": "com.tencent.xinWeChat",
        "微信": "com.tencent.xinWeChat",
        "teams": "com.microsoft.teams",
        "discord": "com.hnc.Discord",
        "telegram": "ru.keepcoder.Telegram",
        "finder": "com.apple.finder",
        "terminal": "com.apple.Terminal",
        "code": "com.microsoft.VSCode",
        "vs code": "com.microsoft.VSCode",
        "visual studio code": "com.microsoft.VSCode"
    ]

    static func routingRule(
        from payload: ElectronRoutingRulePayload,
        customBrowsers: [ElectronCustomBrowserPayload],
        now: Date
    ) -> RoutingRule? {
        let value = payload.value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !value.isEmpty else { return nil }
        guard let target = targetBrowserID(
            from: payload.targetBrowserId,
            customBrowsers: customBrowsers
        ) else {
            return nil
        }

        let matcher: RuleMatcher
        let label: String?
        switch payload.type?.uppercased() {
        case "SOURCE_APP":
            guard let bundleIdentifier = sourceBundleIdentifier(
                value: value,
                appName: payload.appName
            ) else {
                return nil
            }
            matcher = .sourceBundleIdentifier(bundleIdentifier)
            label = visibleLabel(payload.appName) ?? visibleLabel(payload.description) ?? visibleLabel(value)
        case "URL_PATTERN", nil:
            matcher = .urlContains(value)
            label = visibleLabel(payload.description)
        default:
            return nil
        }

        return RoutingRule(
            id: uuid(from: payload.id),
            isEnabled: payload.active ?? true,
            matcher: matcher,
            targetBrowserID: target,
            priority: 0,
            label: label,
            validationState: .valid,
            createdAt: now,
            updatedAt: now
        )
    }

    static func historyEntry(
        from payload: ElectronHistoryPayload,
        customBrowsers: [ElectronCustomBrowserPayload],
        sanitizer: URLSanitizer = .default
    ) -> HistoryEntry? {
        let createdAt = payload.timestamp?.date ?? Date(timeIntervalSince1970: 0)
        let rawURL = payload.url.flatMap(URL.init(string:))
        let sanitizedURL = rawURL.flatMap { url -> URL? in
            guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
                return nil
            }
            return sanitizer.sanitize(url)
        }
        let target = targetBrowserID(from: payload.routedToBrowserId, customBrowsers: customBrowsers)
        let sourceDisplayName = visibleLabel(payload.sourceApp) ?? "Unknown"
        return HistoryEntry(
            id: uuid(from: payload.id),
            requestID: uuid(from: payload.id.map { "request-\($0)" }),
            sanitizedURL: sanitizedURL,
            sourceBundleIdentifier: usableBundleIdentifier(payload.sourceBundleId),
            sourceDisplayName: sourceDisplayName,
            targetBrowserID: target,
            targetDisplayName: nil,
            method: routingMethod(payload.method),
            result: .success,
            matchingRuleID: nil,
            failureReason: nil,
            attemptCount: 1,
            createdAt: createdAt,
            completedAt: createdAt
        )
    }

    static func customBrowser(
        from payload: ElectronCustomBrowserPayload,
        selectorOrder: Int
    ) -> BrowserDescriptor? {
        let path = payload.path?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !path.isEmpty else { return nil }
        let applicationURL = URL(fileURLWithPath: path)
        let bundleIdentifier = usableBundleIdentifier(payload.bundleId)
            ?? Bundle(url: applicationURL)?.bundleIdentifier
            ?? payload.id
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else { return nil }
        let displayName = visibleLabel(payload.name)
            ?? FileManager.default.displayName(atPath: path)
        return BrowserDescriptor(
            id: BrowserID(rawValue: bundleIdentifier),
            bundleIdentifier: bundleIdentifier,
            displayName: displayName,
            applicationURL: applicationURL,
            securityScopedBookmark: nil,
            origin: .custom,
            availability: .unavailable,
            selectorOrder: payload.selectorOrder ?? selectorOrder
        )
    }

    static func sourceBundleIdentifier(value: String, appName: String?) -> String? {
        if let bundleIdentifier = usableBundleIdentifier(value) {
            return bundleIdentifier
        }
        if let mapped = knownSourceBundleIDs[normalizedName(value)] {
            return mapped
        }
        if let appName, let mapped = knownSourceBundleIDs[normalizedName(appName)] {
            return mapped
        }
        return nil
    }

    static func targetBrowserID(
        from rawValue: String?,
        customBrowsers: [ElectronCustomBrowserPayload]
    ) -> BrowserID? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let mapped = builtInBrowserIDs[trimmed] ?? builtInBrowserIDs[trimmed.lowercased()] {
            return BrowserID(rawValue: mapped)
        }
        if let custom = customBrowsers.first(where: {
            $0.id == trimmed || $0.bundleId == trimmed
        }) {
            if let bundleIdentifier = usableBundleIdentifier(custom.bundleId) {
                return BrowserID(rawValue: bundleIdentifier)
            }
            if let path = custom.path, let bundleIdentifier = Bundle(url: URL(fileURLWithPath: path))?.bundleIdentifier {
                return BrowserID(rawValue: bundleIdentifier)
            }
        }
        if usableBundleIdentifier(trimmed) != nil {
            return BrowserID(rawValue: trimmed)
        }
        return nil
    }

    static func routingMethod(_ rawValue: String?) -> RoutingMethod? {
        switch rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "manual":
            return .manual
        case "rule":
            return .urlRule
        case "default":
            return .preferredBrowser
        case "ai":
            return .manual
        default:
            return nil
        }
    }

    static func visibleLabel(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !SourceRulePresentation.looksLikeBundleIdentifier(trimmed) else {
            return nil
        }
        return trimmed
    }

    static func usableBundleIdentifier(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, SourceRulePresentation.looksLikeBundleIdentifier(trimmed) else {
            return nil
        }
        return trimmed
    }

    static func uuid(from rawValue: String?) -> UUID {
        if let rawValue, let uuid = UUID(uuidString: rawValue) {
            return uuid
        }
        guard let rawValue, !rawValue.isEmpty else {
            return UUID()
        }
        var hasher = Hasher()
        hasher.combine(rawValue)
        let hash = UInt64(bitPattern: Int64(hasher.finalize()))
        return UUID(uuidString: String(format: "00000000-0000-4000-8000-%012llx", hash & 0xFFFFFFFFFFFF))
            ?? UUID()
    }

    private static func normalizedName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
