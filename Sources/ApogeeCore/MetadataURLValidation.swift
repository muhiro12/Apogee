import Foundation

/// Invalid local metadata; diagnostics never include the supplied URL.
public enum MetadataValidationError: Error, Sendable, Equatable, LocalizedError {
    case invalidURL(field: MetadataField)

    public var errorDescription: String? {
        switch self {
        case let .invalidURL(field):
            "Invalid \(field.rawValue): use one absolute HTTP(S) URL without credentials, whitespace, or malformed escapes. Only marketing_url may be empty."
        }
    }
}

enum MetadataURLValidation {
    static func validate(supportURL: String?, marketingURL: String?) throws {
        if let supportURL {
            try validate(supportURL, field: .supportURL)
        }
        if let marketingURL, !marketingURL.isEmpty {
            try validate(marketingURL, field: .marketingURL)
        }
    }

    private static func validate(_ value: String, field: MetadataField) throws {
        guard !value.isEmpty,
              !value.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) }),
              !value.contains("\\"), validEscapes(value),
              let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              components.user == nil, components.password == nil,
              let url = components.url, let host = url.host, !host.isEmpty,
              !host.contains("%"),
              components.port == nil || (1...65_535).contains(components.port ?? 0) else {
            throw MetadataValidationError.invalidURL(field: field)
        }
    }

    private static func validEscapes(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        for index in bytes.indices where bytes[index] == 37 {
            guard index + 2 < bytes.count else {
                return false
            }
            let pair = bytes[(index + 1)...(index + 2)]
            guard pair.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }),
                  let decoded = UInt8(String(decoding: pair, as: UTF8.self), radix: 16),
                  decoded > 31, decoded != 127 else {
                return false
            }
        }
        return true
    }
}
