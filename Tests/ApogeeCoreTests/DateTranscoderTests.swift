@testable import ApogeeCore
import Foundation
import OpenAPIRuntime
import Testing

@Test
func appStoreConnectDateEncodingPreservesTheRuntimeDefault() throws {
    let date = Date(timeIntervalSince1970: 1_800_000_000.123)
    let encoded = try AppStoreConnectDateTranscoder().encode(date)
    let defaultEncoded = try ISO8601DateTranscoder.iso8601.encode(date)
    #expect(encoded == defaultEncoded)
    #expect(encoded == "2027-01-15T08:00:00Z")
}
