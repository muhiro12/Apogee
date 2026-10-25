import Foundation

struct LibraryImage: Codable, Equatable, Sendable {
    var id: String
    var fileName: String
    var byteCount: Int
    var referenceName: String?
    var specID: String?
    var state: String

    var isProcessed: Bool {
        ["COMPLETE", "PREPARE_FOR_SUBMISSION", "READY_FOR_REVIEW", "WAITING_FOR_REVIEW", "IN_REVIEW", "ACCEPTED", "APPROVED"].contains(state)
    }
}

struct LibraryPlacement: Codable, Equatable, Sendable {
    var id: String
    var imageID: String
    var localizationID: String
    var placementType: String
    var group: String
    var state: String
}

struct LibraryReferenceData: Decodable, Sendable {
    struct Profile: Decodable, Sendable {
        var placementProfileGroupId: String
        var platform: String
        var displayClassId: String
    }
    struct Specification: Decodable, Sendable {
        struct Dimensions: Decodable, Sendable {
            var minWidth: Int
            var maxWidth: Int
            var minHeight: Int
            var maxHeight: Int
        }
        var specId: String
        var dimensions: Dimensions
        var compatiblePlacementTypes: [String]
        var fileExtensions: [String]
        var maxFileSize: Int
        var mimeTypes: [String]

        func accepts(_ image: ScreenshotImage, placementType: String) -> Bool {
            guard dimensions.minWidth > 0, dimensions.minWidth <= dimensions.maxWidth,
                  dimensions.minHeight > 0, dimensions.minHeight <= dimensions.maxHeight,
                  maxFileSize > 0 else {
                return false
            }
            return compatiblePlacementTypes.contains(placementType)
                && (dimensions.minWidth...dimensions.maxWidth).contains(image.width)
                && (dimensions.minHeight...dimensions.maxHeight).contains(image.height)
                && image.data.count <= maxFileSize
                && mimeTypes.contains(image.mimeType)
                && fileExtensions.map { $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) }.contains(image.fileExtension)
        }
    }
    struct PlacementType: Decodable, Sendable {
        struct Mapping: Decodable, Sendable {
            var placementGroupId: String
            var specs: [String]
        }
        var placementTypeId: String
        var acceptsAssetCategories: [String]
        var specMappings: [Mapping]
    }
    struct Feature: Decodable, Sendable {
        struct Policy: Decodable, Sendable {
            struct Limit: Decodable, Sendable {
                var groupIds: [String]
                var maxCount: Int
            }
            var placementType: String
            var groupLimits: [Limit]
        }
        var featureId: String
        var placementPolicies: [Policy]
    }
    var placementProfileGroups: [Profile]
    var imageSpecs: [Specification]
    var placementTypes: [PlacementType]
    var features: [Feature]

    func targets(displayClass: String, platform: Platform, images: [ScreenshotImage]) throws -> [(group: String, images: [ScreenshotImage], specs: [[String]])] {
        let platforms: [String]
        switch platform {
        case .iOS:
            platforms = ["IPHONE_APP_STORE", "IPAD_APP_STORE", "WATCH_APP_STORE"]
        case .macOS:
            platforms = ["MAC_APP_STORE"]
        case .tvOS:
            platforms = ["TV_APP_STORE"]
        case .visionOS:
            platforms = ["VISION_PRO_APP_STORE"]
        }
        let profiles = placementProfileGroups.filter {
            $0.displayClassId == displayClass && platforms.contains($0.platform)
        }
        guard !profiles.isEmpty, Set(profiles.map(\.placementProfileGroupId)).count == profiles.count else {
            throw ScreenshotError.unsupportedDisplayType
        }
        let types = placementTypes.filter { $0.placementTypeId == "APP_SCREENSHOT" }
        guard types.count == 1, let type = types.first,
              type.acceptsAssetCategories.contains("APP_SCREENSHOTS_AND_PREVIEWS"),
              Set(imageSpecs.map(\.specId)).count == imageSpecs.count else {
            throw ScreenshotError.incompleteInventory
        }
        var result: [(group: String, images: [ScreenshotImage], specs: [[String]])] = []
        var limits: [String: Int] = [:]
        for profile in profiles {
            let group = profile.placementProfileGroupId
            let values = features.filter { $0.featureId == "APP_STORE_VERSIONS" }
                .flatMap(\.placementPolicies).filter { $0.placementType == "APP_SCREENSHOT" }
                .flatMap(\.groupLimits).filter { $0.groupIds.contains(group) }
            guard !group.isEmpty, values.count == 1, let limit = values.first, limit.maxCount > 0 else {
                throw ScreenshotError.incompleteInventory
            }
            limits[group] = limit.maxCount
        }
        for image in images {
            var matches: [(String, [String])] = []
            for profile in profiles {
                let mappings = type.specMappings.filter { $0.placementGroupId == profile.placementProfileGroupId }
                guard mappings.count == 1, let mapping = mappings.first else {
                    throw ScreenshotError.incompleteInventory
                }
                let specs = imageSpecs.filter {
                    mapping.specs.contains($0.specId) && $0.accepts(image, placementType: "APP_SCREENSHOT")
                }.map(\.specId).sorted()
                if !specs.isEmpty {
                    matches.append((profile.placementProfileGroupId, specs))
                }
            }
            guard matches.count == 1, let match = matches.first else {
                throw matches.isEmpty ? ScreenshotError.invalidInput : .unsupportedDisplayType
            }
            if let index = result.firstIndex(where: { $0.group == match.0 }) {
                result[index].images.append(image)
                result[index].specs.append(match.1)
            } else {
                result.append((match.0, [image], [match.1]))
            }
        }
        for target in result {
            guard target.images.count <= (limits[target.group] ?? 0) else {
                throw ScreenshotError.setCapacityExceeded
            }
        }
        return result.sorted { $0.group < $1.group }
    }

}

protocol AssetLibraryAPI: Sendable {
    func libraryID(appID: String) async throws -> String
    func libraryReferenceData() async throws -> LibraryReferenceData
    func libraryPlacements(localizationID: String, group: String) async throws -> [LibraryPlacement]
    func libraryImage(id: String) async throws -> LibraryImage
    func reserveLibraryImage(libraryID: String, image: ScreenshotImage, reference: String) async throws -> (LibraryImage, [ScreenshotUploadOperation])
    func uploadScreenshotPart(_ data: Data, operation: ScreenshotUploadOperation) async throws
    func commitLibraryImage(id: String) async throws
    func createLibraryPlacement(imageID: String, localizationID: String, group: String) async throws -> LibraryPlacement
    func deleteLibraryPlacement(id: String) async throws
    func orderLibraryPlacements(localizationID: String, group: String, ids: [String]) async throws
}
