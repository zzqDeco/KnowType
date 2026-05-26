import Foundation

public struct AIRecommendationTriggerPolicy: Sendable, Equatable {
    public enum RejectionReason: String, Sendable, Equatable {
        case rawTooShort = "raw_too_short"
        case prefixTooShort = "prefix_too_short"
    }

    public struct Decision: Sendable, Equatable {
        public var isEligible: Bool
        public var rejectionReason: RejectionReason?

        public static let eligible = Decision(isEligible: true, rejectionReason: nil)

        public static func rejected(_ reason: RejectionReason) -> Decision {
            Decision(isEligible: false, rejectionReason: reason)
        }
    }

    public var rawInputVisibleMinimumWithoutLockedPrefix: Int
    public var lockedPrefixVisibleMinimum: Int
    public var lockedPrefixHanMinimum: Int

    public init(
        rawInputVisibleMinimumWithoutLockedPrefix: Int = 3,
        lockedPrefixVisibleMinimum: Int = 6,
        lockedPrefixHanMinimum: Int = 2
    ) {
        self.rawInputVisibleMinimumWithoutLockedPrefix = max(1, rawInputVisibleMinimumWithoutLockedPrefix)
        self.lockedPrefixVisibleMinimum = max(1, lockedPrefixVisibleMinimum)
        self.lockedPrefixHanMinimum = max(1, lockedPrefixHanMinimum)
    }

    public static let `default` = AIRecommendationTriggerPolicy()

    public func decision(rawInput: String, lockedPrefix: String?) -> Decision {
        if let lockedPrefix,
           !lockedPrefix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return lockedPrefixIsLongEnough(lockedPrefix)
                ? .eligible
                : .rejected(.prefixTooShort)
        }

        let visibleCount = Self.visibleCount(in: rawInput)
        return visibleCount >= rawInputVisibleMinimumWithoutLockedPrefix
            ? .eligible
            : .rejected(.rawTooShort)
    }

    private func lockedPrefixIsLongEnough(_ prefix: String) -> Bool {
        let visibleCount = Self.visibleCount(in: prefix)
        let hanCount = prefix.filter {
            String($0).range(of: #"\p{Han}"#, options: .regularExpression) != nil
        }.count
        if hanCount > 0 {
            return hanCount >= lockedPrefixHanMinimum || visibleCount >= lockedPrefixVisibleMinimum
        }
        return visibleCount >= lockedPrefixVisibleMinimum
    }

    private static func visibleCount(in text: String) -> Int {
        text.filter { !$0.isWhitespace && !$0.isNewline }.count
    }
}
