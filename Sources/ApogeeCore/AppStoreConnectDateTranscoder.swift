import Foundation
import OpenAPIRuntime

struct AppStoreConnectDateTranscoder: DateTranscoder {
    private let wholeSeconds: ISO8601DateTranscoder = .iso8601
    private let fractionalSeconds: ISO8601DateTranscoder = .iso8601WithFractionalSeconds

    func encode(_ date: Date) throws -> String {
        try wholeSeconds.encode(date)
    }

    func decode(_ value: String) throws -> Date {
        // App Store Connect can mix both precisions within the same response.
        if let date = try? fractionalSeconds.decode(value) {
            return date
        }
        if let date = try? wholeSeconds.decode(value) {
            return date
        }
        throw AppStoreConnectDateDecodingError()
    }
}

struct AppStoreConnectDateDecodingError: Error {}
