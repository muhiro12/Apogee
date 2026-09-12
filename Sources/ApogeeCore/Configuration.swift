import Foundation

/// Portable repository defaults loaded from an optional `apogee.json` file.
///
/// Relative content paths resolve against the configuration file when loaded with
/// ``load(from:)``. Direct construction or JSON decoding does not establish that base.
public struct ApogeeConfiguration: Codable, Sendable, Hashable {
    public static let defaultPath = "apogee.json"
    public static let defaultMetadataPath = "AppStore/Metadata"
    public static let defaultScreenshotsPath = "AppStore/Screenshots"
    public static let defaultWebhooksPath = "AppStore/webhooks.json"

    public var appID: String?
    public var bundleID: String?
    public var defaultPlatform: Platform?
    public var metadataPath: String?
    public var screenshotsPath: String?
    public var webhooksPath: String?
    public var credentials: AppStoreConnectCredentialEnvironment
    private var configurationDirectory: URL?

    public var resolvedMetadataPath: String {
        resolvePath(metadataPath.nonEmpty ?? Self.defaultMetadataPath)
    }

    public var resolvedScreenshotsPath: String {
        resolvePath(screenshotsPath.nonEmpty ?? Self.defaultScreenshotsPath)
    }

    public var resolvedWebhooksPath: String {
        resolvePath(webhooksPath.nonEmpty ?? Self.defaultWebhooksPath)
    }

    private enum CodingKeys: String, CodingKey {
        case appID
        case bundleID
        case defaultPlatform
        case metadataPath
        case screenshotsPath
        case webhooksPath
        case credentials
    }

    public init(
        appID: String? = nil,
        bundleID: String? = nil,
        defaultPlatform: Platform? = nil,
        metadataPath: String? = nil,
        screenshotsPath: String? = nil,
        webhooksPath: String? = nil,
        credentials: AppStoreConnectCredentialEnvironment = .init()
    ) {
        self.appID = appID
        self.bundleID = bundleID
        self.defaultPlatform = defaultPlatform
        self.metadataPath = metadataPath
        self.screenshotsPath = screenshotsPath
        self.webhooksPath = webhooksPath
        self.credentials = credentials
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            appID: try container.decodeIfPresent(String.self, forKey: .appID),
            bundleID: try container.decodeIfPresent(String.self, forKey: .bundleID),
            defaultPlatform: try container.decodeIfPresent(Platform.self, forKey: .defaultPlatform),
            metadataPath: try container.decodeIfPresent(String.self, forKey: .metadataPath),
            screenshotsPath: try container.decodeIfPresent(String.self, forKey: .screenshotsPath),
            webhooksPath: try container.decodeIfPresent(String.self, forKey: .webhooksPath),
            credentials: try container.decodeIfPresent(
                AppStoreConnectCredentialEnvironment.self,
                forKey: .credentials
            ) ?? .init()
        )
    }

    /// Loads the selected configuration, or returns defaults when the implicit default file is absent.
    ///
    /// An explicitly supplied missing path throws rather than silently using defaults.
    public static func loadIfPresent(
        path: String? = nil,
        fileManager: FileManager = .default
    ) throws -> Self {
        let resolvedPath = path ?? Self.defaultPath
        if path == nil && !fileManager.fileExists(atPath: resolvedPath) {
            return .init()
        }

        return try load(from: resolvedPath)
    }

    /// Decodes JSON and anchors relative content paths to the containing directory.
    ///
    /// Throws for missing files, unreadable data, or malformed configuration.
    public static func load(from path: String) throws -> Self {
        guard FileManager.default.fileExists(atPath: path) else {
            throw ApogeeError.invalidPath(path)
        }

        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        var configuration = try JSONDecoder().decode(Self.self, from: data)
        configuration.configurationDirectory = URL(fileURLWithPath: path).deletingLastPathComponent()
        return configuration
    }

    private func resolvePath(_ path: String) -> String {
        guard let configurationDirectory else {
            return path
        }
        return URL(fileURLWithPath: path, relativeTo: configurationDirectory).standardizedFileURL.path
    }
}

/// Names of environment variables containing team API credentials, never their values.
public struct AppStoreConnectCredentialEnvironment: Codable, Sendable, Hashable {
    public var keyIDEnvironment: String
    public var issuerIDEnvironment: String
    public var privateKeyPathEnvironment: String
    public var privateKeyBase64Environment: String

    private enum CodingKeys: String, CodingKey {
        case keyIDEnvironment
        case issuerIDEnvironment
        case privateKeyPathEnvironment
        case privateKeyBase64Environment
    }

    public init(
        keyIDEnvironment: String = "ASC_KEY_ID",
        issuerIDEnvironment: String = "ASC_ISSUER_ID",
        privateKeyPathEnvironment: String = "ASC_PRIVATE_KEY_PATH",
        privateKeyBase64Environment: String = "ASC_PRIVATE_KEY_BASE64"
    ) {
        self.keyIDEnvironment = keyIDEnvironment
        self.issuerIDEnvironment = issuerIDEnvironment
        self.privateKeyPathEnvironment = privateKeyPathEnvironment
        self.privateKeyBase64Environment = privateKeyBase64Environment
    }

    public init(from decoder: Decoder) throws {
        let defaultEnvironment = Self()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            keyIDEnvironment: try container.decodeIfPresent(
                String.self,
                forKey: .keyIDEnvironment
            ) ?? defaultEnvironment.keyIDEnvironment,
            issuerIDEnvironment: try container.decodeIfPresent(
                String.self,
                forKey: .issuerIDEnvironment
            ) ?? defaultEnvironment.issuerIDEnvironment,
            privateKeyPathEnvironment: try container.decodeIfPresent(
                String.self,
                forKey: .privateKeyPathEnvironment
            ) ?? defaultEnvironment.privateKeyPathEnvironment,
            privateKeyBase64Environment: try container.decodeIfPresent(
                String.self,
                forKey: .privateKeyBase64Environment
            ) ?? defaultEnvironment.privateKeyBase64Environment
        )
    }
}

private extension Optional where Wrapped == String {
    var nonEmpty: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        return value
    }
}
