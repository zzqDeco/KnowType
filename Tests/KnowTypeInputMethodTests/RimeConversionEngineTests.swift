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

    func testSourceTreeRimeArtifactsRequireExplicitOptIn() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("knowtype-rime-source-opt-in-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? fileManager.removeItem(at: root)
        }
        let libraryDirectory = root.appendingPathComponent("Vendor/Rime/dist/lib", isDirectory: true)
        let sharedDirectory = root.appendingPathComponent("Vendor/Rime/share", isDirectory: true)
        try fileManager.createDirectory(at: libraryDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: sharedDirectory, withIntermediateDirectories: true)
        fileManager.createFile(
            atPath: libraryDirectory.appendingPathComponent("librime.1.dylib").path,
            contents: Data()
        )
        fileManager.createFile(
            atPath: sharedDirectory.appendingPathComponent("pinyin_simp.schema.yaml").path,
            contents: Data()
        )
        let previousDirectory = fileManager.currentDirectoryPath
        XCTAssertTrue(fileManager.changeCurrentDirectoryPath(root.path))
        defer {
            fileManager.changeCurrentDirectoryPath(previousDirectory)
        }

        let defaultConfiguration = NativeRimeConfiguration.defaultConfiguration(environment: [:])
        XCTAssertNotEqual(
            defaultConfiguration?.libraryURL.standardizedFileURL.path,
            libraryDirectory.appendingPathComponent("librime.1.dylib").standardizedFileURL.path
        )
        XCTAssertNotEqual(
            defaultConfiguration?.sharedDataURL.standardizedFileURL.path,
            sharedDirectory.standardizedFileURL.path
        )

        let optInConfiguration = NativeRimeConfiguration.defaultConfiguration(
            environment: ["KNOWTYPE_RIME_ENABLED": "1"]
        )
        XCTAssertEqual(
            optInConfiguration?.libraryURL.standardizedFileURL.path,
            libraryDirectory.appendingPathComponent("librime.1.dylib").standardizedFileURL.path
        )
        XCTAssertEqual(
            optInConfiguration?.sharedDataURL.standardizedFileURL.path,
            sharedDirectory.standardizedFileURL.path
        )
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
        // librime keeps process-global state after a session is destroyed, so do
        // not remove this sandbox before the test process exits.

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

    func testNativeRimePageDownChangesCurrentPageSnapshotWhenArtifactsAreAvailable() throws {
        let environment = ["KNOWTYPE_RIME_ENABLED": "1"]
        guard var configuration = NativeRimeConfiguration.defaultConfiguration(environment: environment) else {
            throw XCTSkip("Pinned librime artifacts are not prepared in Vendor/Rime")
        }
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("knowtype-rime-paging-\(UUID().uuidString)", isDirectory: true)
        configuration.userDataURL = sandbox.appendingPathComponent("user", isDirectory: true)
        configuration.logURL = sandbox.appendingPathComponent("logs", isDirectory: true)
        // librime keeps process-global state after a session is destroyed, so do
        // not remove this sandbox before the test process exits.

        var engine = RimeConversionEngine(
            traditionalInputEngine: TraditionalInputEngine(),
            configuration: configuration
        )
        guard engine.isNativeActive else {
            throw XCTSkip("librime could not create a native session")
        }

        for character in "shi" {
            XCTAssertTrue(engine.process(.text(String(character))).handled)
        }
        let firstPage = engine.snapshot.candidates.map(\.text)
        guard !firstPage.isEmpty, !engine.snapshot.isLastPage else {
            throw XCTSkip("Rime shared data did not expose multiple pages for paging smoke input")
        }

        let result = engine.process(.pageDown)

        XCTAssertTrue(result.handled)
        XCTAssertEqual(engine.snapshot.pageNumber, 1)
        XCTAssertNotEqual(engine.snapshot.candidates.map(\.text), firstPage)
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
        // librime keeps process-global state after a session is destroyed, so do
        // not remove this sandbox before the test process exits.

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
