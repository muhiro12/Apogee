#!/usr/bin/env swift

import Foundation

let selectedOperationIDs: Set<String> = [
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

let methodNames: Set<String> = ["get", "post", "patch", "delete"]
guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write(
        Data("Usage: trim-app-store-connect-openapi.swift <source-openapi-json> <output-openapi-json>\n".utf8)
    )
    exit(64)
}

let sourcePath = CommandLine.arguments[1]
let outputPath = CommandLine.arguments[2]

let sourceURL = URL(fileURLWithPath: sourcePath)
let outputURL = URL(fileURLWithPath: outputPath)
let sourceData = try Data(contentsOf: sourceURL)

guard
    let root = try JSONSerialization.jsonObject(with: sourceData) as? [String: Any],
    let sourcePaths = root["paths"] as? [String: Any],
    let sourceComponents = root["components"] as? [String: Any]
else {
    throw TrimmerError.invalidOpenAPIDocument(sourcePath)
}

var trimmedPaths: [String: Any] = [:]
var referencedComponents: Set<ComponentReference> = []
var queuedComponents: [ComponentReference] = []

func enqueueReferences(in value: Any) {
    if let dictionary = value as? [String: Any] {
        if let ref = dictionary["$ref"] as? String,
           let componentReference = ComponentReference(ref: ref),
           !referencedComponents.contains(componentReference) {
            referencedComponents.insert(componentReference)
            queuedComponents.append(componentReference)
        }

        for nestedValue in dictionary.values {
            enqueueReferences(in: nestedValue)
        }
    } else if let array = value as? [Any] {
        for element in array {
            enqueueReferences(in: element)
        }
    }
}

for (path, rawPathItem) in sourcePaths {
    guard let pathItem = rawPathItem as? [String: Any] else {
        continue
    }

    var trimmedPathItem: [String: Any] = [:]

    if let parameters = pathItem["parameters"] {
        let sanitizedParameters = sanitized(parameters)
        trimmedPathItem["parameters"] = sanitizedParameters
        enqueueReferences(in: sanitizedParameters)
    }

    for (key, value) in pathItem where methodNames.contains(key) {
        guard
            let operation = value as? [String: Any],
            let operationID = operation["operationId"] as? String,
            selectedOperationIDs.contains(operationID)
        else {
            continue
        }

        let sanitizedOperation = sanitized(operation)
        trimmedPathItem[key] = sanitizedOperation
        enqueueReferences(in: sanitizedOperation)
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
    let sanitizedComponentValue = sanitized(componentValue)
    outputGroup[componentReference.name] = sanitizedComponentValue
    trimmedComponents[componentReference.section] = outputGroup
    enqueueReferences(in: sanitizedComponentValue)
}

if let securitySchemes = sourceComponents["securitySchemes"] {
    trimmedComponents["securitySchemes"] = securitySchemes
}

var output: [String: Any] = [
    "openapi": root["openapi"] ?? "3.0.1",
    "info": root["info"] ?? [
        "title": "App Store Connect API",
        "version": "trimmed",
    ],
    "servers": root["servers"] ?? [
        ["url": "https://api.appstoreconnect.apple.com"],
    ],
    "paths": trimmedPaths,
    "components": trimmedComponents,
]

if let security = root["security"] {
    output["security"] = security
}

let outputData = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try outputData.write(to: outputURL)

print("Wrote \(outputPath) with \(trimmedPaths.count) paths and \(referencedComponents.count) referenced components.")

func sanitized(_ value: Any) -> Any {
    if var dictionary = value as? [String: Any] {
        if let enumValues = dictionary["enum"] as? [Any], enumValues.isEmpty {
            dictionary.removeValue(forKey: "enum")
        }

        dictionary.removeValue(forKey: "deprecated")

        for (key, nestedValue) in dictionary {
            dictionary[key] = sanitized(nestedValue)
        }

        return dictionary
    }

    if let array = value as? [Any] {
        return array.map(sanitized)
    }

    return value
}

struct ComponentReference: Hashable {
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

enum TrimmerError: Error, CustomStringConvertible {
    case invalidOpenAPIDocument(String)
    case missingComponent(String)

    var description: String {
        switch self {
        case let .invalidOpenAPIDocument(path):
            "Invalid OpenAPI document at \(path)."
        case let .missingComponent(ref):
            "Missing component referenced by trimmed OpenAPI document: \(ref)."
        }
    }
}
