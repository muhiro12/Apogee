import AppStoreConnectGenerated
import Foundation

extension GeneratedAppStoreConnectAPI: AssetLibraryAPI {
    func libraryID(appID: String) async throws -> String {
        try await perform(operation: "libraryID") {
            let response = try await client().apps_assetLibrary_getToOneRelated(.init(path: .init(id: appID)))
            let id = try response.ok.body.json.data.id
            guard !id.isEmpty else {
                throw ScreenshotError.incompleteInventory
            }
            return id
        }
    }

    func libraryReferenceData() async throws -> LibraryReferenceData {
        try await perform(operation: "libraryReferenceData") {
            var total: Int?
            let pages: [LibraryReferenceData] = try await allPages { pageClient in
                let response = try await pageClient.appAssetLibraryRefData_getCollection(.init())
                let page = try response.ok.body.json
                if let count = page.meta?.paging.total {
                    guard count >= 0, total == nil || total == count else {
                        throw ScreenshotError.incompleteInventory
                    }
                    total = count
                }
                if page.meta?.paging.nextCursor != nil, page.links.next == nil {
                    throw ScreenshotError.incompleteInventory
                }
                let values = try page.data.map { item in
                    guard let attributes = item.attributes else {
                        throw ScreenshotError.incompleteInventory
                    }
                    return try Self.project(attributes, as: LibraryReferenceData.self)
                }
                return (values, page.links.next)
            }
            guard total == nil || pages.count == total else {
                throw ScreenshotError.incompleteInventory
            }
            return .init(placementProfileGroups: pages.flatMap(\.placementProfileGroups),
                         imageSpecs: pages.flatMap(\.imageSpecs), placementTypes: pages.flatMap(\.placementTypes),
                         features: pages.flatMap(\.features))
        }
    }

    func libraryPlacements(localizationID: String, group: String) async throws -> [LibraryPlacement] {
        try await perform(operation: "libraryPlacements") {
            var total: Int?
            let placements: [LibraryPlacement] = try await allPages { pageClient in
                let response = try await pageClient.appStoreVersionLocalizations_placements_getToManyRelated(.init(
                    path: .init(id: localizationID),
                    query: .init(filter_lbrack_placementType_rbrack_: [.APP_SCREENSHOT],
                                 filter_lbrack_placementGroup_rbrack_: [group],
                                 sort: [.placementGroupPosition], limit: 200,
                                 include: [.image, .appStoreVersionLocalization])
                ))
                let page = try response.ok.body.json
                if let count = page.meta?.paging.total {
                    guard count >= 0, total == nil || total == count else {
                        throw ScreenshotError.incompleteInventory
                    }
                    total = count
                }
                if page.meta?.paging.nextCursor != nil, page.links.next == nil {
                    throw ScreenshotError.incompleteInventory
                }
                let values = try page.data.map { item in
                    let wire = try Self.project(item, as: PlacementWire.self)
                    guard wire.attributes.mediaType == "IMAGE",
                          wire.attributes.placementType == "APP_SCREENSHOT",
                          wire.attributes.placementGroup == group,
                          wire.relationships.appStoreVersionLocalization.data.id == localizationID,
                          wire.relationships.appStoreVersionLocalization.data.type == "appStoreVersionLocalizations",
                          wire.relationships.image.data.type == "appAssetLibraryImages" else {
                        throw ScreenshotError.incompleteInventory
                    }
                    return LibraryPlacement(id: wire.id, imageID: wire.relationships.image.data.id,
                                            localizationID: localizationID, placementType: wire.attributes.placementType,
                                            group: group, state: wire.attributes.state)
                }
                return (values, page.links.next)
            }
            guard total == nil || placements.count == total,
                  Set(placements.map(\.id)).count == placements.count else {
                throw ScreenshotError.incompleteInventory
            }
            return placements
        }
    }

    func libraryImage(id: String) async throws -> LibraryImage {
        try await perform(operation: "libraryImage") {
            let response = try await client().appAssetLibraryImages_getInstance(.init(path: .init(id: id)))
            return try Self.image(response.ok.body.json.data).0
        }
    }

    func reserveLibraryImage(libraryID: String, image: ScreenshotImage, reference: String) async throws -> (LibraryImage, [ScreenshotUploadOperation]) {
        try await perform(operation: "reserveLibraryImage") {
            let request = Components.Schemas.AppAssetLibraryImageCreateRequest(data: .init(
                attributes: .init(category: .APP_SCREENSHOTS_AND_PREVIEWS, fileName: image.fileName,
                                  fileSize: Int64(image.data.count), referenceName: reference),
                relationships: .init(assetLibrary: .init(data: .init(id: libraryID, _type: .appAssetLibraries))),
                _type: .appAssetLibraryImages
            ))
            let response = try await client().appAssetLibraryImages_createInstance(.init(body: .json(request)))
            return try Self.image(response.created.body.json.data)
        }
    }

    func commitLibraryImage(id: String) async throws {
        try await perform(operation: "commitLibraryImage") {
            let request = Components.Schemas.AppAssetLibraryImageUpdateRequest(data: .init(
                attributes: .init(uploaded: true), id: id, _type: .appAssetLibraryImages
            ))
            let response = try await client().appAssetLibraryImages_updateInstance(.init(path: .init(id: id), body: .json(request)))
            _ = try response.ok.body.json
        }
    }

    func createLibraryPlacement(imageID: String, localizationID: String, group: String) async throws -> LibraryPlacement {
        try await perform(operation: "createLibraryPlacement") {
            let request = Components.Schemas.AppAssetLibraryPlacementCreateRequest(data: .init(value2: .init(
                attributes: .init(placementGroup: group, placementType: .APP_SCREENSHOT),
                relationships: .init(
                    appStoreVersionLocalization: .init(data: .init(id: localizationID, _type: .appStoreVersionLocalizations)),
                    image: .init(data: .init(id: imageID, _type: .appAssetLibraryImages))
                ),
                _type: .appAssetLibraryPlacements
            )))
            let response = try await client().appAssetLibraryPlacements_createInstance(.init(body: .json(request)))
            let wire = try Self.project(response.created.body.json.data, as: PlacementWire.self)
            guard wire.attributes.mediaType == "IMAGE",
                  wire.relationships.image.data.type == "appAssetLibraryImages",
                  wire.relationships.appStoreVersionLocalization.data.type == "appStoreVersionLocalizations" else {
                throw ScreenshotError.incompleteInventory
            }
            return .init(id: wire.id, imageID: wire.relationships.image.data.id,
                         localizationID: wire.relationships.appStoreVersionLocalization.data.id,
                         placementType: wire.attributes.placementType, group: wire.attributes.placementGroup,
                         state: wire.attributes.state)
        }
    }

    func deleteLibraryPlacement(id: String) async throws {
        try await perform(operation: "deleteLibraryPlacement") {
            let response = try await client().appAssetLibraryPlacements_deleteInstance(.init(path: .init(id: id)))
            _ = try response.noContent
        }
    }

    func orderLibraryPlacements(localizationID: String, group: String, ids: [String]) async throws {
        try await perform(operation: "orderLibraryPlacements") {
            let request = Components.Schemas.AppAssetLibraryPlacementOrderingRequestCreateRequest(data: .init(value1: .init(
                attributes: .init(placementGroup: group),
                relationships: .init(
                    appStoreVersionLocalization: .init(data: .init(id: localizationID, _type: .appStoreVersionLocalizations)),
                    orderedPlacements: .init(data: ids.map { .init(id: $0, _type: .appAssetLibraryPlacements) })
                ),
                _type: .appAssetLibraryPlacementOrderingRequests
            )))
            let response = try await client().appAssetLibraryPlacementOrderingRequests_createInstance(.init(body: .json(request)))
            _ = try response.created.body.json
        }
    }

    private static func project<Value: Encodable, Result: Decodable>(_ value: Value, as: Result.Type) throws -> Result {
        try JSONDecoder().decode(Result.self, from: JSONEncoder().encode(value))
    }

    private static func image(_ item: Components.Schemas.AppAssetLibraryImage) throws -> (LibraryImage, [ScreenshotUploadOperation]) {
        let wire = try project(item, as: ImageWire.self)
        guard !wire.id.isEmpty, wire.attributes.category == "APP_SCREENSHOTS_AND_PREVIEWS",
              wire.attributes.fileSize > 0, !wire.attributes.fileName.isEmpty else {
            throw ScreenshotError.incompleteInventory
        }
        var operations: [ScreenshotUploadOperation] = []
        for operation in wire.attributes.uploadOperations ?? [] {
            var headers: [String: String] = [:]
            for field in operation.requestHeaders {
                guard !headers.keys.contains(where: { $0.lowercased() == field.name.lowercased() }) else {
                    throw ScreenshotError.unsafeUpload
                }
                headers[field.name] = field.value
            }
            operations.append(.init(method: operation.method, url: operation.url,
                                    offset: operation.offset, length: operation.length, headers: headers))
        }
        return (.init(id: wire.id, fileName: wire.attributes.fileName, byteCount: wire.attributes.fileSize,
                      referenceName: wire.attributes.referenceName, specID: wire.attributes.specId,
                      state: wire.attributes.state), operations)
    }
}

private struct ImageWire: Decodable {
    struct Attributes: Decodable {
        struct Upload: Decodable {
            struct Header: Decodable {
                var name: String
                var value: String
            }
            var method: String
            var url: String
            var offset: Int
            var length: Int
            var requestHeaders: [Header]
        }
        var category: String
        var fileName: String
        var fileSize: Int
        var referenceName: String?
        var specId: String?
        var state: String
        var uploadOperations: [Upload]?
    }
    var id: String
    var attributes: Attributes
}

private struct PlacementWire: Decodable {
    struct Attributes: Decodable {
        var mediaType: String
        var placementType: String
        var placementGroup: String
        var state: String
    }
    struct Relationships: Decodable {
        struct Relationship: Decodable {
            struct Identity: Decodable {
                var id: String
                var type: String
            }
            var data: Identity
        }
        var image: Relationship
        var appStoreVersionLocalization: Relationship
    }
    var id: String
    var attributes: Attributes
    var relationships: Relationships
}
