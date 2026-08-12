import Foundation

public struct URLSanitizer: Sendable {
    public static let `default` = URLSanitizer()

    public init() {}

    public func sanitize(_ url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        if components.percentEncodedQuery != nil {
            guard let queryItems = components.queryItems else {
                return nil
            }

            let safeQueryItems = queryItems.filter { !isSensitiveQueryItem($0) }
            components.queryItems = safeQueryItems.isEmpty ? nil : safeQueryItems
        }

        components.fragment = nil
        return components.url
    }

    private func isSensitiveQueryItem(_ item: URLQueryItem) -> Bool {
        let name = item.name.lowercased()
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
