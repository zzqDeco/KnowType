import XCTest
@testable import KnowTypeInputMethod
import KnowTypeCore

final class RimeConversionEngineTests: XCTestCase {
    func testUnavailableSessionTracksRawInputWithoutTraditionalCandidates() {
        var engine = RimeConversionEngine(
            traditionalInputEngine: TraditionalInputEngine(),
            configuration: nil
        )

        XCTAssertFalse(engine.isNativeActive)
        XCTAssertTrue(engine.process(.text("w")).handled)
        XCTAssertTrue(engine.process(.text("o")).handled)
        XCTAssertEqual(engine.snapshot.rawInput, "wo")
        XCTAssertEqual(engine.snapshot.preedit, "wo")
        XCTAssertTrue(engine.snapshot.candidates.isEmpty)
        XCTAssertEqual(engine.snapshot.engineName, "rime-unavailable")

        let result = engine.process(.space)

        XCTAssertFalse(result.handled)
        XCTAssertNil(result.commitText)
    }

    func testUnavailableSessionDoesNotCommitCandidateSelection() {
        var engine = RimeConversionEngine(
            traditionalInputEngine: TraditionalInputEngine(),
            configuration: nil
        )

        _ = engine.process(.text("n"))
        _ = engine.process(.text("i"))

        let result = engine.process(.selectCandidateOnCurrentPage(1))

        XCTAssertFalse(result.handled)
        XCTAssertNil(result.commitText)
        XCTAssertEqual(engine.snapshot.rawInput, "ni")
    }

    func testUnavailableSessionPreservesRawBypassForNonASCIIInput() {
        var engine = RimeConversionEngine(
            traditionalInputEngine: TraditionalInputEngine(),
            configuration: nil
        )

        XCTAssertTrue(engine.process(.text("n")).handled)
        XCTAssertTrue(engine.process(.text("i")).handled)
        XCTAssertTrue(engine.process(.text("\u{E9}")).handled)

        XCTAssertEqual(engine.snapshot.rawInput, "ni\u{E9}")
        XCTAssertTrue(engine.snapshot.candidates.isEmpty)
        XCTAssertEqual(engine.snapshot.engineName, "rime-raw-bypass")
    }

    func testNativeConfigurationExpandsTildeEnvironmentPaths() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let url = NativeRimeConfiguration.environmentFileURL(
            path: "~/Library/Application Support/KnowType/Rime",
            isDirectory: true
        )

        XCTAssertEqual(
            url.standardizedFileURL.path,
            home
                .appendingPathComponent("Library/Application Support/KnowType/Rime", isDirectory: true)
                .standardizedFileURL
                .path
        )
        XCTAssertTrue(url.hasDirectoryPath)
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

    func testNativeNonASCIIBypassPreservesRawWithoutTraditionalFallbackWhenArtifactsAreAvailable() throws {
        let environment = ["KNOWTYPE_RIME_ENABLED": "1"]
        guard var configuration = NativeRimeConfiguration.defaultConfiguration(environment: environment) else {
            throw XCTSkip("Pinned librime artifacts are not prepared in Vendor/Rime")
        }
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("knowtype-rime-nonascii-\(UUID().uuidString)", isDirectory: true)
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

        XCTAssertTrue(engine.process(.text("n")).handled)
        XCTAssertTrue(engine.process(.text("i")).handled)
        let existingComposition = engine.snapshot.rawInput.isEmpty
            ? engine.snapshot.preedit
            : engine.snapshot.rawInput
        XCTAssertFalse(existingComposition.isEmpty)

        XCTAssertTrue(engine.process(.text("\u{E9}")).handled)

        XCTAssertFalse(engine.isNativeActive)
        XCTAssertEqual(engine.snapshot.rawInput, "\(existingComposition)\u{E9}")
        XCTAssertTrue(engine.snapshot.candidates.isEmpty)
        XCTAssertEqual(engine.snapshot.engineName, "rime-raw-bypass")
    }
}
