import Foundation

public enum TraditionalInputLexiconResourceFormat: String, Sendable, Equatable {
    case json
    case tsv
}

public enum TraditionalInputLexiconResourceError: Error, Sendable, Equatable, LocalizedError {
    case invalidUTF8
    case invalidJSON(String)
    case invalidTSVLine(line: Int, reason: String)
    case invalidEntry(index: Int, reason: String)

    public var errorDescription: String? {
        switch self {
        case .invalidUTF8:
            return "Lexicon resource is not valid UTF-8."
        case let .invalidJSON(reason):
            return "Lexicon JSON is invalid: \(reason)"
        case let .invalidTSVLine(line, reason):
            return "Lexicon TSV line \(line) is invalid: \(reason)"
        case let .invalidEntry(index, reason):
            return "Lexicon entry \(index) is invalid: \(reason)"
        }
    }
}

public struct TraditionalInputLexiconResourceLoader: Sendable {
    public init() {}

    public func load(
        _ data: Data,
        format: TraditionalInputLexiconResourceFormat
    ) throws -> [TraditionalInputLexiconEntry] {
        switch format {
        case .json:
            return try loadJSON(data)
        case .tsv:
            return try loadTSV(data)
        }
    }

    public func loadJSON(_ data: Data) throws -> [TraditionalInputLexiconEntry] {
        do {
            let entries = try JSONDecoder().decode([TraditionalInputLexiconEntry].self, from: data)
            return try normalized(entries)
        } catch let error as TraditionalInputLexiconResourceError {
            throw error
        } catch {
            throw TraditionalInputLexiconResourceError.invalidJSON(error.localizedDescription)
        }
    }

    public func loadTSV(_ data: Data) throws -> [TraditionalInputLexiconEntry] {
        guard let text = String(data: data, encoding: .utf8) else {
            throw TraditionalInputLexiconResourceError.invalidUTF8
        }

        var entries: [TraditionalInputLexiconEntry] = []
        for (offset, rawLine) in text.components(separatedBy: .newlines).enumerated() {
            let lineNumber = offset + 1
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") {
                continue
            }

            let columns = rawLine.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard columns.count == 2 || columns.count == 3 else {
                throw TraditionalInputLexiconResourceError.invalidTSVLine(
                    line: lineNumber,
                    reason: "expected pinyin, text, and optional confidence columns"
                )
            }

            let confidence: Double
            if columns.count == 3 {
                guard let parsed = Double(columns[2].trimmingCharacters(in: .whitespaces)) else {
                    throw TraditionalInputLexiconResourceError.invalidTSVLine(
                        line: lineNumber,
                        reason: "confidence must be a number"
                    )
                }
                confidence = parsed
            } else {
                confidence = 0.72
            }

            entries.append(
                TraditionalInputLexiconEntry(
                    pinyin: columns[0].split(whereSeparator: \.isWhitespace).map(String.init),
                    outputs: [
                        TraditionalInputLexiconOutput(
                            text: columns[1],
                            confidence: confidence
                        )
                    ]
                )
            )
        }

        return try normalized(entries)
    }

    private func normalized(_ entries: [TraditionalInputLexiconEntry]) throws -> [TraditionalInputLexiconEntry] {
        try entries.enumerated().map { index, entry in
            let pinyin = entry.pinyin
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
            guard !pinyin.isEmpty else {
                throw TraditionalInputLexiconResourceError.invalidEntry(
                    index: index,
                    reason: "pinyin must contain at least one token"
                )
            }

            let outputs = try entry.outputs.enumerated().map { outputIndex, output in
                let text = output.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else {
                    throw TraditionalInputLexiconResourceError.invalidEntry(
                        index: index,
                        reason: "output \(outputIndex) text must not be empty"
                    )
                }
                guard output.confidence.isFinite,
                      (0...1).contains(output.confidence) else {
                    throw TraditionalInputLexiconResourceError.invalidEntry(
                        index: index,
                        reason: "output \(outputIndex) confidence must be between 0 and 1"
                    )
                }
                return TraditionalInputLexiconOutput(text: text, confidence: output.confidence)
            }
            guard !outputs.isEmpty else {
                throw TraditionalInputLexiconResourceError.invalidEntry(
                    index: index,
                    reason: "outputs must not be empty"
                )
            }

            return TraditionalInputLexiconEntry(pinyin: pinyin, outputs: outputs)
        }
    }
}
