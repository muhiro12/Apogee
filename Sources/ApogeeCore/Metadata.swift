import Foundation

/// Locale-specific metadata; nil leaves a field unchanged and an empty string clears it.
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

    /// Returns a copy retaining only the selected fields; locale is preserved.
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

/// A supported metadata field whose raw value is its text file basename.
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

/// Loads local UTF-8 metadata without contacting App Store Connect.
public struct MetadataLoader: Sendable {
    public init() {}

    /// Loads locale directories in sorted order and trims leading/trailing newlines.
    ///
    /// Missing selected files become nil; empty files remain explicit empty values.
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
            metadata.releaseNotes != nil || metadata.description != nil
                || metadata.keywords != nil || metadata.promotionalText != nil
        }
        guard !metadata.isEmpty else {
            throw ApogeeError.emptyMetadata
        }
        return metadata
    }

    private func loadLocale(_ localeURL: URL, fields: Set<MetadataField>) throws -> LocalizedMetadata {
        let locale = localeURL.lastPathComponent
        return .init(
            locale: locale,
            releaseNotes: try fields.contains(.releaseNotes) ? optionalTextFile(localeURL.appendingPathComponent(MetadataField.releaseNotes.fileName)) : nil,
            description: try fields.contains(.description) ? optionalTextFile(localeURL.appendingPathComponent(MetadataField.description.fileName)) : nil,
            keywords: try fields.contains(.keywords) ? optionalTextFile(localeURL.appendingPathComponent(MetadataField.keywords.fileName)) : nil,
            promotionalText: try fields.contains(.promotionalText) ? optionalTextFile(localeURL.appendingPathComponent(MetadataField.promotionalText.fileName)) : nil
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
