import Foundation

package struct OpenAPITrimResult {
    package let pathCount: Int
    package let componentReferenceCount: Int
}

package struct OpenAPITrimmer {
    private let selectedOperationIDs: Set<String> = [
        "apps_getCollection",
        "apps_getInstance",
        "apps_appStoreVersions_getToManyRelated",
        "apps_webhooks_getToManyRelated",
        "appStoreVersions_getInstance",
        "appStoreVersions_appStoreVersionLocalizations_getToManyRelated",
        "appStoreVersions_build_getToOneRelated",
        "appStoreVersions_build_updateToOneRelationship",
        "appStoreVersionLocalizations_getInstance",
        "appStoreVersionLocalizations_updateInstance",
        "builds_getCollection",
        "builds_getInstance",
        "appScreenshotSets_createInstance",
        "appScreenshotSets_getInstance",
        "appScreenshotSets_deleteInstance",
        "appScreenshotSets_appScreenshots_getToManyRelated",
        "appScreenshotSets_appScreenshots_replaceToManyRelationship",
        "appScreenshots_createInstance",
        "appScreenshots_getInstance",
        "appScreenshots_updateInstance",
        "appScreenshots_deleteInstance",
        "appStoreVersionLocalizations_appScreenshotSets_getToManyRelated",
        "reviewSubmissions_getCollection",
        "reviewSubmissions_createInstance",
        "reviewSubmissions_getInstance",
        "reviewSubmissions_updateInstance",
        "reviewSubmissionItems_createInstance",
        "reviewSubmissionItems_updateInstance",
        "reviewSubmissionItems_deleteInstance",
        "webhooks_createInstance",
        "webhooks_getInstance",
        "webhooks_updateInstance",
        "webhooks_deleteInstance",
    ]

    private let methodNames: Set<String> = ["get", "post", "patch", "delete"]
    private let maximumNestingDepth: Int

    package init(maximumNestingDepth: Int = 128) {
        precondition(maximumNestingDepth > 0)
        self.maximumNestingDepth = maximumNestingDepth
    }

    package func trim(sourceData: Data, outputURL: URL) throws -> OpenAPITrimResult {
        guard
            let root = try JSONSerialization.jsonObject(with: sourceData) as? [String: Any],
            let sourcePaths = root["paths"] as? [String: Any],
            let sourceComponents = root["components"] as? [String: Any]
        else {
            throw TrimmerError.invalidOpenAPIDocument
        }

        var trimmedPaths: [String: Any] = [:]
        var referencedComponents: Set<ComponentReference> = []
        var queuedComponents: [ComponentReference] = []

        func enqueueReferences(in value: Any, depth: Int = 0) throws {
            guard depth <= maximumNestingDepth else {
                throw TrimmerError.nestingDepthExceeded(maximum: maximumNestingDepth)
            }

            if let dictionary = value as? [String: Any] {
                if let ref = dictionary["$ref"] as? String,
                   let componentReference = ComponentReference(ref: ref),
                   !referencedComponents.contains(componentReference) {
                    referencedComponents.insert(componentReference)
                    queuedComponents.append(componentReference)
                }

                for nestedValue in dictionary.values {
                    try enqueueReferences(in: nestedValue, depth: depth + 1)
                }
            } else if let array = value as? [Any] {
                for element in array {
                    try enqueueReferences(in: element, depth: depth + 1)
                }
            }
        }

        for (path, rawPathItem) in sourcePaths {
            guard let pathItem = rawPathItem as? [String: Any] else {
                continue
            }

            var trimmedPathItem: [String: Any] = [:]

            if let parameters = pathItem["parameters"] {
                let sanitizedParameters = try sanitized(parameters)
                trimmedPathItem["parameters"] = sanitizedParameters
                try enqueueReferences(in: sanitizedParameters)
            }

            for (key, value) in pathItem where methodNames.contains(key) {
                guard
                    let operation = value as? [String: Any],
                    let operationID = operation["operationId"] as? String,
                    selectedOperationIDs.contains(operationID)
                else {
                    continue
                }

                let sanitizedOperation = try sanitized(operation)
                trimmedPathItem[key] = sanitizedOperation
                try enqueueReferences(in: sanitizedOperation)
            }

            if trimmedPathItem.keys.contains(where: methodNames.contains) {
                trimmedPaths[path] = trimmedPathItem
            }
        }

        var trimmedComponents: [String: Any] = [:]

        while let componentReference = queuedComponents.popLast() {
            guard
                let componentGroup = sourceComponents[componentReference.section] as? [String: Any],
                let componentValue = componentGroup[componentReference.name]
            else {
                throw TrimmerError.missingComponent(componentReference.ref)
            }

            var outputGroup = trimmedComponents[componentReference.section] as? [String: Any] ?? [:]
            let sanitizedComponentValue = try sanitized(componentValue)
            outputGroup[componentReference.name] = sanitizedComponentValue
            trimmedComponents[componentReference.section] = outputGroup
            try enqueueReferences(in: sanitizedComponentValue)
        }

        if let securitySchemes = sourceComponents["securitySchemes"] {
            trimmedComponents["securitySchemes"] = try sanitized(securitySchemes)
        }

        let info = try root["info"].map { value in
            try sanitized(value)
        } ?? [
            "title": "App Store Connect API",
            "version": "trimmed",
        ]
        let servers = try root["servers"].map { value in
            try sanitized(value)
        } ?? [
            ["url": "https://api.appstoreconnect.apple.com"],
        ]
        var output: [String: Any] = [
            "openapi": root["openapi"] ?? "3.0.1",
            "info": info,
            "servers": servers,
            "paths": trimmedPaths,
            "components": trimmedComponents,
        ]

        if let security = root["security"] {
            output["security"] = try sanitized(security)
        }

        let outputData = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try outputData.write(to: outputURL)

        return OpenAPITrimResult(
            pathCount: trimmedPaths.count,
            componentReferenceCount: referencedComponents.count
        )
    }

    private func sanitized(_ value: Any, depth: Int = 0) throws -> Any {
        guard depth <= maximumNestingDepth else {
            throw TrimmerError.nestingDepthExceeded(maximum: maximumNestingDepth)
        }

        if var dictionary = value as? [String: Any] {
            if let enumValues = dictionary["enum"] as? [Any], enumValues.isEmpty {
                dictionary.removeValue(forKey: "enum")
            }

            dictionary.removeValue(forKey: "deprecated")

            for (key, nestedValue) in dictionary {
                dictionary[key] = try sanitized(nestedValue, depth: depth + 1)
            }

            return dictionary
        }

        if let array = value as? [Any] {
            return try array.map { element in
                try sanitized(element, depth: depth + 1)
            }
        }

        return value
    }
}

private struct ComponentReference: Hashable {
    var section: String
    var name: String

    var ref: String {
        "#/components/\(section)/\(name)"
    }

    init?(ref: String) {
        let prefix = "#/components/"
        guard ref.hasPrefix(prefix) else {
            return nil
        }

        let path = String(ref.dropFirst(prefix.count)).split(separator: "/", maxSplits: 1)
        guard path.count == 2 else {
            return nil
        }

        section = String(path[0])
        name = String(path[1])
    }
}

package enum TrimmerError: Error, Equatable, CustomStringConvertible {
    case invalidOpenAPIDocument
    case missingComponent(String)
    case nestingDepthExceeded(maximum: Int)

    package var description: String {
        switch self {
        case .invalidOpenAPIDocument:
            "Invalid OpenAPI document."
        case let .missingComponent(ref):
            "Missing component referenced by trimmed OpenAPI document: \(ref)."
        case let .nestingDepthExceeded(maximum):
            "The OpenAPI document exceeds the maximum nesting depth of \(maximum)."
        }
    }
}
