import XCTest
@testable import KnowTypeInputMethod
import KnowTypeCore

final class RimeConversionEngineTests: XCTestCase {
    func testFallbackSessionCommitsFirstCandidateOnSpace() {
        var engine = RimeConversionEngine(
            traditionalInputEngine: TraditionalInputEngine(),
            configuration: nil
        )

        XCTAssertFalse(engine.isNativeActive)
        XCTAssertTrue(engine.process(.text("w")).handled)
        XCTAssertTrue(engine.process(.text("o")).handled)
        XCTAssertFalse(engine.snapshot.candidates.isEmpty)

        let result = engine.process(.space)

        XCTAssertEqual(result.commitText, "我")
    }

    func testFallbackNumberSelectionCommitsVisibleCandidateWithoutAppendingDigit() throws {
        var engine = RimeConversionEngine(
            traditionalInputEngine: TraditionalInputEngine(),
            configuration: nil
        )

        _ = engine.process(.text("n"))
        _ = engine.process(.text("i"))
        let secondCandidate = try XCTUnwrap(engine.snapshot.candidates.dropFirst().first?.text)

        let result = engine.process(.selectCandidate(1))

        XCTAssertEqual(result.commitText, secondCandidate)
    }

    func testNativeRimeSessionSmokeWhenArtifactsAreAvailable() throws {
        let environment = ["KNOWTYPE_RIME_ENABLED": "1"]
        guard var configuration = NativeRimeConfiguration.defaultConfiguration(environment: environment) else {
            throw XCTSkip("Pinned librime artifacts are not prepared in Vendor/Rime")
        }
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("knowtype-rime-smoke-\(UUID().uuidString)", isDirectory: true)
        configuration.userDataURL = sandbox.appendingPathComponent("user", isDirectory: true)
        configuration.logURL = sandbox.appendingPathComponent("logs", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: sandbox)
        }

        var engine = RimeConversionEngine(
            traditionalInputEngine: TraditionalInputEngine(),
            configuration: configuration
        )
        guard engine.isNativeActive else {
            throw XCTSkip("librime could not create a native session")
        }

        XCTAssertTrue(engine.process(.text("w")).handled)
        XCTAssertTrue(engine.process(.text("o")).handled)
        guard !engine.snapshot.candidates.isEmpty else {
            throw XCTSkip("Rime shared data is not installed")
        }

        let result = engine.process(.space)

        XCTAssertNotNil(result.commitText)
        XCTAssertFalse(result.commitText?.isEmpty ?? true)
    }
}
