import XCTest
@testable import KnowTypeInputMethod
import KnowTypeAI
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

    func testEngineExposesConfiguredSchemaIDForLexicalProfile() {
        let configuration = NativeRimeConfiguration(
            libraryURL: URL(fileURLWithPath: "/tmp/missing-librime.dylib"),
            sharedDataURL: URL(fileURLWithPath: "/tmp/missing-rime-data", isDirectory: true),
            userDataURL: URL(fileURLWithPath: "/tmp/missing-rime-user", isDirectory: true),
            logURL: URL(fileURLWithPath: "/tmp/missing-rime-logs", isDirectory: true),
            schemaID: "custom_schema"
        )

        let engine = RimeConversionEngine(configuration: configuration)

        XCTAssertEqual(engine.activeSchemaID, "custom_schema")
    }

    func testRimeSessionModeOptionsMapProcessStateToNativeOptionNames() {
        let options = RimeSessionModeOptions(
            state: InputModeState(
                textMode: .ascii,
                punctuationMode: .english,
                symbolWidth: .fullWidth
            )
        )

        XCTAssertEqual(options.asciiMode, true)
        XCTAssertEqual(options.asciiPunct, true)
        XCTAssertEqual(options.fullShape, true)
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: options.namedValues.map { ($0.name, $0.value) }),
            ["ascii_mode": true, "ascii_punct": true, "full_shape": true]
        )
    }

    func testModeSynchronizationRemainsColdStartReadOnlyWithoutNativeSession() throws {
        let fileManager = FileManager.default
        let root = temporaryDirectory(name: "rime-mode-sync-cold-start")
        defer {
            try? fileManager.removeItem(at: root)
        }
        let userData = root.appendingPathComponent("user", isDirectory: true)
        let logs = root.appendingPathComponent("logs", isDirectory: true)
        let configuration = NativeRimeConfiguration(
            libraryURL: root.appendingPathComponent("missing-librime.dylib"),
            sharedDataURL: root.appendingPathComponent("missing-rime-data", isDirectory: true),
            userDataURL: userData,
            logURL: logs
        )
        var engine = RimeConversionEngine(configuration: configuration)

        engine.synchronizeInputMode(
            InputModeSnapshot(
                state: InputModeState(
                    textMode: .ascii,
                    punctuationMode: .english,
                    symbolWidth: .fullWidth
                ),
                punctuationSource: .linked,
                generation: 3
            )
        )

        XCTAssertFalse(fileManager.fileExists(atPath: userData.path))
        XCTAssertFalse(fileManager.fileExists(atPath: logs.path))
        XCTAssertFalse(engine.isNativeActive)
    }

    func testNativeRimeSessionIsNotCreatedDuringEngineInitializationOrReadOnlyAccess() throws {
        let fileManager = FileManager.default
        let root = temporaryDirectory(name: "rime-lazy-cold-start")
        defer {
            try? fileManager.removeItem(at: root)
        }
        let userData = root.appendingPathComponent("user", isDirectory: true)
        let logs = root.appendingPathComponent("logs", isDirectory: true)
        let configuration = NativeRimeConfiguration(
            libraryURL: root.appendingPathComponent("missing-librime.dylib"),
            sharedDataURL: root.appendingPathComponent("missing-rime-data", isDirectory: true),
            userDataURL: userData,
            logURL: logs,
            schemaID: "custom_schema"
        )

        var engine = RimeConversionEngine(configuration: configuration)

        XCTAssertFalse(fileManager.fileExists(atPath: userData.path))
        XCTAssertFalse(fileManager.fileExists(atPath: logs.path))
        XCTAssertFalse(engine.isNativeActive)
        XCTAssertEqual(engine.activeSchemaID, "custom_schema")
        XCTAssertTrue(engine.snapshot.candidates.isEmpty)
        engine.reset()
        XCTAssertFalse(fileManager.fileExists(atPath: userData.path))
        XCTAssertFalse(fileManager.fileExists(atPath: logs.path))
    }

    func testNativeRimeSessionCreationIsDeferredUntilFirstProcessCall() throws {
        let fileManager = FileManager.default
        let root = temporaryDirectory(name: "rime-lazy-first-process")
        defer {
            try? fileManager.removeItem(at: root)
        }
        let userData = root.appendingPathComponent("user", isDirectory: true)
        let logs = root.appendingPathComponent("logs", isDirectory: true)
        let configuration = NativeRimeConfiguration(
            libraryURL: root.appendingPathComponent("missing-librime.dylib"),
            sharedDataURL: root.appendingPathComponent("missing-rime-data", isDirectory: true),
            userDataURL: userData,
            logURL: logs
        )
        var engine = RimeConversionEngine(configuration: configuration)

        XCTAssertFalse(fileManager.fileExists(atPath: userData.path))
        XCTAssertFalse(fileManager.fileExists(atPath: logs.path))

        _ = engine.process(.text("n"))

        XCTAssertTrue(fileManager.fileExists(atPath: userData.path))
        XCTAssertTrue(fileManager.fileExists(atPath: logs.path))
    }

    func testNativeRimeSessionCreationIsSkippedWhileRawBypassIsActive() throws {
        let fileManager = FileManager.default
        let root = temporaryDirectory(name: "rime-lazy-raw-bypass")
        defer {
            try? fileManager.removeItem(at: root)
        }
        let userData = root.appendingPathComponent("user", isDirectory: true)
        let logs = root.appendingPathComponent("logs", isDirectory: true)
        let configuration = NativeRimeConfiguration(
            libraryURL: root.appendingPathComponent("missing-librime.dylib"),
            sharedDataURL: root.appendingPathComponent("missing-rime-data", isDirectory: true),
            userDataURL: userData,
            logURL: logs
        )
        var engine = RimeConversionEngine(configuration: configuration)

        XCTAssertTrue(engine.process(.text("\u{E9}")).handled)
        XCTAssertTrue(engine.process(.text("n")).handled)
        XCTAssertFalse(engine.process(.pageDown).handled)

        XCTAssertFalse(fileManager.fileExists(atPath: userData.path))
        XCTAssertFalse(fileManager.fileExists(atPath: logs.path))
        XCTAssertFalse(engine.isNativeActive)
        XCTAssertEqual(engine.snapshot.rawInput, "\u{E9}n")
        XCTAssertEqual(engine.snapshot.engineName, "rime-raw-bypass")
    }

    func testUserDBSnapshotLocatorPrefersLocalInstallationSnapshot() throws {
        let fileManager = FileManager.default
        let root = temporaryDirectory(name: "rime-userdb-local-snapshot")
        defer {
            try? fileManager.removeItem(at: root)
        }
        let userData = root.appendingPathComponent("user", isDirectory: true)
        let sync = userData.appendingPathComponent("sync", isDirectory: true)
        let local = sync.appendingPathComponent("local-device", isDirectory: true)
        let other = sync.appendingPathComponent("other-device", isDirectory: true)
        try fileManager.createDirectory(at: local, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: other, withIntermediateDirectories: true)
        try """
        installation_id: "local-device"
        """.write(to: userData.appendingPathComponent("installation.yaml"), atomically: true, encoding: .utf8)
        let localSnapshot = local.appendingPathComponent("custom_dict.userdb.txt")
        let otherSnapshot = other.appendingPathComponent("custom_dict.userdb.txt")
        try "local\t本机\tc=1\n".write(to: localSnapshot, atomically: true, encoding: .utf8)
        try "other\t其他\tc=99\n".write(to: otherSnapshot, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1)], ofItemAtPath: localSnapshot.path)
        try fileManager.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2)], ofItemAtPath: otherSnapshot.path)
        let locator = RimeUserDBSnapshotLocator(fileManager: fileManager)

        let roots = locator.snapshotSearchRoots(syncDirectory: sync, userDataDirectory: userData)
        let selected = locator.findUserDBTextSnapshot(userDBName: "custom_dict", roots: roots)

        XCTAssertEqual(selected?.standardizedFileURL.path, localSnapshot.standardizedFileURL.path)
    }

    func testUserDBSnapshotLocatorChoosesLatestSnapshotDeterministicallyWithoutInstallationID() throws {
        let fileManager = FileManager.default
        let root = temporaryDirectory(name: "rime-userdb-deterministic-snapshot")
        defer {
            try? fileManager.removeItem(at: root)
        }
        let userData = root.appendingPathComponent("user", isDirectory: true)
        let sync = userData.appendingPathComponent("sync", isDirectory: true)
        let older = sync.appendingPathComponent("a-device", isDirectory: true)
        let newer = sync.appendingPathComponent("b-device", isDirectory: true)
        try fileManager.createDirectory(at: older, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: newer, withIntermediateDirectories: true)
        let olderSnapshot = older.appendingPathComponent("custom_dict.userdb.txt")
        let newerSnapshot = newer.appendingPathComponent("custom_dict.userdb.txt")
        try "old\t旧\tc=1\n".write(to: olderSnapshot, atomically: true, encoding: .utf8)
        try "new\t新\tc=2\n".write(to: newerSnapshot, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1)], ofItemAtPath: olderSnapshot.path)
        try fileManager.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2)], ofItemAtPath: newerSnapshot.path)
        let locator = RimeUserDBSnapshotLocator(fileManager: fileManager)

        let roots = locator.snapshotSearchRoots(syncDirectory: sync, userDataDirectory: userData)
        let selected = locator.findUserDBTextSnapshot(userDBName: "custom_dict", roots: roots)

        XCTAssertEqual(selected?.standardizedFileURL.path, newerSnapshot.standardizedFileURL.path)
    }

    func testUserDBTextSnapshotProviderReadsExistingSnapshotWithoutSyncing() async throws {
        let fileManager = FileManager.default
        let root = temporaryDirectory(name: "rime-userdb-existing-snapshot")
        defer {
            try? fileManager.removeItem(at: root)
        }
        let userData = root.appendingPathComponent("user", isDirectory: true)
        let sync = userData.appendingPathComponent("sync", isDirectory: true)
        try fileManager.createDirectory(at: sync, withIntermediateDirectories: true)
        let snapshotURL = sync.appendingPathComponent("pinyin_simp.userdb.txt")
        try "ni\t你\tc=12 d=0\n".write(to: snapshotURL, atomically: true, encoding: .utf8)
        let configuration = NativeRimeConfiguration(
            libraryURL: root.appendingPathComponent("missing-librime.dylib"),
            sharedDataURL: root.appendingPathComponent("share", isDirectory: true),
            userDataURL: userData,
            logURL: root.appendingPathComponent("logs", isDirectory: true),
            schemaID: "pinyin_simp"
        )
        let session = FakeRimeUserDBSnapshotSession(
            syncResult: false,
            userDataDirectory: userData,
            userDataSyncDirectory: sync,
            userDictionaryName: nil
        )
        let provider = RimeUserDBTextSnapshotProvider(
            configuration: configuration,
            sessionFactory: { _ in session }
        )

        let snapshot = try await provider.userDBTextSnapshot(schemaID: "pinyin_simp")

        XCTAssertEqual(snapshot.fileURL.standardizedFileURL.path, snapshotURL.standardizedFileURL.path)
        XCTAssertTrue(snapshot.content.contains("你"))
        XCTAssertEqual(session.syncCallCount, 0)
    }

    func testUserDBTextSnapshotProviderSyncsOnlyOnExplicitSyncedSnapshot() async throws {
        let fileManager = FileManager.default
        let root = temporaryDirectory(name: "rime-userdb-explicit-sync")
        defer {
            try? fileManager.removeItem(at: root)
        }
        let userData = root.appendingPathComponent("user", isDirectory: true)
        let sync = userData.appendingPathComponent("sync", isDirectory: true)
        try fileManager.createDirectory(at: sync, withIntermediateDirectories: true)
        let snapshotURL = sync.appendingPathComponent("pinyin_simp.userdb.txt")
        try "wo\t我\tc=21 d=0\n".write(to: snapshotURL, atomically: true, encoding: .utf8)
        let configuration = NativeRimeConfiguration(
            libraryURL: root.appendingPathComponent("missing-librime.dylib"),
            sharedDataURL: root.appendingPathComponent("share", isDirectory: true),
            userDataURL: userData,
            logURL: root.appendingPathComponent("logs", isDirectory: true),
            schemaID: "pinyin_simp"
        )
        let session = FakeRimeUserDBSnapshotSession(
            syncResult: true,
            userDataDirectory: userData,
            userDataSyncDirectory: sync,
            userDictionaryName: nil
        )
        let provider = RimeUserDBTextSnapshotProvider(
            configuration: configuration,
            sessionFactory: { _ in session }
        )

        let snapshot = try await provider.syncedUserDBTextSnapshot(schemaID: "pinyin_simp")

        XCTAssertEqual(snapshot.fileURL.standardizedFileURL.path, snapshotURL.standardizedFileURL.path)
        XCTAssertTrue(snapshot.content.contains("我"))
        XCTAssertEqual(session.syncCallCount, 1)
    }

    func testRimeMaintenanceServiceSyncsOnlyAfterIdlePolicyAllowsIt() async throws {
        let provider = CountingSyncSnapshotProvider()
        let service = RimeMaintenanceService(snapshotProvider: provider)
        let now = Date(timeIntervalSince1970: 1_000)
        let policy = RimeMaintenancePolicy(idleInterval: 60, minimumSyncInterval: 600)

        _ = try await service.syncUserDataIfIdle(
            schemaID: "pinyin_simp",
            lastInputAt: now.addingTimeInterval(-10),
            now: now,
            policy: policy
        )
        var counts = await provider.counts()
        XCTAssertEqual(counts.existing, 1)
        XCTAssertEqual(counts.synced, 0)

        _ = try await service.syncUserDataIfIdle(
            schemaID: "pinyin_simp",
            lastInputAt: now.addingTimeInterval(-120),
            now: now,
            policy: policy
        )
        counts = await provider.counts()
        XCTAssertEqual(counts.existing, 1)
        XCTAssertEqual(counts.synced, 1)

        _ = try await service.syncUserDataIfIdle(
            schemaID: "pinyin_simp",
            lastInputAt: now.addingTimeInterval(-120),
            now: now.addingTimeInterval(120),
            policy: policy
        )
        counts = await provider.counts()
        XCTAssertEqual(counts.existing, 2)
        XCTAssertEqual(counts.synced, 1)
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

    func testNativeRawInputMirrorUsesPreeditAfterHandledTextChangingNativeActionWithoutRawInput() {
        let partialSnapshot = ConversionEngineSnapshot(
            rawInput: "",
            preedit: "ceshi",
            candidates: [
                ConversionEngineCandidate(text: "测试", index: 0, source: "rime-native")
            ],
            highlightedIndex: 0,
            pageSize: 5,
            pageNumber: 0,
            isLastPage: false,
            engineName: "rime-native"
        )
        let result = ConversionEngineResult(handled: true, snapshot: partialSnapshot)

        XCTAssertEqual(
            NativeRawInputMirrorPolicy.updatedMirror(
                current: "woxiangceshi",
                key: .space,
                result: result
            ),
            "ceshi"
        )
        XCTAssertEqual(
            NativeRawInputMirrorPolicy.updatedMirror(
                current: "woxiangceshi",
                key: .selectCandidateOnCurrentPage(0),
                result: result
            ),
            "ceshi"
        )
        XCTAssertEqual(
            NativeRawInputMirrorPolicy.updatedMirror(
                current: "woxiangceshi",
                key: .selectCandidate(0),
                result: result
            ),
            "ceshi"
        )
        XCTAssertEqual(
            NativeRawInputMirrorPolicy.updatedMirror(
                current: "woxiangceshi",
                key: .commitComposition,
                result: result
            ),
            "ceshi"
        )
    }

    func testNativeRawInputMirrorKeepsCurrentMirrorForHighlightAndPagingWithoutRawInput() {
        let pageSnapshot = ConversionEngineSnapshot(
            rawInput: "",
            preedit: "shi",
            candidates: [
                ConversionEngineCandidate(text: "是", index: 0, source: "rime-native")
            ],
            highlightedIndex: 1,
            pageSize: 5,
            pageNumber: 1,
            isLastPage: false,
            engineName: "rime-native"
        )
        let result = ConversionEngineResult(handled: true, snapshot: pageSnapshot)

        XCTAssertEqual(
            NativeRawInputMirrorPolicy.updatedMirror(
                current: "shi",
                key: .highlightCandidateOnCurrentPage(1),
                result: result
            ),
            "shi"
        )
        XCTAssertEqual(
            NativeRawInputMirrorPolicy.updatedMirror(
                current: "shi",
                key: .pageDown,
                result: result
            ),
            "shi"
        )
        XCTAssertEqual(
            NativeRawInputMirrorPolicy.updatedMirror(
                current: "shi",
                key: .pageUp,
                result: result
            ),
            "shi"
        )
    }

    func testNativeRawInputMirrorClearsWhenHandledNativeActionClearsComposition() {
        let result = ConversionEngineResult(
            handled: true,
            commitText: "我",
            snapshot: ConversionEngineSnapshot(rawInput: "", preedit: "", engineName: "rime-native")
        )

        XCTAssertEqual(
            NativeRawInputMirrorPolicy.updatedMirror(
                current: "wo",
                key: .space,
                result: result
            ),
            ""
        )
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

    func testNativeRimePrewarmHandlesMissingConfiguration() {
        XCTAssertFalse(RimeConversionEngine.prewarmNativeSession(configuration: nil))
    }

    func testNativeRimePrewarmKeepsFirstProcessUsableWhenArtifactsAreAvailable() throws {
        let environment = ["KNOWTYPE_RIME_ENABLED": "1"]
        guard var configuration = NativeRimeConfiguration.defaultConfiguration(environment: environment) else {
            throw XCTSkip("Pinned librime artifacts are not prepared in Vendor/Rime")
        }
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("knowtype-rime-prewarm-\(UUID().uuidString)", isDirectory: true)
        configuration.userDataURL = sandbox.appendingPathComponent("user", isDirectory: true)
        configuration.logURL = sandbox.appendingPathComponent("logs", isDirectory: true)
        // librime keeps process-global state after a session is destroyed, so do
        // not remove this sandbox before the test process exits.

        XCTAssertTrue(RimeConversionEngine.prewarmNativeSession(configuration: configuration))

        var engine = RimeConversionEngine(
            traditionalInputEngine: TraditionalInputEngine(),
            configuration: configuration
        )
        XCTAssertTrue(engine.process(.text("n")).handled)
        guard engine.isNativeActive else {
            throw XCTSkip("librime could not create a native session")
        }
        XCTAssertTrue(engine.process(.text("i")).handled)
        XCTAssertFalse(engine.snapshot.candidates.isEmpty)
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
        XCTAssertTrue(engine.process(.text("w")).handled)
        guard engine.isNativeActive else {
            throw XCTSkip("librime could not create a native session")
        }

        XCTAssertTrue(engine.process(.text("o")).handled)
        guard !engine.snapshot.candidates.isEmpty else {
            throw XCTSkip("Rime shared data is not installed")
        }

        let result = engine.process(.space)

        XCTAssertNotNil(result.commitText)
        XCTAssertFalse(result.commitText?.isEmpty ?? true)
    }

    func testNativeRimeModeOptionsApplyOnCreationAndGenerationChangeWhenArtifactsAreAvailable() throws {
        let environment = ["KNOWTYPE_RIME_ENABLED": "1"]
        guard var configuration = NativeRimeConfiguration.defaultConfiguration(environment: environment) else {
            throw XCTSkip("Pinned librime artifacts are not prepared in Vendor/Rime")
        }
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("knowtype-rime-mode-options-\(UUID().uuidString)", isDirectory: true)
        configuration.userDataURL = sandbox.appendingPathComponent("user", isDirectory: true)
        configuration.logURL = sandbox.appendingPathComponent("logs", isDirectory: true)
        var engine = RimeConversionEngine(configuration: configuration)
        let fullWidthASCII = InputModeSnapshot(
            state: InputModeState(
                textMode: .ascii,
                punctuationMode: .english,
                symbolWidth: .fullWidth
            ),
            punctuationSource: .linked,
            generation: 7
        )

        engine.synchronizeInputMode(fullWidthASCII)
        _ = engine.process(.text("a"))
        guard engine.isNativeActive else {
            throw XCTSkip("librime could not create a native session")
        }

        XCTAssertEqual(engine.nativeOptionValue("ascii_mode"), true)
        XCTAssertEqual(engine.nativeOptionValue("ascii_punct"), true)
        XCTAssertEqual(engine.nativeOptionValue("full_shape"), true)

        engine.synchronizeInputMode(
            InputModeSnapshot(
                state: InputModeState(),
                punctuationSource: .linked,
                generation: 8
            )
        )

        XCTAssertEqual(engine.nativeOptionValue("ascii_mode"), false)
        XCTAssertEqual(engine.nativeOptionValue("ascii_punct"), false)
        XCTAssertEqual(engine.nativeOptionValue("full_shape"), false)
    }

    func testNativeRimeModeGenerationChangeAppliesDuringActiveCompositionWhenArtifactsAreAvailable() throws {
        let environment = ["KNOWTYPE_RIME_ENABLED": "1"]
        guard var configuration = NativeRimeConfiguration.defaultConfiguration(environment: environment) else {
            throw XCTSkip("Pinned librime artifacts are not prepared in Vendor/Rime")
        }
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("knowtype-rime-active-mode-options-\(UUID().uuidString)", isDirectory: true)
        configuration.userDataURL = sandbox.appendingPathComponent("user", isDirectory: true)
        configuration.logURL = sandbox.appendingPathComponent("logs", isDirectory: true)
        var engine = RimeConversionEngine(configuration: configuration)

        XCTAssertTrue(engine.process(.text("n")).handled)
        guard engine.isNativeActive else {
            throw XCTSkip("librime could not create a native session")
        }
        XCTAssertTrue(engine.snapshot.hasComposition)

        engine.synchronizeInputMode(
            InputModeSnapshot(
                state: InputModeState(
                    textMode: .chinese,
                    punctuationMode: .english,
                    symbolWidth: .fullWidth
                ),
                punctuationSource: .manual,
                generation: 1
            )
        )

        XCTAssertEqual(engine.nativeOptionValue("ascii_mode"), false)
        XCTAssertEqual(engine.nativeOptionValue("ascii_punct"), true)
        XCTAssertEqual(engine.nativeOptionValue("full_shape"), true)
        XCTAssertTrue(engine.snapshot.hasComposition)
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
        XCTAssertTrue(engine.process(.text("s")).handled)
        guard engine.isNativeActive else {
            throw XCTSkip("librime could not create a native session")
        }

        for character in "hi" {
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
        XCTAssertTrue(engine.process(.text("n")).handled)
        guard engine.isNativeActive else {
            throw XCTSkip("librime could not create a native session")
        }

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

private func temporaryDirectory(name: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
}

private final class FakeRimeUserDBSnapshotSession: RimeUserDBMaintenanceSession, @unchecked Sendable {
    private let syncResult: Bool
    private let userDataDirectoryURL: URL?
    private let userDataSyncDirectoryURL: URL?
    private let dictionaryName: String?
    private(set) var syncCallCount = 0

    init(
        syncResult: Bool,
        userDataDirectory: URL?,
        userDataSyncDirectory: URL?,
        userDictionaryName: String?
    ) {
        self.syncResult = syncResult
        self.userDataDirectoryURL = userDataDirectory
        self.userDataSyncDirectoryURL = userDataSyncDirectory
        self.dictionaryName = userDictionaryName
    }

    func syncUserData() -> Bool {
        syncCallCount += 1
        return syncResult
    }

    func userDataDirectory() -> URL? {
        userDataDirectoryURL
    }

    func userDataSyncDirectory() -> URL? {
        userDataSyncDirectoryURL
    }

    func userDictionaryName(schemaID _: String) -> String? {
        dictionaryName
    }
}

private actor CountingSyncSnapshotProvider: RimeUserDBTextSnapshotSyncProviding {
    private(set) var existingCount = 0
    private(set) var syncCount = 0

    func counts() -> (existing: Int, synced: Int) {
        (existingCount, syncCount)
    }

    func userDBTextSnapshot(schemaID: String) async throws -> RimeUserDBTextSnapshot {
        existingCount += 1
        return snapshot(schemaID: schemaID, content: "existing\t已有\t1\n")
    }

    func syncedUserDBTextSnapshot(schemaID: String) async throws -> RimeUserDBTextSnapshot {
        syncCount += 1
        return snapshot(schemaID: schemaID, content: "synced\t同步\t2\n")
    }

    private func snapshot(schemaID: String, content: String) -> RimeUserDBTextSnapshot {
        RimeUserDBTextSnapshot(
            schemaID: schemaID,
            fileURL: URL(fileURLWithPath: "/tmp/\(schemaID).userdb.txt"),
            content: content
        )
    }
}
