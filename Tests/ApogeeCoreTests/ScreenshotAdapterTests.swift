import ApogeeCore
import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing

@Test(arguments: ["sets", "images"])
func screenshotAdapterReadsEveryPageAndPreservesOrder(kind: String) async throws {
    let transport = StubTransport { request, _, index in
        #expect(request.method == .get)
        let path = request.path ?? ""
        let decodedPath = path.removingPercentEncoding ?? path
        let item: [String: Any]
        if kind == "sets" {
            #expect(path.contains("/appStoreVersionLocalizations/locale/appScreenshotSets"))
            #expect(decodedPath.contains("include=appStoreVersionLocalization"))
            item = screenshotSetFixture(id: "set-\(index)")
        } else {
            #expect(path.contains("/appScreenshotSets/set/appScreenshots"))
            #expect(decodedPath.contains("include=appScreenshotSet"))
            item = screenshotResourceFixture(id: "image-\(index)")
        }
        var links = ["self": "unused"]
        if index == 0 {
            links["next"] = "https://api.appstoreconnect.apple.com" + path + "&cursor=second"
        }
        return try jsonResponse(["data": [item], "links": links, "meta": ["paging": ["limit": 200, "total": 2]]])
    }
    let api = testAPI(transport: transport)
    if kind == "sets" {
        #expect(try await api.screenshotSets(localizationID: "locale").map(\.id) == ["set-0", "set-1"])
    } else {
        #expect(try await api.screenshots(setID: "set").map(\.id) == ["image-0", "image-1"])
    }
    #expect(await transport.requests.count == 2)
}

@Test(arguments: ["parent", "state", "total", "cursor"])
func screenshotAdapterRefusesIncompleteInventory(scenario: String) async throws {
    let transport = StubTransport { _, _, _ in
        var resource = screenshotResourceFixture(id: "image")
        if scenario == "parent" {
            resource.removeValue(forKey: "relationships")
        }
        if scenario == "state" {
            resource["attributes"] = ["fileName": "image.png", "fileSize": 10]
        }
        var paging: [String: Any] = ["limit": 200, "total": scenario == "total" ? 2 : 1]
        if scenario == "cursor" {
            paging["nextCursor"] = "omitted-link"
        }
        return try jsonResponse(["data": [resource], "links": ["self": "unused"], "meta": ["paging": paging]])
    }
    await #expect(throws: ApogeeError.self) {
        _ = try await testAPI(transport: transport).screenshots(setID: "set")
    }
}

@Test
func screenshotAdapterEncodesReservationCommitDeleteAndOrdering() async throws {
    let transport = StubTransport { request, body, index in
        let object = try #require(body.flatMap { try JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] })
        let data = object["data"]
        switch index {
        case 0:
            #expect(request.path == "/v1/appScreenshotSets")
            #expect(request.method == .post)
            let payload = try #require(data as? [String: Any])
            #expect(payload["attributes"] as? [String: String] == ["screenshotDisplayType": "APP_DESKTOP"])
            return try jsonResponse(["data": screenshotSetFixture(id: "set"), "links": ["self": "unused"]], status: 201)
        case 1:
            #expect(request.path == "/v1/appScreenshots")
            let payload = try #require(data as? [String: Any])
            let attributes = try #require(payload["attributes"] as? [String: Any])
            #expect(attributes["fileSize"] as? Int == 10)
            #expect(attributes["fileName"] as? String == "image.png")
            var item = screenshotResourceFixture(id: "image", state: "AWAITING_UPLOAD")
            var fields = try #require(item["attributes"] as? [String: Any])
            fields["uploadOperations"] = [["method": "PUT", "url": "https://store.blobstore.apple.com/image?Expires=9999999999", "offset": 0, "length": 10, "requestHeaders": []]]
            item["attributes"] = fields
            return try jsonResponse(["data": item, "links": ["self": "unused"]], status: 201)
        case 2:
            #expect(request.path == "/v1/appScreenshots/image")
            #expect(request.method == .patch)
            let payload = try #require(data as? [String: Any])
            let fields = try #require(payload["attributes"] as? [String: Any])
            #expect(fields["uploaded"] as? Bool == true)
            #expect(fields["sourceFileChecksum"] as? String == String(repeating: "a", count: 32))
            return try jsonResponse(["data": screenshotResourceFixture(id: "image"), "links": ["self": "unused"]])
        default:
            #expect(request.method == .patch)
            #expect(request.path == "/v1/appScreenshotSets/set/relationships/appScreenshots")
            let relationships = try #require(data as? [[String: String]])
            #expect(relationships.map { $0["id"] } == ["b", "a"])
            return (HTTPResponse(status: .noContent), nil)
        }
    }
    let api = testAPI(transport: transport)
    _ = try await api.createScreenshotSet(localizationID: "locale", displayType: "APP_DESKTOP")
    let (reserved, operations) = try await api.reserveScreenshot(setID: "set", fileName: "image.png", byteCount: 10)
    #expect(reserved.id == "image")
    #expect(operations.count == 1)
    #expect(operations[0].length == 10)
    try await api.commitScreenshot(id: "image", checksum: String(repeating: "a", count: 32))
    try await api.orderScreenshots(setID: "set", ids: ["b", "a"])
    let deleteTransport = StubTransport { request, _, _ in
        #expect(request.method == .delete)
        #expect(request.path == "/v1/appScreenshots/image")
        return (HTTPResponse(status: .noContent), nil)
    }
    try await testAPI(transport: deleteTransport).deleteScreenshot(id: "image")
}

private func screenshotSetFixture(id: String) -> [String: Any] {
    ["type": "appScreenshotSets", "id": id, "attributes": ["screenshotDisplayType": "APP_DESKTOP"],
     "relationships": ["appStoreVersionLocalization": ["data": ["type": "appStoreVersionLocalizations", "id": "locale"]]]]
}

private func screenshotResourceFixture(id: String, state: String = "COMPLETE") -> [String: Any] {
    ["type": "appScreenshots", "id": id,
     "attributes": ["fileName": "image.png", "fileSize": 10, "sourceFileChecksum": String(repeating: "a", count: 32), "assetDeliveryState": ["state": state]],
     "relationships": ["appScreenshotSet": ["data": ["type": "appScreenshotSets", "id": "set"]]]]
}
