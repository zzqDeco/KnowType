import Foundation

public enum CandidateAnchorPolicy {
    public static func characterRange(for selectedRange: NSRange) -> NSRange? {
        guard isKnown(selectedRange) else {
            return nil
        }
        return NSRange(location: selectedRange.location, length: 0)
    }

    public static func characterRange(selectedRange: NSRange, markedRange: NSRange?) -> NSRange {
        characterRanges(selectedRange: selectedRange, markedRange: markedRange).first
            ?? NSRange(location: 0, length: 0)
    }

    public static func characterRanges(selectedRange: NSRange, markedRange: NSRange?) -> [NSRange] {
        var ranges: [NSRange] = []
        if isKnown(selectedRange) {
            ranges.append(NSRange(location: selectedRange.location, length: 0))
        }
        if let markedRange, isKnown(markedRange) {
            let markedEnd = NSRange(location: markedRange.location + markedRange.length, length: 0)
            if !ranges.contains(markedEnd) {
                ranges.insert(markedEnd, at: 0)
            }
        }
        if ranges.isEmpty {
            ranges.append(NSRange(location: 0, length: 0))
        }
        return ranges
    }

    private static func isKnown(_ range: NSRange) -> Bool {
        range.location != NSNotFound && range.length != NSNotFound
    }
}
