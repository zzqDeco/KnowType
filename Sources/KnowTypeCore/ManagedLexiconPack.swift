import CryptoKit
import Foundation

public enum ManagedLexiconPackFormat: String, Codable, Sendable, Equatable {
    case rimeDictYAML
}

public struct ManagedLexiconPack: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var displayName: String
    public var sourceURL: URL
    public var sourceVersion: String
    public var sourceSHA256: String
    public var licenseName: String
    public var licenseURL: URL
    public var outputFileName: String
    public var metadataFileName: String
    public var format: ManagedLexiconPackFormat

    public init(
        id: String,
        displayName: String,
        sourceURL: URL,
        sourceVersion: String,
        sourceSHA256: String,
        licenseName: String,
        licenseURL: URL,
        outputFileName: String,
        metadataFileName: String,
        format: ManagedLexiconPackFormat
    ) {
        self.id = id
        self.displayName = displayName
        self.sourceURL = sourceURL
        self.sourceVersion = sourceVersion
        self.sourceSHA256 = sourceSHA256
        self.licenseName = licenseName
        self.licenseURL = licenseURL
        self.outputFileName = outputFileName
        self.metadataFileName = metadataFileName
        self.format = format
    }
}

public enum ManagedLexiconPacks {
    public static let rimePinyinSimplified = ManagedLexiconPack(
        id: "rime-pinyin-simp",
        displayName: "Rime Pinyin Simplified",
        sourceURL: URL(
            string: "https://raw.githubusercontent.com/rime/rime-pinyin-simp/0c6861ef7420ee780270ca6d993d18d4101049d0/pinyin_simp.dict.yaml"
        )!,
        sourceVersion: "0c6861ef7420ee780270ca6d993d18d4101049d0",
        sourceSHA256: "e341598343a0f0f2035bb1aafc34a7f3bb7887deeecb3f60796262aaa2983e6b",
        licenseName: "Apache-2.0",
        licenseURL: URL(
            string: "https://github.com/rime/rime-pinyin-simp/blob/0c6861ef7420ee780270ca6d993d18d4101049d0/LICENSE"
        )!,
        outputFileName: "rime-pinyin-simp.tsv",
        metadataFileName: "rime-pinyin-simp.metadata.json",
        format: .rimeDictYAML
    )

    public static let recommended = rimePinyinSimplified

    public static let all: [ManagedLexiconPack] = [
        rimePinyinSimplified
    ]

    public static func pack(id: String) -> ManagedLexiconPack? {
        all.first { $0.id == id }
    }
}

public struct InstalledLexiconPackMetadata: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var displayName: String
    public var sourceURL: URL
    public var sourceVersion: String
    public var sourceSHA256: String
    public var outputFileName: String
    public var entryCount: Int
    public var licenseName: String
    public var licenseURL: URL
    public var installedAt: Date

    public init(
        id: String,
        displayName: String,
        sourceURL: URL,
        sourceVersion: String,
        sourceSHA256: String,
        outputFileName: String,
        entryCount: Int,
        licenseName: String,
        licenseURL: URL,
        installedAt: Date
    ) {
        self.id = id
        self.displayName = displayName
        self.sourceURL = sourceURL
        self.sourceVersion = sourceVersion
        self.sourceSHA256 = sourceSHA256
        self.outputFileName = outputFileName
        self.entryCount = entryCount
        self.licenseName = licenseName
        self.licenseURL = licenseURL
        self.installedAt = installedAt
    }
}

public struct RimeDictionaryConversionResult: Sendable, Equatable {
    public var tsvData: Data
    public var entryCount: Int
    public var skippedLineCount: Int

    public init(tsvData: Data, entryCount: Int, skippedLineCount: Int) {
        self.tsvData = tsvData
        self.entryCount = entryCount
        self.skippedLineCount = skippedLineCount
    }
}

public enum RimeDictionaryConverterError: Error, Sendable, Equatable, LocalizedError {
    case invalidUTF8
    case missingDataSection
    case noEntries

    public var errorDescription: String? {
        switch self {
        case .invalidUTF8:
            return "Rime dictionary is not valid UTF-8."
        case .missingDataSection:
            return "Rime dictionary data section marker was not found."
        case .noEntries:
            return "Rime dictionary did not contain any valid entries."
        }
    }
}

public struct RimeDictionaryConverter: Sendable {
    private struct Row: Equatable {
        var text: String
        var pinyin: String
        var weight: Double?
    }

    public init() {}

    public func convert(_ data: Data) throws -> RimeDictionaryConversionResult {
        guard let source = String(data: data, encoding: .utf8) else {
            throw RimeDictionaryConverterError.invalidUTF8
        }

        var rows: [Row] = []
        var skipped = 0
        var inDataSection = false

        for rawLine in source.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if !inDataSection {
                if trimmed == "..." {
                    inDataSection = true
                }
                continue
            }
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }

            let columns = rawLine.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard columns.count >= 2 else {
                skipped += 1
                continue
            }

            let text = columns[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let pinyin = columns[1]
                .split(whereSeparator: \.isWhitespace)
                .map(String.init)
                .joined(separator: " ")
            guard !text.isEmpty, !pinyin.isEmpty else {
                skipped += 1
                continue
            }

            let weight = columns.count >= 3
                ? Double(columns[2].trimmingCharacters(in: .whitespacesAndNewlines))
                : nil
            rows.append(Row(text: text, pinyin: pinyin, weight: weight))
        }

        guard inDataSection else {
            throw RimeDictionaryConverterError.missingDataSection
        }
        guard !rows.isEmpty else {
            throw RimeDictionaryConverterError.noEntries
        }

        let maxWeight = rows.compactMap(\.weight).max() ?? 0
        var outputRows = [
            "# Generated from Rime dictionary by KnowType.",
            "# Format: pinyin<TAB>text<TAB>confidence"
        ]
        outputRows.reserveCapacity(rows.count + outputRows.count)
        for row in rows {
            outputRows.append(
                "\(row.pinyin)\t\(row.text)\t\(Self.confidence(weight: row.weight, maxWeight: maxWeight, text: row.text))"
            )
        }
        let output = outputRows.joined(separator: "\n") + "\n"

        return RimeDictionaryConversionResult(
            tsvData: Data(output.utf8),
            entryCount: rows.count,
            skippedLineCount: skipped
        )
    }

    private static func confidence(weight: Double?, maxWeight: Double, text: String) -> String {
        let value: Double
        if let weight, weight.isFinite, weight > 0, maxWeight > 0 {
            let normalized = log10(weight + 1) / log10(maxWeight + 1)
            var weighted = 0.50 + normalized * 0.495
            if text.count == 1, weight < maxWeight * 0.001 {
                weighted -= 0.08
            }
            value = min(0.995, max(0.50, weighted))
        } else {
            value = text.count == 1 ? 0.55 : 0.72
        }
        let scaled = Int((value * 1000).rounded())
        let whole = scaled / 1000
        let fraction = scaled % 1000
        let fractionText = String(fraction)
        return "\(whole).\(String(repeating: "0", count: 3 - fractionText.count))\(fractionText)"
    }
}

public enum ManagedLexiconPackInstallerError: Error, Sendable, Equatable, LocalizedError {
    case unknownPack(String)
    case checksumMismatch(expected: String, actual: String)
    case outputAlreadyExists(String)
    case unsupportedFormat(ManagedLexiconPackFormat)
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .unknownPack(id):
            return "Unknown lexicon pack: \(id)"
        case let .checksumMismatch(expected, actual):
            return "Lexicon pack checksum mismatch. Expected \(expected), got \(actual)."
        case let .outputAlreadyExists(path):
            return "Lexicon pack output already exists: \(path)"
        case let .unsupportedFormat(format):
            return "Lexicon pack format is unsupported: \(format.rawValue)"
        case let .writeFailed(reason):
            return "Lexicon pack could not be written: \(reason)"
        }
    }
}

public struct ManagedLexiconPackInstaller {
    public typealias DataProvider = @Sendable (URL) async throws -> Data

    private let dataProvider: DataProvider
    private let fileManager: FileManager
    private let dateProvider: () -> Date

    public init(
        dataProvider: @escaping DataProvider = ManagedLexiconPackInstaller.defaultDataProvider,
        fileManager: FileManager = .default,
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.dataProvider = dataProvider
        self.fileManager = fileManager
        self.dateProvider = dateProvider
    }

    public func installRecommended(
        destinationDirectory: URL = TraditionalInputLexiconDirectoryResolver.applicationSupportLexiconDirectory(),
        force: Bool = false
    ) async throws -> InstalledLexiconPackMetadata {
        try await install(
            ManagedLexiconPacks.recommended,
            destinationDirectory: destinationDirectory,
            force: force
        )
    }

    public func install(
        _ pack: ManagedLexiconPack,
        destinationDirectory: URL = TraditionalInputLexiconDirectoryResolver.applicationSupportLexiconDirectory(),
        force: Bool = false
    ) async throws -> InstalledLexiconPackMetadata {
        let sourceData = try await dataProvider(pack.sourceURL)
        let actualChecksum = Self.sha256Hex(sourceData)
        guard actualChecksum == pack.sourceSHA256 else {
            throw ManagedLexiconPackInstallerError.checksumMismatch(
                expected: pack.sourceSHA256,
                actual: actualChecksum
            )
        }

        let conversion: RimeDictionaryConversionResult
        switch pack.format {
        case .rimeDictYAML:
            conversion = try RimeDictionaryConverter().convert(sourceData)
        }

        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let outputURL = destinationDirectory.appendingPathComponent(pack.outputFileName)
        if fileManager.fileExists(atPath: outputURL.path), !force {
            throw ManagedLexiconPackInstallerError.outputAlreadyExists(outputURL.path)
        }

        let metadata = InstalledLexiconPackMetadata(
            id: pack.id,
            displayName: pack.displayName,
            sourceURL: pack.sourceURL,
            sourceVersion: pack.sourceVersion,
            sourceSHA256: actualChecksum,
            outputFileName: pack.outputFileName,
            entryCount: conversion.entryCount,
            licenseName: pack.licenseName,
            licenseURL: pack.licenseURL,
            installedAt: dateProvider()
        )
        let metadataURL = destinationDirectory.appendingPathComponent(pack.metadataFileName)
        let metadataEncoder = JSONEncoder()
        metadataEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        metadataEncoder.dateEncodingStrategy = .iso8601

        do {
            try Self.writeAtomically(conversion.tsvData, to: outputURL, fileManager: fileManager)
            try Self.writeAtomically(try metadataEncoder.encode(metadata), to: metadataURL, fileManager: fileManager)
        } catch let error as ManagedLexiconPackInstallerError {
            throw error
        } catch {
            throw ManagedLexiconPackInstallerError.writeFailed(error.localizedDescription)
        }

        return metadata
    }

    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { byte in
                let text = String(byte, radix: 16)
                return byte < 16 ? "0\(text)" : text
            }
            .joined()
    }

    public static func defaultDataProvider(url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        if let response = response as? HTTPURLResponse,
           !(200...299).contains(response.statusCode) {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private static func writeAtomically(
        _ data: Data,
        to url: URL,
        fileManager: FileManager
    ) throws {
        let directory = url.deletingLastPathComponent()
        let temporaryURL = directory.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        do {
            try data.write(to: temporaryURL, options: [.atomic])
            if fileManager.fileExists(atPath: url.path) {
                _ = try fileManager.replaceItemAt(url, withItemAt: temporaryURL)
            } else {
                try fileManager.moveItem(at: temporaryURL, to: url)
            }
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }
}
