import Foundation
import KnowTypeCore

public struct CompositionBuffer: Sendable, Equatable {
    public private(set) var rawInput: String
    public private(set) var resolvedSegments: [CandidateSegment]

    public init(rawInput: String = "", resolvedSegments: [CandidateSegment] = []) {
        self.rawInput = rawInput
        self.resolvedSegments = Self.normalized(segments: resolvedSegments, rawLength: rawInput.count)
    }

    public var rawRange: KnowTypeCore.TextRange {
        KnowTypeCore.TextRange(start: 0, length: rawInput.count)
    }

    public var hasResolvedSegments: Bool {
        !resolvedSegments.isEmpty
    }

    public var displayText: String {
        guard !rawInput.isEmpty else {
            return ""
        }
        var output = ""
        var cursor = 0
        for segment in resolvedSegments.sorted(by: { $0.rawRange.start < $1.rawRange.start }) {
            if cursor < segment.rawRange.start {
                output += substring(KnowTypeCore.TextRange(start: cursor, length: segment.rawRange.start - cursor))
            }
            output += segment.text
            cursor = max(cursor, segment.rawRange.end)
        }
        if cursor < rawInput.count {
            output += substring(KnowTypeCore.TextRange(start: cursor, length: rawInput.count - cursor))
        }
        return output
    }

    public var commitText: String {
        if isFullyResolved {
            return resolvedSegments
                .sorted { $0.rawRange.start < $1.rawRange.start }
                .map(\.text)
                .joined()
        }
        return displayText
    }

    public var isFullyResolved: Bool {
        guard !rawInput.isEmpty else {
            return false
        }
        let sorted = resolvedSegments.sorted { $0.rawRange.start < $1.rawRange.start }
        var cursor = 0
        for segment in sorted {
            if cursor < segment.rawRange.start,
               containsNonWhitespace(in: KnowTypeCore.TextRange(start: cursor, length: segment.rawRange.start - cursor)) {
                return false
            }
            cursor = max(cursor, segment.rawRange.end)
        }
        if cursor < rawInput.count,
           containsNonWhitespace(in: KnowTypeCore.TextRange(start: cursor, length: rawInput.count - cursor)) {
            return false
        }
        return !resolvedSegments.isEmpty
    }

    public var activeRange: KnowTypeCore.TextRange? {
        guard !rawInput.isEmpty else {
            return nil
        }
        let sorted = resolvedSegments.sorted { $0.rawRange.start < $1.rawRange.start }
        var cursor = 0
        for segment in sorted {
            if let range = firstNonWhitespaceRange(from: cursor, to: segment.rawRange.start) {
                return KnowTypeCore.TextRange(start: range.start, length: rawInput.count - range.start)
            }
            cursor = max(cursor, segment.rawRange.end)
        }
        if let range = firstNonWhitespaceRange(from: cursor, to: rawInput.count) {
            return KnowTypeCore.TextRange(start: range.start, length: rawInput.count - range.start)
        }
        return nil
    }

    public mutating func updateRawInput(_ newRawInput: String) {
        rawInput = newRawInput
        resolvedSegments = Self.normalized(segments: resolvedSegments, rawLength: newRawInput.count)
    }

    @discardableResult
    public mutating func apply(_ candidate: CorrectionCandidate) -> Bool {
        let candidateSegments = candidate.segments.isEmpty
            ? fallbackSegments(for: candidate)
            : candidate.segments
        guard !candidateSegments.isEmpty,
              candidateSegments.allSatisfy({ rawRange.contains($0.rawRange) }),
              !candidateSegments.contains(where: overlapsExistingSegment) else {
            return false
        }
        resolvedSegments.append(contentsOf: candidateSegments)
        resolvedSegments = Self.normalized(segments: resolvedSegments, rawLength: rawInput.count)
        return true
    }

    @discardableResult
    public mutating func undoLastResolvedSegment() -> Bool {
        guard !resolvedSegments.isEmpty else {
            return false
        }
        resolvedSegments.removeLast()
        return true
    }

    public func substring(_ range: KnowTypeCore.TextRange) -> String {
        guard rawRange.contains(range),
              let lower = rawInput.index(rawInput.startIndex, offsetBy: range.start, limitedBy: rawInput.endIndex),
              let upper = rawInput.index(lower, offsetBy: range.length, limitedBy: rawInput.endIndex) else {
            return ""
        }
        return String(rawInput[lower..<upper])
    }

    private func fallbackSegments(for candidate: CorrectionCandidate) -> [CandidateSegment] {
        guard let range = candidate.rawRange ?? activeRange else {
            return []
        }
        return [
            CandidateSegment(
                rawRange: range,
                tokenRange: KnowTypeCore.TextRange(start: 0, length: 0),
                reading: substring(range),
                text: candidate.text
            )
        ]
    }

    private func overlapsExistingSegment(_ segment: CandidateSegment) -> Bool {
        resolvedSegments.contains { existing in
            existing.rawRange.intersects(segment.rawRange)
        }
    }

    private func containsNonWhitespace(in range: KnowTypeCore.TextRange) -> Bool {
        substring(range).contains { !$0.isWhitespace }
    }

    private func firstNonWhitespaceRange(from start: Int, to end: Int) -> KnowTypeCore.TextRange? {
        guard start < end else {
            return nil
        }
        var offset = start
        for character in substring(KnowTypeCore.TextRange(start: start, length: end - start)) {
            if !character.isWhitespace {
                return KnowTypeCore.TextRange(start: offset, length: 1)
            }
            offset += 1
        }
        return nil
    }

    private static func normalized(segments: [CandidateSegment], rawLength: Int) -> [CandidateSegment] {
        var accepted: [CandidateSegment] = []
        for segment in segments.sorted(by: { lhs, rhs in
            if lhs.rawRange.start == rhs.rawRange.start {
                return lhs.rawRange.length < rhs.rawRange.length
            }
            return lhs.rawRange.start < rhs.rawRange.start
        }) {
            guard segment.rawRange.start >= 0,
                  segment.rawRange.end <= rawLength,
                  !accepted.contains(where: { $0.rawRange.intersects(segment.rawRange) }) else {
                continue
            }
            accepted.append(segment)
        }
        return accepted
    }
}
