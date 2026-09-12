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
          "UploadReservation": {"type": "object"}
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

    #expect(result.pathCount == 1)
    #expect(result.componentReferenceCount == 2)
    #expect(Set(paths.keys) == ["/v1/apps"])
    #expect(Set(schemas.keys) == ["AppPage", "App"])
}
