#!/usr/bin/env swift

import Foundation

private let catalogPath = "Splitty/Splitty/Localization/Localizable.xcstrings"
private let checking = CommandLine.arguments.dropFirst().contains("--check")

do {
    let url = URL(fileURLWithPath: catalogPath)
    let original = try Data(contentsOf: url)
    let object = try JSONSerialization.jsonObject(with: original)
    var formatted = try JSONSerialization.data(
        withJSONObject: object,
        options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    )
    formatted.append(0x0A)

    if checking {
        guard original == formatted else {
            FileHandle.standardError.write(
                Data("\(catalogPath) is not canonically formatted. Run scripts/format-xcstrings.swift.\n".utf8)
            )
            exit(EXIT_FAILURE)
        }
    } else {
        try formatted.write(to: url, options: .atomic)
    }
} catch {
    FileHandle.standardError.write(Data("Could not format \(catalogPath): \(error)\n".utf8))
    exit(EXIT_FAILURE)
}
