import CryptoKit
import Foundation
import KnowTypeCore
import KnowTypeProviders

public enum AIRequestBudget {
    public static let recommendationLogicalPayload = 32 * 1_024
    public static let recommendationHTTPBody = 64 * 1_024
    public static let digestEvents = 48 * 1_024
    public static let digestEnvironmentProjection = 8 * 1_024
    public static let digestLogicalPayload = 64 * 1_024
    public static let digestHTTPBody = 96 * 1_024
    public static let generated = 4 * 1_024
    public static let userNotes = 4 * 1_024
    public static let correction = 4 * 1_024
    public static let lexical = 6 * 1_024
    public static let feedback = 4 * 1_024
    public static let rawInput = 4 * 1_024
    public static let lockedPrefix = 4 * 1_024

    public static func fingerprint(for request: LLMRequest) throws -> String {
        let data = try ProviderRequestBudget.encodedPayload(for: request)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
