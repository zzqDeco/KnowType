import Foundation

public enum CandidateAnchorPolicy {
    public static let currentInsertionPointFallbackRange = NSRange(location: NSNotFound, length: 0)
    public static let maximumLineHeightBacktrack = 80

    public static func characterRange(for selectedRange: NSRange) -> NSRange? {
        guard isKnown(selectedRange) else {
            return nil
        }
        return NSRange(location: selectedRange.location + selectedRange.length, length: 0)
    }

    public static func characterRange(selectedRange: NSRange, markedRange: NSRange?) -> NSRange {
        characterRanges(selectedRange: selectedRange, markedRange: markedRange).first
            ?? NSRange(location: 0, length: 0)
    }

    public static func characterRanges(selectedRange: NSRange, markedRange: NSRange?) -> [NSRange] {
        characterRangeRequests(selectedRange: selectedRange, markedRange: markedRange).map(\.range)
    }

    public static func characterRangeRequests(
        selectedRange: NSRange,
        markedRange: NSRange?
    ) -> [CandidateAnchorCharacterRange] {
        var ranges: [NSRange] = []
        if isKnown(selectedRange) {
            appendUnique(
                NSRange(location: selectedRange.location + selectedRange.length, length: 0),
                to: &ranges
            )
        }
        if let markedRange, isKnown(markedRange) {
            let markedEnd = NSRange(location: markedRange.location + markedRange.length, length: 0)
            insertUnique(markedEnd, at: 0, in: &ranges)
            appendUnique(NSRange(location: markedRange.location, length: 0), to: &ranges)
        }
        if isKnown(selectedRange) {
            appendUnique(NSRange(location: selectedRange.location, length: 0), to: &ranges)
        }
        if ranges.isEmpty {
            ranges.append(NSRange(location: 0, length: 0))
        }
        return ranges.map { range in
            CandidateAnchorCharacterRange(
                range: range,
                source: source(for: range, selectedRange: selectedRange, markedRange: markedRange)
            )
        }
    }

    public static func lineHeightCharacterIndexes(
        selectedRange: NSRange,
        markedRange: NSRange?,
        maximumBacktrack: Int = maximumLineHeightBacktrack
    ) -> [Int] {
        var indexes: [Int] = []
        let startIndexes = characterRanges(selectedRange: selectedRange, markedRange: markedRange)
            .map(\.location)
            .filter { $0 != NSNotFound }

        for startIndex in startIndexes {
            let lowerBound = max(0, startIndex - max(0, maximumBacktrack))
            var index = startIndex
            while index >= lowerBound {
                appendUnique(index, to: &indexes)
                if index == 0 {
                    break
                }
                index -= 1
            }
        }
        appendUnique(0, to: &indexes)
        return indexes
    }

    private static func source(
        for range: NSRange,
        selectedRange: NSRange,
        markedRange: NSRange?
    ) -> CandidateAnchorSource {
        if let markedRange,
           isKnown(markedRange),
           range.location == markedRange.location + markedRange.length {
            return .firstRectMarkedEnd
        }
        if isKnown(selectedRange),
           range.location == selectedRange.location + selectedRange.length {
            return .firstRectSelectedEnd
        }
        if let markedRange,
           isKnown(markedRange),
           range.location == markedRange.location {
            return .firstRectMarkedStart
        }
        return .firstRectSelectedStart
    }

    private static func appendUnique(_ range: NSRange, to ranges: inout [NSRange]) {
        if !ranges.contains(range) {
            ranges.append(range)
        }
    }

    private static func insertUnique(_ range: NSRange, at index: Int, in ranges: inout [NSRange]) {
        if !ranges.contains(range) {
            ranges.insert(range, at: index)
        }
    }

    private static func appendUnique(_ index: Int, to indexes: inout [Int]) {
        if !indexes.contains(index) {
            indexes.append(index)
        }
    }

    private static func isKnown(_ range: NSRange) -> Bool {
        range.location != NSNotFound && range.length != NSNotFound
    }
}
