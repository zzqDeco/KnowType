import Foundation
import XCTest
@testable import KnowTypeCore

final class TraditionalInputLexiconCatalogTests: XCTestCase {
    func testCatalogLoadsMultipleResourcesAndBuildsEngine() {
        let json = """
        [{ "pinyin": ["xi", "an"], "outputs": [{ "text": "西安", "confidence": 0.995 }] }]
        """
        let tsv = "ce shi ci\t测试词\t0.91\n"

        let catalog = TraditionalInputLexiconCatalogLoader().load([
            TraditionalInputLexiconResource(id: "places", format: .json, data: Data(json.utf8)),
            TraditionalInputLexiconResource(id: "product", format: .tsv, data: Data(tsv.utf8))
        ])
        let engine = catalog.makeEngine()

        XCTAssertFalse(catalog.hasDiagnostics)
        XCTAssertEqual(catalog.entries.count, 2)
        XCTAssertEqual(engine.candidates(for: "xian").first?.text, "西安")
        XCTAssertEqual(engine.candidates(for: "ceshici").first?.text, "测试词")
    }

    func testCatalogKeepsValidResourcesWhenOneResourceFails() {
        let valid = "ce shi ci\t测试词\t0.91\n"
        let invalid = "bad\trow\t0.9\textra\n"

        let catalog = TraditionalInputLexiconCatalogLoader().load([
            TraditionalInputLexiconResource(id: "valid", format: .tsv, data: Data(valid.utf8)),
            TraditionalInputLexiconResource(id: "invalid", format: .tsv, data: Data(invalid.utf8))
        ])
        let engine = catalog.makeEngine()

        XCTAssertTrue(catalog.hasDiagnostics)
        XCTAssertEqual(catalog.entries.count, 1)
        XCTAssertEqual(engine.candidates(for: "ceshici").first?.text, "测试词")
        XCTAssertEqual(catalog.diagnostics, [
            TraditionalInputLexiconDiagnostic(
                resourceID: "invalid",
                error: .invalidTSVLine(
                    line: 1,
                    reason: "expected pinyin, text, and optional confidence columns"
                )
            )
        ])
    }

    func testCatalogPreservesEntryOrderAcrossResources() {
        let first = "ce shi ci\t测试词\t0.91\n"
        let second = "xi an\t西安\t0.995\n"

        let catalog = TraditionalInputLexiconCatalogLoader().load([
            TraditionalInputLexiconResource(id: "first", format: .tsv, data: Data(first.utf8)),
            TraditionalInputLexiconResource(id: "second", format: .tsv, data: Data(second.utf8))
        ])

        XCTAssertEqual(catalog.entries.map(\.outputs.first?.text), ["测试词", "西安"])
    }
}
