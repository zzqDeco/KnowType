import Foundation
import XCTest
@testable import KnowTypeCore

final class TraditionalInputLexiconResourceLoaderTests: XCTestCase {
    func testLoadJSONNormalizesEntriesAndFeedsEngine() throws {
        let json = """
        [
          {
            "pinyin": [" XI ", " AN "],
            "outputs": [
              { "text": " 西安 ", "confidence": 0.995 }
            ]
          }
        ]
        """
        let entries = try TraditionalInputLexiconResourceLoader().loadJSON(Data(json.utf8))
        let engine = TraditionalInputEngine(additionalLexiconEntries: entries)

        XCTAssertEqual(entries.first?.pinyin, ["xi", "an"])
        XCTAssertEqual(entries.first?.outputs.first?.text, "西安")
        XCTAssertEqual(engine.candidates(for: "xian").first?.text, "西安")
    }

    func testLoadTSVSupportsCommentsDefaultConfidenceAndExplicitConfidence() throws {
        let tsv = """
        # pinyin\ttext\tconfidence
        ce shi ci\t测试词\t0.91
        zhuan you ming ci\t专有名词
        """

        let entries = try TraditionalInputLexiconResourceLoader().loadTSV(Data(tsv.utf8))

        XCTAssertEqual(entries.map(\.pinyin), [
            ["ce", "shi", "ci"],
            ["zhuan", "you", "ming", "ci"]
        ])
        XCTAssertEqual(entries[0].outputs.first?.text, "测试词")
        XCTAssertEqual(entries[0].outputs.first?.confidence ?? 0, 0.91, accuracy: 0.0001)
        XCTAssertEqual(entries[1].outputs.first?.confidence ?? 0, 0.72, accuracy: 0.0001)
    }

    func testLoadDispatchesByFormat() throws {
        let json = """
        [{ "pinyin": ["ce"], "outputs": [{ "text": "测", "confidence": 0.8 }] }]
        """
        let tsv = "ce\t测\t0.8\n"
        let loader = TraditionalInputLexiconResourceLoader()

        XCTAssertEqual(try loader.load(Data(json.utf8), format: .json), try loader.loadJSON(Data(json.utf8)))
        XCTAssertEqual(try loader.load(Data(tsv.utf8), format: .tsv), try loader.loadTSV(Data(tsv.utf8)))
    }

    func testInvalidUTF8TSVThrowsTypedError() {
        XCTAssertThrowsError(
            try TraditionalInputLexiconResourceLoader().loadTSV(Data([0xFF]))
        ) { error in
            XCTAssertEqual(error as? TraditionalInputLexiconResourceError, .invalidUTF8)
        }
    }

    func testInvalidTSVColumnsThrowLineError() {
        XCTAssertThrowsError(
            try TraditionalInputLexiconResourceLoader().loadTSV(Data("ce\t测\t0.8\textra\n".utf8))
        ) { error in
            XCTAssertEqual(
                error as? TraditionalInputLexiconResourceError,
                .invalidTSVLine(line: 1, reason: "expected pinyin, text, and optional confidence columns")
            )
        }
    }

    func testInvalidEntriesThrowTypedValidationErrors() {
        let json = """
        [{ "pinyin": ["ce"], "outputs": [{ "text": "测", "confidence": 1.2 }] }]
        """

        XCTAssertThrowsError(
            try TraditionalInputLexiconResourceLoader().loadJSON(Data(json.utf8))
        ) { error in
            XCTAssertEqual(
                error as? TraditionalInputLexiconResourceError,
                .invalidEntry(index: 0, reason: "output 0 confidence must be between 0 and 1")
            )
        }
    }
}
