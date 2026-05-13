import Foundation

public enum CandidateAnchorPolicy {
    public static func characterRange(for selectedRange: NSRange) -> NSRange? {
        guard selectedRange.location != NSNotFound else {
            return nil
        }
        return NSRange(location: selectedRange.location, length: 0)
    }
}
