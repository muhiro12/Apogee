import Foundation

public struct ApogeeConfiguration: Codable, Sendable, Hashable {
    public static let defaultPath = "AppStore/apogee.json"

    public var appID: String?
    public var bundleID: String?
    public var defaultPlatform: Platform?
    public var metadataPath: String?
    public var screenshotsPath: String?
    public var webhooksPath: String?
    public var credentials: AppStoreConnectCredentialEnvironment

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

    public static func load(from path: String) throws -> Self {
        guard FileManager.default.fileExists(atPath: path) else {
            throw ApogeeError.invalidPath(path)
        }

        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try JSONDecoder().decode(Self.self, from: data)
    }
}

public struct AppStoreConnectCredentialEnvironment: Codable, Sendable, Hashable {
    public var keyIDEnvironment: String
    public var issuerIDEnvironment: String
    public var privateKeyPathEnvironment: String
    public var privateKeyBase64Environment: String

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
}
