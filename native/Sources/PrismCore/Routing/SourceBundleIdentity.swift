import Foundation

public enum SourceBundleIdentity {
    public static func canonical(_ raw: String?) -> String? {
        guard var value = trimmed(raw) else { return nil }
        if let applicationID = strippingTeamPrefix(value) {
            value = applicationID
        }
        if let host = strippingHelperSuffix(value) {
            value = host
        }
        return trimmed(value)
    }

    public static func matches(_ lhs: String, _ rhs: String) -> Bool {
        guard let left = canonical(lhs), let right = canonical(rhs) else { return false }
        return left.caseInsensitiveCompare(right) == .orderedSame
    }

    public static func isHelper(_ raw: String?) -> Bool {
        guard let value = trimmed(raw) else { return false }
        let applicationID = strippingTeamPrefix(value) ?? value
        return strippingHelperSuffix(applicationID) != nil
    }

    private static func strippingTeamPrefix(_ value: String) -> String? {
        guard value.count > 11, value[value.index(value.startIndex, offsetBy: 10)] == "." else {
            return nil
        }
        let prefix = value.prefix(10)
        guard prefix.allSatisfy(isTeamIDCharacter) else { return nil }
        let remainder = String(value.dropFirst(11))
        guard remainder.contains(".") else { return nil }
        return remainder
    }

    private static func strippingHelperSuffix(_ value: String) -> String? {
        let parts = value.split(separator: ".").map(String.init)
        guard let helperIndex = parts.firstIndex(where: { $0.compare("helper", options: .caseInsensitive) == .orderedSame }),
              helperIndex > 0,
              parts[helperIndex...].allSatisfy({ helperTailComponents.contains($0.lowercased()) })
        else {
            return nil
        }
        let host = parts.prefix(helperIndex).joined(separator: ".")
        return host.isEmpty ? nil : host
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func isTeamIDCharacter(_ character: Character) -> Bool {
        guard let ascii = character.asciiValue else { return false }
        let isDigit = ascii >= 48 && ascii <= 57
        let isUppercase = ascii >= 65 && ascii <= 90
        return isDigit || isUppercase
    }

    private static let helperTailComponents: Set<String> = ["helper", "renderer", "gpu", "plugin", "alerts"]
}
