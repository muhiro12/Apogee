import Foundation
import OpenAPIGenerationSupport
import Testing

@Test
func archiveReaderSupportsCurrentAppleDocumentName() throws {
    let documentData = openAPIDocumentData()
    let entries = [
        "openapi.oas (2).json": documentData,
        "__MACOSX/._openapi.oas (2).json": Data("metadata".utf8),
    ]
    let listing = entries.keys.sorted().joined(separator: "\n")

    let document = try OpenAPIArchiveReader().document(in: listing) { entryPath in
        try #require(entries[entryPath])
    }

    #expect(document.path == "openapi.oas (2).json")
    #expect(document.data == documentData)
}

@Test
func archiveReaderSupportsHistoricalDocumentName() throws {
    let documentData = openAPIDocumentData()
    let document = try OpenAPIArchiveReader().document(in: "openapi.oas.json\n") { entryPath in
        #expect(entryPath == "openapi.oas.json")
        return documentData
    }

    #expect(document.path == "openapi.oas.json")
}

@Test
func archiveReaderRejectsMissingOpenAPIDocument() {
    do {
        _ = try OpenAPIArchiveReader().document(in: "notes.json\nREADME.txt\n") { _ in
            Data("{}".utf8)
        }
        Issue.record("Expected the archive reader to reject an archive without an OpenAPI document.")
    } catch {
        #expect(error as? OpenAPIArchiveError == .documentNotFound)
    }
}

@Test
func archiveReaderRejectsMultipleOpenAPIDocuments() {
    do {
        _ = try OpenAPIArchiveReader().document(in: "first.json\nsecond.json\n") { _ in
            openAPIDocumentData()
        }
        Issue.record("Expected the archive reader to reject multiple OpenAPI documents.")
    } catch {
        #expect(error as? OpenAPIArchiveError == .multipleDocuments(["first.json", "second.json"]))
    }
}

@Test
func archiveReaderRejectsTooManyCandidateDocuments() {
    let reader = OpenAPIArchiveReader(
        limits: .init(maximumCandidateCount: 1)
    )

    do {
        _ = try reader.document(in: "first.json\nsecond.json\n") { _ in
            openAPIDocumentData()
        }
        Issue.record("Expected the archive reader to enforce its candidate limit.")
    } catch {
        #expect(
            error as? OpenAPIArchiveError
                == .tooManyCandidateDocuments(maximum: 1)
        )
    }
}

@Test
func archiveReaderRejectsOversizedDocuments() {
    let reader = OpenAPIArchiveReader(
        limits: .init(maximumDocumentByteCount: 8)
    )

    do {
        _ = try reader.document(in: "openapi.json\n") { _ in
            Data(repeating: 0, count: 9)
        }
        Issue.record("Expected the archive reader to enforce its document limit.")
    } catch {
        #expect(
            error as? OpenAPIArchiveError
                == .documentTooLarge(path: "openapi.json", maximumByteCount: 8)
        )
    }
}

@Test
func openAPITrimmerRejectsExcessiveNesting() throws {
    let sourceData = try JSONSerialization.data(withJSONObject: [
        "openapi": "3.0.1",
        "paths": [
            "/v1/apps": [
                "get": [
                    "operationId": "apps_getCollection",
                    "responses": [
                        "200": [
                            "content": [
                                "application/json": [
                                    "schema": [
                                        "type": "object",
                                    ],
                                ],
                            ],
                        ],
                    ],
                ],
            ],
        ],
        "components": [:],
    ])
    let outputURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("openapi.json")

    do {
        _ = try OpenAPITrimmer(maximumNestingDepth: 2).trim(
            sourceData: sourceData,
            outputURL: outputURL
        )
        Issue.record("Expected the trimmer to enforce its nesting limit.")
    } catch {
        #expect(error as? TrimmerError == .nestingDepthExceeded(maximum: 2))
    }
}

private func openAPIDocumentData() -> Data {
    Data(
        """
        {
          "openapi": "3.0.1",
          "paths": {},
          "components": {}
        }
        """.utf8
    )
}
