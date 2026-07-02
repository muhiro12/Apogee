import Crypto
import Foundation

public struct JSONWebTokenSigner: Sendable {
    public var credentials: AppStoreConnectCredentials
    public var lifetime: TimeInterval

    public init(credentials: AppStoreConnectCredentials, lifetime: TimeInterval = 19 * 60) {
        self.credentials = credentials
        self.lifetime = lifetime
    }

    public func signedToken(now: Date = .init()) throws -> SignedToken {
        let issuedAt = Int(now.timeIntervalSince1970)
        let expiration = Int(now.addingTimeInterval(lifetime).timeIntervalSince1970)
        let header: [String: String] = [
            "alg": "ES256",
            "kid": credentials.keyID,
            "typ": "JWT",
        ]
        let payload: [String: Any] = [
            "iss": credentials.issuerID,
            "iat": issuedAt,
            "exp": expiration,
            "aud": "appstoreconnect-v1",
        ]

        let headerData = try JSONSerialization.data(withJSONObject: header, options: [.sortedKeys])
        let payloadData = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let signingInput = "\(headerData.base64URLEncodedString()).\(payloadData.base64URLEncodedString())"
        let privateKeyPEM = try credentials.privateKeySource.pemString()

        let privateKey: P256.Signing.PrivateKey
        do {
            privateKey = try .init(pemRepresentation: privateKeyPEM)
        } catch {
            throw ApogeeError.invalidPrivateKey(error.localizedDescription)
        }

        let signature = try privateKey.signature(for: Data(signingInput.utf8))
        let token = "\(signingInput).\(Data(signature.rawRepresentation).base64URLEncodedString())"
        return .init(value: token, expiresAt: Date(timeIntervalSince1970: TimeInterval(expiration)))
    }
}

public struct SignedToken: Sendable, Hashable {
    public var value: String
    public var expiresAt: Date

    public init(value: String, expiresAt: Date) {
        self.value = value
        self.expiresAt = expiresAt
    }
}

public actor AppStoreConnectTokenProvider {
    private var cachedToken: SignedToken?
    private let signer: JSONWebTokenSigner

    public init(signer: JSONWebTokenSigner) {
        self.signer = signer
    }

    public func token(now: Date = .init()) throws -> String {
        if let cachedToken, cachedToken.expiresAt.timeIntervalSince(now) > 60 {
            return cachedToken.value
        }

        let signedToken = try signer.signedToken(now: now)
        cachedToken = signedToken
        return signedToken.value
    }
}

extension Data {
    fileprivate func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
