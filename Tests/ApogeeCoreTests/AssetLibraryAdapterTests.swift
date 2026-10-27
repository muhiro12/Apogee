@testable import ApogeeCore
import Foundation
import HTTPTypes
import Testing

@Test
func assetLibraryReferenceAndIdentityUsePublicResources() async throws {
    let transport = StubTransport { request, _, index in
        if index == 0 {
            #expect(request.path == "/v1/apps/app/assetLibrary")
            return try jsonResponse(["data": ["type": "appAssetLibraries", "id": "library"], "links": ["self": "unused"]])
        }
        #expect(request.path == "/v1/appAssetLibraryRefData")
        return try jsonResponse(libraryReferenceFixture())
    }
    let api = testAPI(transport: transport)
    #expect(try await api.libraryID(appID: "app") == "library")
    let reference = try await api.libraryReferenceData()
    #expect(reference.placementProfileGroups.first?.displayClassId == "IPHONE_DUO")
    #expect(reference.imageSpecs.first?.specId == "runtime-spec")
}

@Test(arguments: ["ACTIVE", "PARENT_PREPARE_FOR_SUBMISSION", "ASSET_PROCESSING", "FAILED", "FUTURE_STATE"])
func assetLibraryPlacementsPreserveScopeOrderAndPagination(state: String) async throws {
    let transport = StubTransport { request, _, index in
        let path = try #require(request.path)
        let decoded = path.removingPercentEncoding ?? path
        #expect(decoded.contains("filter[placementType]=APP_SCREENSHOT"))
        #expect(decoded.contains("filter[placementGroup]=runtime-duo-group"))
        #expect(decoded.contains("sort=placementGroupPosition"))
        var links = ["self": "unused"]
        if index == 0 {
            links["next"] = "https://api.appstoreconnect.apple.com" + path + "&cursor=next"
        }
        return try jsonResponse(["data": [libraryPlacementFixture(id: "placement-\(index)", imageID: "image-\(index)", state: state)],
                                 "links": links, "meta": ["paging": ["limit": 200, "total": 2]]])
    }
    let placements = try await testAPI(transport: transport).libraryPlacements(localizationID: "localization", group: "runtime-duo-group")
    #expect(placements.map(\.id) == ["placement-0", "placement-1"])
    #expect(placements.allSatisfy { $0.state == state })
    #expect(await transport.requests.count == 2)
}

@Test(arguments: ["parent", "media", "group", "cursor", "total"])
func assetLibraryRefusesIncompleteOrOutOfScopePlacements(scenario: String) async throws {
    let transport = StubTransport { _, _, _ in
        var item = libraryPlacementFixture(id: "placement", imageID: "image")
        if scenario == "parent" {
            item["relationships"] = ["image": ["data": ["type": "appAssetLibraryImages", "id": "image"]]]
        }
        if scenario == "media" || scenario == "group" {
            item["attributes"] = ["mediaType": scenario == "media" ? "VIDEO" : "IMAGE", "placementType": "APP_SCREENSHOT",
                                  "placementGroup": scenario == "group" ? "other-group" : "runtime-duo-group", "state": "PARENT_PREPARE_FOR_SUBMISSION"]
        }
        var paging: [String: Any] = ["limit": 200, "total": scenario == "total" ? 2 : 1]
        if scenario == "cursor" {
            paging["nextCursor"] = "unreadable-next-page"
        }
        return try jsonResponse(["data": [item], "links": ["self": "unused"], "meta": ["paging": paging]])
    }
    await #expect(throws: (any Error).self) {
        _ = try await testAPI(transport: transport).libraryPlacements(localizationID: "localization", group: "runtime-duo-group")
    }
}

@Test(arguments: ["ACTIVE", "PARENT_PREPARE_FOR_SUBMISSION", "ASSET_PROCESSING"])
func assetLibraryEncodesUploadsPlacementsAndOrderingWithoutChecksums(state: String) async throws {
    let directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: directory)
    }
    let path = directory.appendingPathComponent("image.png")
    try screenshotPNG(seed: 1).write(to: path)
    let image = try ScreenshotImage(url: path)
    let size = image.data.count
    let transport = StubTransport { request, body, index in
        if index == 4 {
            #expect(request.method == .delete)
            #expect(request.path == "/v1/appAssetLibraryPlacements/placement")
            return (HTTPResponse(status: .noContent), nil)
        }
        let payload = try #require(body.flatMap { try JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] })
        let data = try #require(payload["data"] as? [String: Any])
        let attributes = try #require(data["attributes"] as? [String: Any])
        #expect(!String(describing: payload).contains("sourceFileChecksum"))
        switch index {
        case 0:
            #expect(request.path == "/v1/appAssetLibraryImages")
            #expect(attributes["category"] as? String == "APP_SCREENSHOTS_AND_PREVIEWS")
            #expect(attributes["fileSize"] as? Int == size)
            #expect(attributes["referenceName"] as? String == "local-reference")
            var item = libraryImageFixture(size: size, state: "AWAITING_UPLOAD")
            var fields = try #require(item["attributes"] as? [String: Any])
            fields["uploadOperations"] = [["method": "PUT", "url": "https://store.blobstore.apple.com/asset", "offset": 0, "length": size, "requestHeaders": []]]
            item["attributes"] = fields
            return try jsonResponse(["data": item, "links": ["self": "unused"]], status: 201)
        case 1:
            #expect(request.path == "/v1/appAssetLibraryImages/image")
            #expect(Set(attributes.keys) == ["uploaded"])
            #expect(attributes["uploaded"] as? Bool == true)
            return try jsonResponse(["data": libraryImageFixture(size: size), "links": ["self": "unused"]])
        case 2:
            #expect(request.path == "/v1/appAssetLibraryPlacements")
            #expect(attributes["placementGroup"] as? String == "runtime-duo-group")
            #expect(attributes["placementType"] as? String == "APP_SCREENSHOT")
            let relationships = try #require(data["relationships"] as? [String: Any])
            #expect(Set(relationships.keys) == ["image", "appStoreVersionLocalization"])
            return try jsonResponse(["data": libraryPlacementFixture(id: "placement", imageID: "image", state: state), "links": ["self": "unused"]], status: 201)
        default:
            #expect(request.path == "/v1/appAssetLibraryPlacementOrderingRequests")
            let relationships = try #require(data["relationships"] as? [String: Any])
            let ordered = try #require(relationships["orderedPlacements"] as? [String: Any])
            #expect((ordered["data"] as? [[String: String]])?.map { $0["id"] } == ["b", "a"])
            return try jsonResponse(["data": ["type": "appAssetLibraryPlacementOrderingRequests", "id": "order"], "links": ["self": "unused"]], status: 201)
        }
    }
    let api = testAPI(transport: transport)
    let (reserved, operations) = try await api.reserveLibraryImage(libraryID: "library", image: image, reference: "local-reference")
    #expect(reserved.id == "image")
    #expect(operations.count == 1)
    try await api.commitLibraryImage(id: reserved.id)
    let placement = try await api.createLibraryPlacement(imageID: reserved.id, localizationID: "localization", group: "runtime-duo-group")
    #expect(placement.imageID == reserved.id)
    #expect(placement.state == state)
    try await api.orderLibraryPlacements(localizationID: "localization", group: "runtime-duo-group", ids: ["b", "a"])
    try await api.deleteLibraryPlacement(id: placement.id)
    #expect(await transport.requests.count == 5)
}

func libraryReferenceFixture() -> [String: Any] {
    ["data": [["type": "appAssetLibraryRefData", "id": "reference", "attributes": [
        "placementProfileGroups": [
            ["placementProfileGroupId": "runtime-duo-group", "platform": "IPHONE_APP_STORE", "displayClassId": "IPHONE_DUO"],
            ["placementProfileGroupId": "runtime-large-group", "platform": "IPHONE_APP_STORE", "displayClassId": "IPHONE_DYNAMIC_ISLAND_LARGE_DISPLAY"],
        ],
        "imageSpecs": [["specId": "runtime-spec", "dimensions": ["minWidth": 2, "maxWidth": 2, "minHeight": 2, "maxHeight": 2],
                        "compatiblePlacementTypes": ["APP_SCREENSHOT"], "fileExtensions": ["png"], "mimeTypes": ["image/png"], "maxFileSize": 100000]],
        "placementTypes": [["placementTypeId": "APP_SCREENSHOT", "acceptsAssetCategories": ["APP_SCREENSHOTS_AND_PREVIEWS"], "specMappings": [
            ["placementGroupId": "runtime-duo-group", "specs": ["runtime-spec"]],
            ["placementGroupId": "runtime-large-group", "specs": ["runtime-spec"]],
        ]]],
        "features": [["featureId": "APP_STORE_VERSIONS", "placementPolicies": [["placementType": "APP_SCREENSHOT", "groupLimits": [
            ["groupIds": ["runtime-duo-group"], "maxCount": 10], ["groupIds": ["runtime-large-group"], "maxCount": 10],
        ]]]]],
    ]]], "links": ["self": "unused"]]
}

func libraryImageFixture(size: Int, state: String = "COMPLETE") -> [String: Any] {
    ["type": "appAssetLibraryImages", "id": "image", "attributes": [
        "category": "APP_SCREENSHOTS_AND_PREVIEWS", "fileName": "image.png", "fileSize": size,
        "referenceName": "local-reference", "specId": "runtime-spec", "state": state,
    ]]
}

func libraryPlacementFixture(id: String, imageID: String, state: String = "PARENT_PREPARE_FOR_SUBMISSION") -> [String: Any] {
    ["type": "appAssetLibraryPlacements", "id": id,
     "attributes": ["mediaType": "IMAGE", "placementType": "APP_SCREENSHOT", "placementGroup": "runtime-duo-group", "state": state],
     "relationships": [
        "image": ["data": ["type": "appAssetLibraryImages", "id": imageID]],
        "appStoreVersionLocalization": ["data": ["type": "appStoreVersionLocalizations", "id": "localization"]],
     ]]
}

@Test
func productionScreenshotErrorsNeverFallBackToLegacyEndpoints() async throws {
    let directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
    let display = directory.appendingPathComponent("en-US/IPHONE_DUO")
    try FileManager.default.createDirectory(at: display, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: directory)
    }
    try screenshotPNG(seed: 1).write(to: display.appendingPathComponent("image.png"))
    let transport = StubTransport { request, _, _ in
        #expect(request.method == .get)
        let path = request.path ?? ""
        if path == "/v1/apps/app" {
            return try jsonResponse(["data": ["type": "apps", "id": "app"], "links": ["self": "unused"]])
        }
        if path.contains("/apps/app/appStoreVersions") {
            return try jsonResponse(["data": [["type": "appStoreVersions", "id": "version", "attributes": [
                "versionString": "2.0", "platform": "IOS", "appVersionState": "PREPARE_FOR_SUBMISSION",
            ]]], "links": ["self": "unused"]])
        }
        if path.contains("/appStoreVersions/version/appStoreVersionLocalizations") {
            return try jsonResponse(["data": [["type": "appStoreVersionLocalizations", "id": "localization", "attributes": ["locale": "en-US"]]], "links": ["self": "unused"]])
        }
        #expect(path == "/v1/appAssetLibraryRefData")
        return try jsonResponse(["errors": [["status": "403", "code": "FORBIDDEN", "title": "Unavailable"]]], status: 403)
    }
    await #expect(throws: ApogeeError.appStoreConnectHTTPError(operation: "appAssetLibraryRefData_getCollection", statusCode: 403)) {
        _ = try await ReleaseAutomation(api: testAPI(transport: transport)).updateScreenshots(
            appLookup: .appID("app"), version: "2.0", screenshotsPath: directory.path, options: .init(mode: .apply)
        )
    }
    #expect(await transport.requests.last?.path == "/v1/appAssetLibraryRefData")
    #expect(await !transport.requests.contains { ($0.path ?? "").contains("appScreenshot") })
}

@Test(arguments: ["ACTIVE", "PARENT_PREPARE_FOR_SUBMISSION", "ASSET_PROCESSING", "FAILED", "FUTURE_STATE", "PARENT_APPROVED",
                  "https://example.invalid/signed?token=private-sentinel", "FUTURE_STATE\nprivate-sentinel"], [false, true])
func existingPlacementStateRunsThroughTheProductionAdapterAndWorkflow(state: String, apply: Bool) async throws {
    let directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
    let display = directory.appendingPathComponent("en-US/IPHONE_DUO")
    try FileManager.default.createDirectory(at: display, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: directory)
    }
    let file = display.appendingPathComponent("image.png")
    try screenshotPNG(seed: 1).write(to: file)
    let image = try ScreenshotImage(url: file)
    let transport = StubTransport { request, _, _ in
        #expect(request.method == .get)
        let path = request.path ?? ""
        if path == "/v1/apps/app" {
            return try jsonResponse(["data": ["type": "apps", "id": "app"], "links": ["self": "unused"]])
        }
        if path.contains("/apps/app/appStoreVersions") {
            return try jsonResponse(["data": [["type": "appStoreVersions", "id": "version", "attributes": [
                "versionString": "2.0", "platform": "IOS", "appVersionState": "PREPARE_FOR_SUBMISSION",
            ]]], "links": ["self": "unused"]])
        }
        if path.contains("/appStoreVersions/version/appStoreVersionLocalizations") {
            return try jsonResponse(["data": [["type": "appStoreVersionLocalizations", "id": "localization", "attributes": ["locale": "en-US"]]], "links": ["self": "unused"]])
        }
        if path == "/v1/appAssetLibraryRefData" {
            return try jsonResponse(libraryReferenceFixture())
        }
        if path.contains("/appStoreVersionLocalizations/localization/placements") {
            return try jsonResponse([
                "data": [libraryPlacementFixture(id: "placement", imageID: "image", state: state)],
                "links": ["self": "unused"], "meta": ["paging": ["limit": 200, "total": 1]],
            ])
        }
        #expect(path == "/v1/appAssetLibraryImages/image")
        var item = libraryImageFixture(size: image.data.count)
        var attributes = try #require(item["attributes"] as? [String: Any])
        attributes["referenceName"] = AssetLibraryScreenshotWorkflow.reference(image)
        item["attributes"] = attributes
        return try jsonResponse(["data": item, "links": ["self": "unused"]])
    }
    do {
        let plan = try await ReleaseAutomation(api: testAPI(transport: transport)).updateScreenshots(
            appLookup: .appID("app"), version: "2.0", screenshotsPath: directory.path,
            options: .init(mode: apply ? .apply : .dryRun)
        )
        #expect(["ACTIVE", "PARENT_PREPARE_FOR_SUBMISSION"].contains(state))
        #expect(!plan.hasChanges)
        #expect(plan.actions.allSatisfy { $0.kind == .unchanged })
    } catch {
        #expect(!["ACTIVE", "PARENT_PREPARE_FOR_SUBMISSION"].contains(state))
        let diagnostic = String(describing: error)
        #expect(diagnostic.contains("appAssetLibraryPlacements"))
        #expect(diagnostic.contains(state.contains("private-sentinel") ? "<unrecognized>" : state))
        #expect(!diagnostic.contains("private-sentinel"))
        #expect(!diagnostic.contains("Bearer"))
    }
    #expect(await transport.requests.allSatisfy { $0.method == .get })
}
