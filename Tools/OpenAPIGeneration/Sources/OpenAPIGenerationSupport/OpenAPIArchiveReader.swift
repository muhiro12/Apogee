import Foundation

package struct OpenAPIArchiveDocument: Sendable {
    package var path: String
    package var data: Data
}

package struct OpenAPIArchiveReader: Sendable {
    package init() {}

    package func document(
        in archiveListing: String,
        entryData: (String) throws -> Data
    ) throws -> OpenAPIArchiveDocument {
        var documents: [OpenAPIArchiveDocument] = []

        for entryPath in candidateEntryPaths(in: archiveListing) {
            let data = try entryData(entryPath)
            guard isOpenAPIDocument(data) else {
                continue
            }

            documents.append(.init(path: entryPath, data: data))
        }

        switch documents.count {
        case 1:
            return documents[0]
        case 0:
            throw OpenAPIArchiveError.documentNotFound
        default:
            throw OpenAPIArchiveError.multipleDocuments(documents.map(\.path))
        }
    }

    private func candidateEntryPaths(in archiveListing: String) -> [String] {
        archiveListing
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { entryPath in
                let pathComponents = entryPath.split(separator: "/")
                let isMetadata = pathComponents.contains { component in
                    component == "__MACOSX" || component.hasPrefix("._")
                }
                return !isMetadata && entryPath.lowercased().hasSuffix(".json")
            }
    }

    private func isOpenAPIDocument(_ data: Data) -> Bool {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let openAPIVersion = root["openapi"] as? String,
            !openAPIVersion.isEmpty,
            root["paths"] is [String: Any],
            root["components"] is [String: Any]
        else {
            return false
        }

        return true
    }
}

package enum OpenAPIArchiveError: Error, Equatable, CustomStringConvertible {
    case documentNotFound
    case multipleDocuments([String])

    package var description: String {
        switch self {
        case .documentNotFound:
            "The archive does not contain an OpenAPI JSON document."
        case let .multipleDocuments(paths):
            "The archive contains multiple OpenAPI JSON documents: \(paths.joined(separator: ", "))."
        }
    }
}
