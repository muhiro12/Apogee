import Foundation

public struct LocalizedMetadata: Sendable, Hashable {
    public var locale: String
    public var releaseNotes: String?
    public var description: String?
    public var keywords: String?
    public var promotionalText: String?

    public init(
        locale: String,
        releaseNotes: String? = nil,
        description: String? = nil,
        keywords: String? = nil,
        promotionalText: String? = nil
    ) {
        self.locale = locale
        self.releaseNotes = releaseNotes
        self.description = description
        self.keywords = keywords
        self.promotionalText = promotionalText
    }

    public func filtered(fields: Set<MetadataField>) -> Self {
        .init(
            locale: locale,
            releaseNotes: fields.contains(.releaseNotes) ? releaseNotes : nil,
            description: fields.contains(.description) ? description : nil,
            keywords: fields.contains(.keywords) ? keywords : nil,
            promotionalText: fields.contains(.promotionalText) ? promotionalText : nil
        )
    }
}

public enum MetadataField: String, Sendable, Hashable, CaseIterable {
    case releaseNotes = "release_notes"
    case description
    case keywords
    case promotionalText = "promotional_text"

    var fileName: String {
        "\(rawValue).txt"
    }

    var displayName: String {
        switch self {
        case .releaseNotes:
            "What's New"
        case .description:
            "Description"
        case .keywords:
            "Keywords"
        case .promotionalText:
            "Promotional Text"
        }
    }
}

public struct MetadataLoader: Sendable {
    public init() {}

    public func load(from path: String) throws -> [LocalizedMetadata] {
        let rootURL = URL(fileURLWithPath: path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: rootURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ApogeeError.invalidPath(path)
        }

        let rootResourceValues = try rootURL.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard rootResourceValues.isSymbolicLink != true else {
            throw ApogeeError.invalidPath(path)
        }

        let childURLs = try FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )
        var localeURLs: [URL] = []

        for childURL in childURLs {
            let resourceValues = try childURL.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
            )
            guard resourceValues.isSymbolicLink != true else {
                throw ApogeeError.invalidPath(childURL.path)
            }

            if resourceValues.isDirectory == true {
                localeURLs.append(childURL)
            }
        }

        let orderedLocaleURLs = localeURLs.sorted { lhs, rhs in
            lhs.lastPathComponent < rhs.lastPathComponent
        }
        return try orderedLocaleURLs.map { localeURL in
            try loadLocale(localeURL)
        }
    }

    private func loadLocale(_ localeURL: URL) throws -> LocalizedMetadata {
        let locale = localeURL.lastPathComponent
        return .init(
            locale: locale,
            releaseNotes: try optionalTextFile(localeURL.appendingPathComponent(MetadataField.releaseNotes.fileName)),
            description: try optionalTextFile(localeURL.appendingPathComponent(MetadataField.description.fileName)),
            keywords: try optionalTextFile(localeURL.appendingPathComponent(MetadataField.keywords.fileName)),
            promotionalText: try optionalTextFile(localeURL.appendingPathComponent(MetadataField.promotionalText.fileName))
        )
    }

    private func optionalTextFile(_ url: URL) throws -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        let resourceValues = try url.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        )
        guard resourceValues.isRegularFile == true, resourceValues.isSymbolicLink != true else {
            throw ApogeeError.invalidPath(url.path)
        }

        let contents = try String(contentsOf: url, encoding: .utf8)
        return contents.trimmingCharacters(in: .newlines)
    }
}
