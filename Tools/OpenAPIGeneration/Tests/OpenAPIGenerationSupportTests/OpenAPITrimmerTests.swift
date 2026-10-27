import Foundation
import OpenAPIGenerationSupport
import Testing

@Test
func trimmerDropsUnusedOperationsAndTheirExclusiveComponents() throws {
    let sourceData = Data("""
    {
      "openapi": "3.0.1",
      "paths": {
        "/v1/apps": {
          "get": {
            "operationId": "apps_getCollection",
            "responses": {"200": {"$ref": "#/components/schemas/AppPage"}}
          }
        },
        "/v1/appStoreVersions": {
          "post": {
            "operationId": "appStoreVersions_createInstance",
            "requestBody": {"content": {"application/json": {"schema": {"$ref": "#/components/schemas/VersionCreate"}}}},
            "responses": {"201": {"description": "Created"}}
          }
        },
        "/v1/appStoreVersions/{id}": {
          "patch": {
            "operationId": "appStoreVersions_updateInstance",
            "requestBody": {"content": {"application/json": {"schema": {"$ref": "#/components/schemas/VersionUpdate"}}}},
            "responses": {"200": {"description": "Updated"}}
          }
        },
        "/v1/appPreviews": {
          "post": {
            "operationId": "appPreviews_createInstance",
            "responses": {"201": {"$ref": "#/components/schemas/PreviewReservation"}}
          }
        },
        "/v1/appScreenshots": {
          "post": {
            "operationId": "appScreenshots_createInstance",
            "responses": {"201": {"$ref": "#/components/schemas/UploadReservation"}}
          }
        }
      },
      "components": {
        "schemas": {
          "AppPage": {"properties": {"app": {"$ref": "#/components/schemas/App"}}},
          "App": {"type": "object"},
          "PreviewReservation": {"type": "object"},
          "UploadReservation": {"type": "object"},
          "VersionUpdate": {"type": "object"},
          "VersionCreate": {"type": "object"}
        }
      }
    }
    """.utf8)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let outputURL = directory.appendingPathComponent("openapi.json")

    let result = try OpenAPITrimmer().trim(sourceData: sourceData, outputURL: outputURL)
    let document = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: outputURL)) as? [String: Any])
    let paths = try #require(document["paths"] as? [String: Any])
    let components = try #require(document["components"] as? [String: Any])
    let schemas = try #require(components["schemas"] as? [String: Any])

    #expect(result.pathCount == 4)
    #expect(result.componentReferenceCount == 5)
    #expect(Set(paths.keys) == ["/v1/apps", "/v1/appStoreVersions", "/v1/appStoreVersions/{id}", "/v1/appScreenshots"])
    #expect(Set(schemas.keys) == ["AppPage", "App", "VersionCreate", "VersionUpdate", "UploadReservation"])
}

@Test
func trimmerPreservesCommonFieldsAndRequiredConstraintsInComposedRequests() throws {
    let source = Data("""
    {"paths":{"/placements":{"post":{
      "operationId":"appAssetLibraryPlacements_createInstance",
      "requestBody":{"content":{"application/json":{"schema":{"$ref":"#/components/schemas/Request"}}}}
    }}},"components":{"schemas":{"Request":{
      "type":"object","required":["type"],
      "properties":{"type":{"type":"string"},"relationships":{
        "type":"object","properties":{"image":{"$ref":"#/components/schemas/Identity"},"localization":{"type":"string"}}
      }},
      "anyOf":[{"type":"object","required":["relationships"],"properties":{
        "relationships":{"type":"object","required":["image","localization"]}
      }}]
    },"Identity":{"type":"string"}}}}
    """.utf8)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {
        try? FileManager.default.removeItem(at: directory)
    }
    let output = directory.appendingPathComponent("openapi.json")
    _ = try OpenAPITrimmer().trim(sourceData: source, outputURL: output)
    let document = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: output)) as? [String: Any])
    let components = try #require(document["components"] as? [String: Any])
    let schemas = try #require(components["schemas"] as? [String: Any])
    let request = try #require(schemas["Request"] as? [String: Any])
    let alternatives = try #require(request["anyOf"] as? [[String: Any]])
    let alternative = try #require(alternatives.first)
    #expect(Set(alternative["required"] as? [String] ?? []) == ["type", "relationships"])
    let properties = try #require(alternative["properties"] as? [String: Any])
    let relationships = try #require(properties["relationships"] as? [String: Any])
    #expect(Set(relationships["required"] as? [String] ?? []) == ["image", "localization"])
    let fields = try #require(relationships["properties"] as? [String: Any])
    #expect(Set(fields.keys) == ["image", "localization"])
    #expect(schemas["Identity"] != nil)
}

@Test
func trimmerPreservesPlacementStatesWithoutOpeningUnrelatedEnums() throws {
    let source = Data("""
    {"paths":{"/placements":{"get":{
      "operationId":"appStoreVersionLocalizations_placements_getToManyRelated",
      "responses":{"200":{"content":{"application/json":{"schema":{"$ref":"#/components/schemas/Placement"}}}}}
    }}},"components":{"schemas":{
      "Placement":{"type":"object","properties":{
        "state":{"$ref":"#/components/schemas/AppAssetLibraryPlacementState"},
        "type":{"$ref":"#/components/schemas/PlacementType"}
      }},
      "AppAssetLibraryPlacementState":{"type":"string","enum":["ASSET_PROCESSING","FAILED","PARENT_PREPARE_FOR_SUBMISSION"]},
      "PlacementType":{"type":"string","enum":["APP_SCREENSHOT"]}
    }}}
    """.utf8)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {
        try? FileManager.default.removeItem(at: directory)
    }
    let output = directory.appendingPathComponent("openapi.json")
    _ = try OpenAPITrimmer().trim(sourceData: source, outputURL: output)
    let document = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: output)) as? [String: Any])
    let components = try #require(document["components"] as? [String: Any])
    let schemas = try #require(components["schemas"] as? [String: Any])
    let state = try #require(schemas["AppAssetLibraryPlacementState"] as? [String: Any])
    #expect(state["type"] as? String == "string")
    #expect(state["enum"] == nil)
    let type = try #require(schemas["PlacementType"] as? [String: Any])
    #expect(type["enum"] as? [String] == ["APP_SCREENSHOT"])
}
