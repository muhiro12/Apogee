import Foundation

/// Locale-specific metadata; nil leaves a field unchanged. Empty strings request clearing,
/// except the required support URL, whose empty local value is rejected.
public struct LocalizedMetadata: Sendable, Hashable {
    public var locale: String
    public var releaseNotes: String?
    public var description: String?
    public var keywords: String?
    public var promotionalText: String?
    public var supportURL: String?
    public var marketingURL: String?

    public init(
        locale: String,
        releaseNotes: String? = nil,
        description: String? = nil,
        keywords: String? = nil,
        promotionalText: String? = nil,
        supportURL: String? = nil,
        marketingURL: String? = nil
    ) {
        self.locale = locale
        self.releaseNotes = releaseNotes
        self.description = description
        self.keywords = keywords
        self.promotionalText = promotionalText
        self.supportURL = supportURL
        self.marketingURL = marketingURL
    }

    /// Returns a copy retaining only the selected fields; locale is preserved.
    public func filtered(fields: Set<MetadataField>) -> Self {
        .init(
            locale: locale,
            releaseNotes: fields.contains(.releaseNotes) ? releaseNotes : nil,
            description: fields.contains(.description) ? description : nil,
            keywords: fields.contains(.keywords) ? keywords : nil,
            promotionalText: fields.contains(.promotionalText) ? promotionalText : nil,
            supportURL: fields.contains(.supportURL) ? supportURL : nil,
            marketingURL: fields.contains(.marketingURL) ? marketingURL : nil
        )
    }
}

/// A supported metadata field whose raw value is its text file basename.
public enum MetadataField: String, Sendable, Hashable, CaseIterable {
    case releaseNotes = "release_notes"
    case description
    case keywords
    case promotionalText = "promotional_text"
    case supportURL = "support_url"
    case marketingURL = "marketing_url"

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
        case .supportURL:
            "Support URL"
        case .marketingURL:
            "Marketing URL"
        }
    }
}

/// Loads local UTF-8 metadata without contacting App Store Connect.
public struct MetadataLoader: Sendable {
    public init() {}

    /// Loads locale directories in sorted order and trims leading/trailing newlines.
    ///
    /// Missing selected files become nil; empty files remain explicit empty values,
    /// except that an empty support URL is rejected. Selected URLs are validated locally.
    /// Hidden entries are ignored, symbolic links at inspected entries are rejected,
    /// and no matching fields throws ``ApogeeError/emptyMetadata``. This does not validate
    /// App Store field length limits or whether remote localizations already exist.
    public func load(from path: String, fields: Set<MetadataField> = Set(MetadataField.allCases)) throws -> [LocalizedMetadata] {
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
        let metadata = try orderedLocaleURLs.map { localeURL in
            try loadLocale(localeURL, fields: fields)
        }.filter { metadata in
            let values = [metadata.releaseNotes, metadata.description, metadata.keywords,
                          metadata.promotionalText, metadata.supportURL, metadata.marketingURL]
            return values.contains { $0 != nil }
        }
        guard !metadata.isEmpty else {
            throw ApogeeError.emptyMetadata
        }
        return metadata
    }

    private func loadLocale(_ localeURL: URL, fields: Set<MetadataField>) throws -> LocalizedMetadata {
        let locale = localeURL.lastPathComponent
        let metadata = LocalizedMetadata(
            locale: locale,
            releaseNotes: try fields.contains(.releaseNotes) ? optionalTextFile(localeURL.appendingPathComponent(MetadataField.releaseNotes.fileName)) : nil,
            description: try fields.contains(.description) ? optionalTextFile(localeURL.appendingPathComponent(MetadataField.description.fileName)) : nil,
            keywords: try fields.contains(.keywords) ? optionalTextFile(localeURL.appendingPathComponent(MetadataField.keywords.fileName)) : nil,
            promotionalText: try fields.contains(.promotionalText) ? optionalTextFile(localeURL.appendingPathComponent(MetadataField.promotionalText.fileName)) : nil,
            supportURL: try fields.contains(.supportURL) ? optionalTextFile(localeURL.appendingPathComponent(MetadataField.supportURL.fileName)) : nil,
            marketingURL: try fields.contains(.marketingURL) ? optionalTextFile(localeURL.appendingPathComponent(MetadataField.marketingURL.fileName)) : nil
        )
        try MetadataURLValidation.validate(supportURL: metadata.supportURL, marketingURL: metadata.marketingURL)
        return metadata
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
