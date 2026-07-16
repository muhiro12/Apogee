import Foundation

package struct OpenAPIArchiveDocument: Sendable {
    package var path: String
    package var data: Data
}

package struct OpenAPIArchiveLimits: Sendable {
    package let maximumCandidateCount: Int
    package let maximumDocumentByteCount: Int

    package init(
        maximumCandidateCount: Int = 16,
        maximumDocumentByteCount: Int = 64 * 1_024 * 1_024
    ) {
        precondition(maximumCandidateCount > 0)
        precondition(maximumDocumentByteCount > 0)
        self.maximumCandidateCount = maximumCandidateCount
        self.maximumDocumentByteCount = maximumDocumentByteCount
    }
}

package struct OpenAPIArchiveReader: Sendable {
    private let limits: OpenAPIArchiveLimits

    package init(limits: OpenAPIArchiveLimits = .init()) {
        self.limits = limits
    }

    package func document(
        in archiveListing: String,
        entryData: (String) throws -> Data
    ) throws -> OpenAPIArchiveDocument {
        let candidateEntryPaths = candidateEntryPaths(in: archiveListing)
        guard candidateEntryPaths.count <= limits.maximumCandidateCount else {
            throw OpenAPIArchiveError.tooManyCandidateDocuments(
                maximum: limits.maximumCandidateCount
            )
        }

        var document: OpenAPIArchiveDocument?
        for entryPath in candidateEntryPaths {
            let data = try entryData(entryPath)
            guard data.count <= limits.maximumDocumentByteCount else {
                throw OpenAPIArchiveError.documentTooLarge(
                    path: entryPath,
                    maximumByteCount: limits.maximumDocumentByteCount
                )
            }

            guard isOpenAPIDocument(data) else {
                continue
            }

            if let document {
                throw OpenAPIArchiveError.multipleDocuments([document.path, entryPath])
            }
            document = .init(path: entryPath, data: data)
        }

        guard let document else {
            throw OpenAPIArchiveError.documentNotFound
        }
        return document
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
    case documentTooLarge(path: String, maximumByteCount: Int)
    case multipleDocuments([String])
    case tooManyCandidateDocuments(maximum: Int)

    package var description: String {
        switch self {
        case .documentNotFound:
            "The archive does not contain an OpenAPI JSON document."
        case let .documentTooLarge(path, maximumByteCount):
            "OpenAPI archive entry \(path) exceeds the \(maximumByteCount)-byte limit."
        case let .multipleDocuments(paths):
            "The archive contains multiple OpenAPI JSON documents: \(paths.joined(separator: ", "))."
        case let .tooManyCandidateDocuments(maximum):
            "The archive contains more than \(maximum) candidate JSON documents."
        }
    }
}
