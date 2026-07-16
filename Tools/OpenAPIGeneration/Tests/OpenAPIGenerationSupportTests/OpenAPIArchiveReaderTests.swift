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
