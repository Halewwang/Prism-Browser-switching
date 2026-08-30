import Foundation

enum ChromiumLocalStorageReader {
    static func stringValues(
        in directory: URL,
        keys: Set<String>,
        fileManager: FileManager = .default
    ) -> [String: String] {
        guard !keys.isEmpty,
              let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        else {
            return [:]
        }

        var found: [String: String] = [:]
        for fileURL in files {
            let name = fileURL.lastPathComponent
            if name == "LOCK" || name == "LOG" || name == "CURRENT" || name.hasPrefix("MANIFEST-") {
                continue
            }
            guard let data = try? Data(contentsOf: fileURL) else { continue }
            for key in keys where found[key] == nil {
                if let value = extractJSON(afterKey: key, in: data) {
                    found[key] = value
                }
            }
            if found.count == keys.count {
                break
            }
        }
        return found
    }

    static func extractJSON(afterKey key: String, in data: Data) -> String? {
        if let utf8Range = data.range(of: Data(key.utf8)),
           let json = firstJSONLiteral(in: data[utf8Range.upperBound...], encoding: .utf8) {
            return json
        }
        if let utf16Key = key.data(using: .utf16LittleEndian),
           let utf16Range = data.range(of: utf16Key),
           let json = firstJSONLiteral(in: data[utf16Range.upperBound...], encoding: .utf16LittleEndian) {
            return json
        }
        return nil
    }

    private static func firstJSONLiteral(in data: Data, encoding: String.Encoding) -> String? {
        let aligned: Data
        if encoding == .utf16LittleEndian, data.startIndex % 2 != 0 {
            aligned = data.dropFirst()
        } else {
            aligned = Data(data)
        }
        guard let string = String(data: aligned, encoding: encoding) ?? String(data: aligned, encoding: .utf8) else {
            return nil
        }
        return firstJSONLiteral(in: string)
    }

    static func firstJSONLiteral(in string: String) -> String? {
        guard let start = string.firstIndex(where: { $0 == "[" || $0 == "{" }) else {
            return nil
        }
        let open = string[start]
        let close: Character = open == "[" ? "]" : "}"
        var depth = 0
        var inString = false
        var escape = false
        var index = start
        while index < string.endIndex {
            let character = string[index]
            if inString {
                if escape {
                    escape = false
                } else if character == "\\" {
                    escape = true
                } else if character == "\"" {
                    inString = false
                }
            } else if character == "\"" {
                inString = true
            } else if character == open {
                depth += 1
            } else if character == close {
                depth -= 1
                if depth == 0 {
                    return String(string[start...index])
                }
            }
            index = string.index(after: index)
        }
        return nil
    }
}
