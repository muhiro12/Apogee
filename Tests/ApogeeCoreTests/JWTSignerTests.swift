import Crypto
import Foundation
import Testing
@testable import ApogeeCore

@Test
func jwtSignerCreatesES256AppStoreConnectToken() throws {
    let privateKey = P256.Signing.PrivateKey()
    let keyURL = temporaryDirectory().appendingPathComponent("AuthKey_TEST.p8")
    try privateKey.pemRepresentation.write(to: keyURL, atomically: true, encoding: .utf8)
    let credentials = AppStoreConnectCredentials(
        keyID: "KEY123",
        issuerID: "ISSUER456",
        privateKeyPath: keyURL.path
    )

    let token = try JSONWebTokenSigner(credentials: credentials).signedToken(now: Date(timeIntervalSince1970: 1_700_000_000))
    let parts = token.value.split(separator: ".").map(String.init)

    #expect(parts.count == 3)

    let header = try decodedJSONObject(parts[0])
    let payload = try decodedJSONObject(parts[1])

    #expect(header["alg"] as? String == "ES256")
    #expect(header["kid"] as? String == "KEY123")
    #expect(header["typ"] as? String == "JWT")
    #expect(payload["iss"] as? String == "ISSUER456")
    #expect(payload["aud"] as? String == "appstoreconnect-v1")
    #expect(payload["iat"] as? Int == 1_700_000_000)
    #expect(payload["exp"] as? Int == 1_700_001_140)

    let signingInput = "\(parts[0]).\(parts[1])"
    let signature = try P256.Signing.ECDSASignature(rawRepresentation: base64URLDecoded(parts[2]))
    #expect(privateKey.publicKey.isValidSignature(signature, for: Data(signingInput.utf8)))
}

@Test
func credentialsLoadPrivateKeyBase64FromConfiguredEnvironment() throws {
    let privateKey = P256.Signing.PrivateKey()
    let privateKeyBase64 = Data(privateKey.pemRepresentation.utf8).base64EncodedString()
    let credentialEnvironment = AppStoreConnectCredentialEnvironment(
        keyIDEnvironment: "TEST_ASC_KEY_ID",
        issuerIDEnvironment: "TEST_ASC_ISSUER_ID",
        privateKeyPathEnvironment: "TEST_ASC_PRIVATE_KEY_PATH",
        privateKeyBase64Environment: "TEST_ASC_PRIVATE_KEY_BASE64"
    )
    let credentials = try AppStoreConnectCredentials.load(
        environment: [
            "TEST_ASC_KEY_ID": "KEY123",
            "TEST_ASC_ISSUER_ID": "ISSUER456",
            "TEST_ASC_PRIVATE_KEY_BASE64": privateKeyBase64,
        ],
        credentialEnvironment: credentialEnvironment
    )

    let token = try JSONWebTokenSigner(credentials: credentials).signedToken(now: Date(timeIntervalSince1970: 1_700_000_000))
    let parts = token.value.split(separator: ".").map(String.init)
    let signingInput = "\(parts[0]).\(parts[1])"
    let signature = try P256.Signing.ECDSASignature(rawRepresentation: base64URLDecoded(parts[2]))

    #expect(credentials.privateKeyPath == nil)
    #expect(privateKey.publicKey.isValidSignature(signature, for: Data(signingInput.utf8)))
}

@Test
func secretBearingValuesUseRedactedDescriptions() {
    let secret = "apogee-secret-value-sentinel"
    let credentials = AppStoreConnectCredentials(
        keyID: "KEY123",
        issuerID: "ISSUER456",
        privateKeyPEM: secret
    )
    let signedToken = SignedToken(value: secret, expiresAt: Date(timeIntervalSince1970: 1_700_000_000))
    let secretEnvironment = SecretEnvironment(values: ["WEBHOOK_SECRET": secret])
    let signer = JSONWebTokenSigner(credentials: credentials)
    let renderedValues = [
        String(describing: credentials),
        String(reflecting: credentials),
        String(describing: signedToken),
        String(reflecting: signedToken),
        String(describing: secretEnvironment),
        String(reflecting: secretEnvironment),
        String(reflecting: signer),
    ]

    #expect(renderedValues.allSatisfy { value in
        !value.contains(secret)
    })
    #expect(renderedValues.allSatisfy { value in
        value.contains("<redacted>")
    })
}

private func decodedJSONObject(_ text: String) throws -> [String: Any] {
    let data = try base64URLDecoded(text)
    return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private func base64URLDecoded(_ text: String) throws -> Data {
    var base64 = text
        .replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")
    let remainder = base64.count % 4
    if remainder > 0 {
        base64.append(String(repeating: "=", count: 4 - remainder))
    }

    return try #require(Data(base64Encoded: base64))
}

private func temporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("apogee-tests")
        .appendingPathComponent(UUID().uuidString)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
