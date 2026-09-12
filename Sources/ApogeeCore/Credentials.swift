import Foundation

/// Team API key identifiers and a private key source used for App Store Connect requests.
///
/// Descriptions redact all values. Construction does not validate the signing key;
/// the generated adapter reads and parses it when it first needs an authorization token.
public struct AppStoreConnectCredentials: Sendable, Hashable, CustomStringConvertible, CustomDebugStringConvertible {
    public var keyID: String
    public var issuerID: String
    var privateKeySource: AppStoreConnectPrivateKeySource

    /// The configured file path, or nil when the key was supplied as PEM.
    public var privateKeyPath: String? {
        guard case let .path(path) = privateKeySource else {
            return nil
        }

        return path
    }

    public var description: String {
        "AppStoreConnectCredentials(<redacted>)"
    }

    public var debugDescription: String {
        description
    }

    public init(keyID: String, issuerID: String, privateKeyPath: String) {
        self.keyID = keyID
        self.issuerID = issuerID
        privateKeySource = .path(privateKeyPath)
    }

    public init(keyID: String, issuerID: String, privateKeyPEM: String) {
        self.keyID = keyID
        self.issuerID = issuerID
        privateKeySource = .pem(privateKeyPEM)
    }

    /// Loads required identifiers and a private key source from the selected environment.
    ///
    /// A nonempty base64 variable takes precedence over the file-path variable. Base64
    /// is decoded as UTF-8 PEM; key validity and file readability are checked on use.
    public static func load(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        credentialEnvironment: AppStoreConnectCredentialEnvironment = .init()
    ) throws -> Self {
        guard let keyID = environment[credentialEnvironment.keyIDEnvironment], !keyID.isEmpty else {
            throw ApogeeError.missingEnvironmentVariable(credentialEnvironment.keyIDEnvironment)
        }

        guard let issuerID = environment[credentialEnvironment.issuerIDEnvironment], !issuerID.isEmpty else {
            throw ApogeeError.missingEnvironmentVariable(credentialEnvironment.issuerIDEnvironment)
        }

        if let privateKeyBase64 = environment[credentialEnvironment.privateKeyBase64Environment], !privateKeyBase64.isEmpty {
            return try .init(
                keyID: keyID,
                issuerID: issuerID,
                privateKeyPEM: privateKeyPEM(
                    base64: privateKeyBase64,
                    environmentVariable: credentialEnvironment.privateKeyBase64Environment
                )
            )
        }

        guard let privateKeyPath = environment[credentialEnvironment.privateKeyPathEnvironment], !privateKeyPath.isEmpty else {
            throw ApogeeError.missingEnvironmentVariable(
                "\(credentialEnvironment.privateKeyBase64Environment) or \(credentialEnvironment.privateKeyPathEnvironment)"
            )
        }

        guard FileManager.default.fileExists(atPath: privateKeyPath) else {
            throw ApogeeError.missingCredentialFile(privateKeyPath)
        }

        return .init(keyID: keyID, issuerID: issuerID, privateKeyPath: privateKeyPath)
    }

    private static func privateKeyPEM(base64: String, environmentVariable: String) throws -> String {
        guard let data = Data(base64Encoded: base64, options: [.ignoreUnknownCharacters]),
              let pem = String(data: data, encoding: .utf8),
              !pem.isEmpty
        else {
            throw ApogeeError.invalidPrivateKey("\(environmentVariable) did not contain base64-encoded UTF-8 PEM.")
        }

        return pem
    }
}

enum AppStoreConnectPrivateKeySource: Sendable, Hashable {
    case path(String)
    case pem(String)

    func pemString() throws -> String {
        switch self {
        case let .path(path):
            return try String(contentsOfFile: path, encoding: .utf8)
        case let .pem(pem):
            return pem
        }
    }
}
