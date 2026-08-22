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

        if components.scheme?.lowercased() == "http" || components.scheme?.lowercased() == "https" {
            components.user = nil
            components.password = nil
        }
        components.fragment = nil
        return components.url
    }

    private func isSensitiveQueryName(_ name: String) -> Bool {
        let name = name.lowercased()
        return Self.sensitiveNames.contains(name)
            || name.hasPrefix("utm_")
            || name.split(whereSeparator: { $0 == "_" || $0 == "-" })
                .contains { Self.sensitiveNameSegments.contains(String($0)) }
    }

    private static let sensitiveNames: Set<String> = [
        "token",
        "access_token",
        "refresh_token",
        "id_token",
        "oauth_token",
        "oauth_verifier",
        "auth",
        "authorization",
        "bearer",
        "jwt",
        "code",
        "state",
        "session",
        "session_id",
        "signature",
        "password",
        "pass",
        "passwd",
        "pwd",
        "secret",
        "client_secret",
        "client-secret",
        "api_key",
        "api-key",
        "apikey",
        "key",
        "private_key",
        "secret_key",
        "access_key",
        "credential",
        "credentials",
        "assertion",
        "saml_response",
        "samlresponse",
        "saml_request",
        "samlrequest",
        "gclid",
        "fbclid"
    ]

    private static let sensitiveNameSegments: Set<String> = [
        "token",
        "auth",
        "authorization",
        "bearer",
        "jwt",
        "code",
        "state",
        "session",
        "signature",
        "password",
        "pass",
        "passwd",
        "pwd",
        "secret",
        "key",
        "credential",
        "credentials",
        "assertion",
        "saml"
    ]
}
