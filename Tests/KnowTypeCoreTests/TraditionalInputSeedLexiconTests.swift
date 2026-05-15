import XCTest
@testable import KnowTypeCore

final class TraditionalInputSeedLexiconTests: XCTestCase {
    func testSeedLexiconLoadsFromBundledResource() {
        let catalog = TraditionalInputSeedLexicon.catalog()

        XCTAssertFalse(catalog.hasDiagnostics)
        XCTAssertGreaterThan(catalog.entries.count, 80)
        XCTAssertTrue(catalog.entries.contains { entry in
            entry.pinyin == ["ni", "shi", "shei"]
                && entry.outputs.contains { $0.text == "你是谁" }
        })
    }

    func testDefaultEngineUsesBundledSeedLexicon() {
        let engine = TraditionalInputEngine()

        XCTAssertEqual(engine.candidates(for: "wsm").first?.text, "为什么")
        XCTAssertEqual(engine.candidates(for: "nishishei").first?.text, "你是谁")
    }
}
