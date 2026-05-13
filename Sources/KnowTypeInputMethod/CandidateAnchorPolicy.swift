import Foundation

public enum CandidateAnchorPolicy {
    public static func characterRange(for selectedRange: NSRange) -> NSRange? {
        guard isKnown(selectedRange) else {
            return nil
        }
        return NSRange(location: selectedRange.location, length: 0)
    }

    public static func characterRange(selectedRange: NSRange, markedRange: NSRange?) -> NSRange {
        if isKnown(selectedRange) {
            return NSRange(location: selectedRange.location, length: 0)
        }
        if let markedRange, isKnown(markedRange) {
            return NSRange(location: markedRange.location + markedRange.length, length: 0)
        }
        return NSRange(location: 0, length: 0)
    }

    private static func isKnown(_ range: NSRange) -> Bool {
        range.location != NSNotFound && range.length != NSNotFound
    }
}
