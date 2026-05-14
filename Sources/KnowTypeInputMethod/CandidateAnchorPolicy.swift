import Foundation

public enum CandidateAnchorPolicy {
    public static let currentInsertionPointFallbackRange = NSRange(location: NSNotFound, length: 0)

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
        var ranges: [NSRange] = []
        if let markedRange, isKnown(markedRange) {
            let markedEnd = NSRange(location: markedRange.location + markedRange.length, length: 0)
            appendUnique(markedEnd, to: &ranges)
            appendUnique(NSRange(location: markedRange.location, length: 0), to: &ranges)
        }
        if isKnown(selectedRange) {
            appendUnique(NSRange(location: selectedRange.location + selectedRange.length, length: 0), to: &ranges)
            appendUnique(NSRange(location: selectedRange.location, length: 0), to: &ranges)
        }
        if ranges.isEmpty {
            ranges.append(NSRange(location: 0, length: 0))
        }
        return ranges
    }

    public static func lineHeightCharacterIndexes(selectedRange: NSRange, markedRange: NSRange?) -> [Int] {
        characterRanges(selectedRange: selectedRange, markedRange: markedRange)
            .map(\.location)
            .filter { $0 != NSNotFound }
    }

    private static func appendUnique(_ range: NSRange, to ranges: inout [NSRange]) {
        if !ranges.contains(range) {
            ranges.append(range)
        }
    }

    private static func isKnown(_ range: NSRange) -> Bool {
        range.location != NSNotFound && range.length != NSNotFound
    }
}
