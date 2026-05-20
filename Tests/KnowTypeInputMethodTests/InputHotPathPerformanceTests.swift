import CoreGraphics
import Foundation
import KnowTypeCore
@testable import KnowTypeInputMethod
import XCTest

final class InputHotPathPerformanceTests: XCTestCase {
    func testCoordinatorSourceKeepsRetiredLocalConversionOutOfHotPath() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let coordinator = try String(
            contentsOf: rootURL.appendingPathComponent("Sources/KnowTypeInputMethod/InputControllerCoordinator.swift"),
            encoding: .utf8
        )
        let inputController = try String(
            contentsOf: rootURL.appendingPathComponent("Sources/KnowTypeInputMethod/InputController.swift"),
            encoding: .utf8
        )
        let rimeEngine = try String(
            contentsOf: rootURL.appendingPathComponent("Sources/KnowTypeInputMethod/RimeConversionEngine.swift"),
            encoding: .utf8
        )
        let settingsView = try String(
            contentsOf: rootURL.appendingPathComponent("Sources/KnowTypeSettingsUI/ProviderProfilesView.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(coordinator.contains("InputMethodPipeline.localSuggestions"))
        XCTAssertFalse(coordinator.contains(".segmentCandidates("))
        XCTAssertFalse(coordinator.contains("mergedPrefixCandidates"))
        XCTAssertFalse(coordinator.contains("prioritizedSegmentCandidates"))
        XCTAssertFalse(coordinator.contains("lexiconRuntime.makeEngine"))
        XCTAssertFalse(coordinator.contains("InputMethodLexiconRuntime.defaultEngine"))
        XCTAssertFalse(coordinator.contains("TraditionalInputEngine()"))
        XCTAssertFalse(inputController.contains("InputMethodLexiconRuntime.defaultRuntime"))
        XCTAssertFalse(inputController.contains("initialEngineState"))
        XCTAssertFalse(rimeEngine.contains("InputMethodLexiconRuntime.defaultEngine"))
        XCTAssertFalse(settingsView.contains(#"Picker("Input scheme""#))
        XCTAssertFalse(settingsView.contains("Xiaohe Shuangpin"))
    }

    func testStrictRimeOnlyHotPathBudgetsWhenEnabled() throws {
        guard ProcessInfo.processInfo.environment["KNOWTYPE_STRICT_INPUT_PERF"] == "1" else {
            throw XCTSkip("Set KNOWTYPE_STRICT_INPUT_PERF=1 to run strict hot-path budgets")
        }
        guard var configuration = NativeRimeConfiguration.defaultConfiguration(
            environment: ProcessInfo.processInfo.environment.merging(["KNOWTYPE_RIME_ENABLED": "1"]) { current, _ in current }
        ) else {
            throw XCTSkip("Pinned librime artifacts are not prepared in Vendor/Rime")
        }
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("knowtype-hotpath-perf-\(UUID().uuidString)", isDirectory: true)
        configuration.userDataURL = sandbox.appendingPathComponent("user", isDirectory: true)
        configuration.logURL = sandbox.appendingPathComponent("logs", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: sandbox)
        }

        var rimeEngine = RimeConversionEngine(configuration: configuration)
        guard rimeEngine.isNativeActive else {
            throw XCTSkip("librime could not create a native session")
        }
        _ = runRimeSequence("wo", commit: .space, engine: &rimeEngine)

        try assertP95("rime.wo.space", budgetMilliseconds: 5) {
            rimeEngine.reset()
        } operation: {
            let result = runRimeSequence("wo", commit: .space, engine: &rimeEngine)
            XCTAssertNotEqual(result.commitText, "wo")
        }
        try assertP95("rime.woxiangceshi.space", budgetMilliseconds: 15) {
            rimeEngine.reset()
        } operation: {
            let result = runRimeSequence("woxiangceshi", commit: .space, engine: &rimeEngine)
            XCTAssertNotEqual(result.commitText, "woxiangceshi")
        }
        try assertP95("rime.ni.select2", budgetMilliseconds: 5) {
            rimeEngine.reset()
        } operation: {
            let result = runRimeSequence("ni", commit: .selectCandidateOnCurrentPage(1), engine: &rimeEngine)
            XCTAssertNotEqual(result.commitText, "ni2")
        }
        try assertPerStepBudget("rime.woxiangceshi.steps", budgetMilliseconds: 16) { measure in
            rimeEngine.reset()
            for character in "woxiangceshi" {
                try measure {
                    _ = rimeEngine.process(.text(String(character)))
                }
            }
            try measure {
                let result = rimeEngine.process(.space)
                XCTAssertNotEqual(result.commitText, "woxiangceshi")
            }
        }
        let appendFixture = makeCoordinator(configuration: configuration)
        try assertP95("coordinator.append.single", budgetMilliseconds: 8) {
        } operation: {
            XCTAssertTrue(appendFixture.coordinator.handleText("w", client: appendFixture.client))
        } cleanup: {
            XCTAssertTrue(appendFixture.coordinator.handleText(" ", client: appendFixture.client))
        }
        let shortCommitFixture = makeCoordinator(configuration: configuration)
        try assertP95("coordinator.wo.space", budgetMilliseconds: 20) {
        } operation: {
            for character in "wo" {
                XCTAssertTrue(shortCommitFixture.coordinator.handleText(String(character), client: shortCommitFixture.client))
            }
            XCTAssertTrue(shortCommitFixture.coordinator.handleText(" ", client: shortCommitFixture.client))
            XCTAssertFalse(shortCommitFixture.client.insertTextWrites.last?.text == "wo")
        }
        let longCommitFixture = makeCoordinator(configuration: configuration)
        try assertP95("coordinator.woxiangceshi.space", budgetMilliseconds: 45) {
        } operation: {
            for character in "woxiangceshi" {
                XCTAssertTrue(longCommitFixture.coordinator.handleText(String(character), client: longCommitFixture.client))
            }
            XCTAssertTrue(longCommitFixture.coordinator.handleText(" ", client: longCommitFixture.client))
            XCTAssertFalse(longCommitFixture.client.insertTextWrites.last?.text == "woxiangceshi")
        }
        let numberFixture = makeCoordinator(configuration: configuration)
        try assertP95("coordinator.ni.number2", budgetMilliseconds: 20) {
        } operation: {
            for character in "ni" {
                XCTAssertTrue(numberFixture.coordinator.handleText(String(character), client: numberFixture.client))
            }
            XCTAssertTrue(
                numberFixture.coordinator.handle(
                    stroke: InputKeyStroke(text: "2", keyCode: 19),
                    client: numberFixture.client
                )
            )
            XCTAssertNotEqual(numberFixture.client.insertTextWrites.last?.text, "ni2")
        }
        let stepFixture = makeCoordinator(configuration: configuration)
        try assertPerStepBudget("coordinator.woxiangceshi.steps", budgetMilliseconds: 16) { measure in
            for character in "woxiangceshi" {
                try measure {
                    XCTAssertTrue(stepFixture.coordinator.handleText(String(character), client: stepFixture.client))
                }
            }
            try measure {
                XCTAssertTrue(stepFixture.coordinator.handleText(" ", client: stepFixture.client))
                XCTAssertFalse(stepFixture.client.insertTextWrites.last?.text == "woxiangceshi")
            }
        }
    }

    private func runRimeSequence(
        _ text: String,
        commit: ConversionEngineKey,
        engine: inout RimeConversionEngine
    ) -> ConversionEngineResult {
        for character in text {
            _ = engine.process(.text(String(character)))
        }
        return engine.process(commit)
    }

    private func assertP95(
        _ name: String,
        budgetMilliseconds: Double,
        iterations: Int = 60,
        prepare: () throws -> Void = {},
        operation: () throws -> Void,
        cleanup: () throws -> Void = {}
    ) throws {
        var samples: [Double] = []
        samples.reserveCapacity(iterations)
        for _ in 0..<5 {
            try prepare()
            try operation()
            try cleanup()
        }
        for _ in 0..<iterations {
            try prepare()
            let start = ContinuousClock.now
            try operation()
            let elapsed = start.duration(to: .now)
            samples.append(Self.milliseconds(elapsed))
            try cleanup()
        }
        let sorted = samples.sorted()
        let p95Index = min(sorted.count - 1, Int(Double(sorted.count - 1) * 0.95))
        let p50 = sorted[sorted.count / 2]
        let p95 = sorted[p95Index]
        let maxValue = sorted.last ?? 0
        print(
            String(
                format: "KnowType perf %@ p50=%.3fms p95=%.3fms max=%.3fms budget=%.3fms",
                name,
                p50,
                p95,
                maxValue,
                budgetMilliseconds
            )
        )
        XCTAssertLessThanOrEqual(p95, budgetMilliseconds, "\(name) p95 exceeded budget")
    }

    private func assertPerStepBudget(
        _ name: String,
        budgetMilliseconds: Double,
        iterations: Int = 60,
        sequence: (_ measure: (_ step: () throws -> Void) throws -> Void) throws -> Void
    ) throws {
        var samples: [Double] = []
        for _ in 0..<5 {
            try sequence { step in
                try step()
            }
        }
        for _ in 0..<iterations {
            try sequence { step in
                let start = ContinuousClock.now
                try step()
                let elapsed = start.duration(to: .now)
                samples.append(Self.milliseconds(elapsed))
            }
        }
        let sorted = samples.sorted()
        let p95Index = min(sorted.count - 1, Int(Double(sorted.count - 1) * 0.95))
        let p50 = sorted[sorted.count / 2]
        let p95 = sorted[p95Index]
        let maxValue = sorted.last ?? 0
        let overBudgetCount = samples.filter { $0 > budgetMilliseconds }.count
        print(
            String(
                format: "KnowType perf %@ p50=%.3fms p95=%.3fms max=%.3fms budget=%.3fms over_budget=%d",
                name,
                p50,
                p95,
                maxValue,
                budgetMilliseconds,
                overBudgetCount
            )
        )
        XCTAssertLessThanOrEqual(p95, budgetMilliseconds, "\(name) p95 exceeded per-key budget")
        XCTAssertLessThanOrEqual(overBudgetCount, 1, "\(name) exceeded per-key guardrail too often")
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1_000
            + Double(duration.components.attoseconds) / 1_000_000_000_000_000
    }

    private func makeCoordinator(
        configuration: NativeRimeConfiguration
    ) -> (coordinator: InputControllerCoordinator, client: PerfInputControllerClient) {
        let client = PerfInputControllerClient()
        let host = PerfInputControllerHost()
        host.currentClientValue = client
        let coordinator = InputControllerCoordinator(
            provider: nil,
            traditionalInputEngine: TraditionalInputEngine(),
            lexiconRuntimeSnapshot: InputMethodLexiconRuntimeSnapshot(directories: [], scheme: .fullPinyin),
            lexiconRuntime: InputMethodLexiconRuntime(directories: []),
            inputModePreferenceStore: PerfInputModePreferenceStore(),
            runtimePreferenceStore: PerfRuntimePreferenceStore(),
            initialRuntimePreferences: .standard,
            initialAppBundleID: client.bundleIdentifier,
            userSelectionHistoryPersistence: nil,
            conversionEngine: RimeConversionEngine(configuration: configuration),
            host: host,
            anchorResolver: CandidateAnchorResolver(
                screenProvider: PerfScreenProvider(),
                accessibilityProvider: NoopAccessibilityAnchorProvider(),
                traceEnabled: false
            ),
            enablesAsyncSuggestionRefresh: true
        )
        return (coordinator, client)
    }
}

private struct PerfScreenProvider: ScreenGeometryProviding {
    var screens: [CandidateAnchorScreen] = [
        CandidateAnchorScreen(
            identifier: "main",
            frame: CGRect(x: 0, y: 0, width: 800, height: 800),
            visibleFrame: CGRect(x: 0, y: 0, width: 800, height: 760)
        )
    ]
}

private final class PerfInputControllerHost: InputControllerHost {
    var currentClientValue: InputControllerClient?
    var currentClient: InputControllerClient? { currentClientValue }
    private(set) var panelStates: [CandidatePanelState] = []

    func updateComposition() {}
    func updateCandidatePanel(state: CandidatePanelState, locale: KnowTypeLocale) {
        panelStates.append(state)
    }
    func hideCandidatePanel() {}
    func scheduleDelayedReanchor(_ operation: @escaping @Sendable () -> Void) {
        operation()
    }
}

private final class PerfInputControllerClient: InputControllerClient, @unchecked Sendable {
    struct InsertTextWrite: Equatable {
        var text: String
        var replacementRange: NSRange
    }

    var bundleIdentifier: String? = "com.example.perf"
    var selectedRange: NSRange = NSRange(location: 0, length: 0)
    var markedRange: NSRange?
    var firstRectValue = CGRect(x: 40, y: 500, width: 0, height: 18)
    var lineHeightRectValue = CGRect(x: 40, y: 500, width: 0, height: 18)
    private(set) var insertTextWrites: [InsertTextWrite] = []

    func firstRect(forCharacterRange range: NSRange) -> CGRect {
        firstRectValue
    }

    func lineHeightRect(forCharacterIndex index: Int) -> CGRect {
        lineHeightRectValue
    }

    func setMarkedText(
        _ text: String,
        selectionRange: NSRange,
        replacementRange: NSRange
    ) {
        if text.isEmpty {
            markedRange = nil
        } else {
            markedRange = NSRange(location: selectedRange.location, length: (text as NSString).length)
        }
    }

    func insertText(_ text: String, replacementRange: NSRange) {
        insertTextWrites.append(InsertTextWrite(text: text, replacementRange: replacementRange))
    }
}

private struct PerfInputModePreferenceStore: InputModePreferenceStore {
    func loadPreferences() -> InputModePreferences { .standard }
    func savePreferences(_ preferences: InputModePreferences) throws {}
}

private struct PerfRuntimePreferenceStore: InputMethodRuntimePreferenceStore {
    func loadPreferences() -> InputMethodRuntimePreferences { .standard }
    func savePreferences(_ preferences: InputMethodRuntimePreferences) throws {}
}
