import Foundation
import OpenAPIGenerationSupport
import Testing

@Test
func generatedSourcesInstallSplitTypesAndRemoveObsoleteFragments() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {
        try? FileManager.default.removeItem(at: directory)
    }
    let source = directory.appendingPathComponent("source")
    let output = directory.appendingPathComponent("output")
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let files = ["Client.swift", "Types.swift", "Types+Components.swift", "Types+Components+Schemas.swift", "Types+Operations.swift"]
    for name in files {
        try Data(name.utf8).write(to: source.appendingPathComponent(name))
    }
    try Data("private spec".utf8).write(to: source.appendingPathComponent("openapi.json"))
    try Data().write(to: output.appendingPathComponent("Server.swift"))
    try Data().write(to: output.appendingPathComponent("README.md"))

    let installer = GeneratedSourceInstaller()
    try installer.install(from: source, to: output)
    #expect(Set(try FileManager.default.contentsOfDirectory(atPath: output.path)) == Set(files + ["README.md"]))
    for name in files {
        #expect(try Data(contentsOf: output.appendingPathComponent(name)) == Data(name.utf8))
    }

    for name in files where name.hasPrefix("Types+") {
        try FileManager.default.removeItem(at: source.appendingPathComponent(name))
    }
    try Data("monolithic types".utf8).write(to: source.appendingPathComponent("Types.swift"))
    try installer.install(from: source, to: output)
    #expect(Set(try FileManager.default.contentsOfDirectory(atPath: output.path)) == ["Client.swift", "Types.swift", "README.md"])
    #expect(try Data(contentsOf: output.appendingPathComponent("Types.swift")) == Data("monolithic types".utf8))
}

@Test(arguments: ["Client.swift", "Types.swift"])
func incompleteGenerationPreservesInstalledSources(missingFile: String) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {
        try? FileManager.default.removeItem(at: directory)
    }
    let source = directory.appendingPathComponent("source")
    let output = directory.appendingPathComponent("output")
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    for name in ["Client.swift", "Types.swift"] {
        try Data("original".utf8).write(to: output.appendingPathComponent(name))
        if name != missingFile {
            try Data("replacement".utf8).write(to: source.appendingPathComponent(name))
        }
    }
    #expect(throws: CocoaError.self) {
        try GeneratedSourceInstaller().install(from: source, to: output)
    }
    for name in ["Client.swift", "Types.swift"] {
        #expect(try Data(contentsOf: output.appendingPathComponent(name)) == Data("original".utf8))
    }
}
