import Foundation

public struct AppStoreConnectCredentials: Sendable, Hashable {
    public var keyID: String
    public var issuerID: String
    public var privateKeyPath: String

    public init(keyID: String, issuerID: String, privateKeyPath: String) {
        self.keyID = keyID
        self.issuerID = issuerID
        self.privateKeyPath = privateKeyPath
    }

    public static func load(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> Self {
        guard let keyID = environment["ASC_KEY_ID"], !keyID.isEmpty else {
            throw ApogeeError.missingEnvironmentVariable("ASC_KEY_ID")
        }

        guard let issuerID = environment["ASC_ISSUER_ID"], !issuerID.isEmpty else {
            throw ApogeeError.missingEnvironmentVariable("ASC_ISSUER_ID")
        }

        guard let privateKeyPath = environment["ASC_PRIVATE_KEY_PATH"], !privateKeyPath.isEmpty else {
            throw ApogeeError.missingEnvironmentVariable("ASC_PRIVATE_KEY_PATH")
        }

        guard FileManager.default.fileExists(atPath: privateKeyPath) else {
            throw ApogeeError.missingCredentialFile(privateKeyPath)
        }

        return .init(keyID: keyID, issuerID: issuerID, privateKeyPath: privateKeyPath)
    }
}
