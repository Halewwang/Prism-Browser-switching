import Foundation

public struct URLSanitizer: Sendable {
    public static let `default` = URLSanitizer()

    public init() {}

    public func sanitize(_ url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        if let query = components.percentEncodedQuery {
            var safeSegments: [Substring] = []

            for segment in query.split(separator: "&", omittingEmptySubsequences: false) where !segment.isEmpty {
                let rawName = segment.prefix { $0 != "=" }
                guard let decodedName = String(rawName).removingPercentEncoding else {
                    return nil
                }

                if !isSensitiveQueryName(decodedName) {
                    safeSegments.append(segment)
                }
            }

            components.percentEncodedQuery = safeSegments.isEmpty
                ? nil
                : safeSegments.map(String.init).joined(separator: "&")
        }

        components.fragment = nil
        return components.url
    }

    private func isSensitiveQueryName(_ name: String) -> Bool {
        let name = name.lowercased()
        return Self.sensitiveNames.contains(name) || name.hasPrefix("utm_")
    }

    private static let sensitiveNames: Set<String> = [
        "token",
        "access_token",
        "auth",
        "authorization",
        "code",
        "state",
        "session",
        "session_id",
        "signature",
        "gclid",
        "fbclid"
    ]
}
