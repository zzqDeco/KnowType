import Foundation
import KnowTypeCore
import XCTest

final class InputDebugDiagnosticsTests: XCTestCase {
    func testPerfDebugEnablesAllDiagnosticCategories() {
        let environment = ["KNOWTYPE_PERF_DEBUG": "1"]

        for category in [
            InputDebugDiagnostics.Category.ai,
            .anchor,
            .clientWrite,
            .inputLatency,
            .panel,
            .performance,
            .rime,
            .startup,
            .turn
        ] {
            XCTAssertTrue(
                InputDebugDiagnostics.isEnabled(category, environment: environment),
                "\(category.rawValue) should be enabled by KNOWTYPE_PERF_DEBUG"
            )
        }
    }

    func testSingleDebugEnvironmentOnlyEnablesMatchingCategory() {
        let environment = ["KNOWTYPE_AI_DEBUG": "1"]

        XCTAssertTrue(InputDebugDiagnostics.isEnabled(.ai, environment: environment))
        XCTAssertFalse(InputDebugDiagnostics.isEnabled(.panel, environment: environment))
        XCTAssertFalse(InputDebugDiagnostics.isEnabled(.turn, environment: environment))
    }

    func testLatencyBudgetOnlyEmitsOverBudgetWithoutPerfDebug() {
        XCTAssertFalse(
            InputDebugDiagnostics.shouldEmitLatency(
                elapsedMilliseconds: 4,
                budgetMilliseconds: 8,
                environment: ["KNOWTYPE_INPUT_LATENCY_DEBUG": "1"]
            )
        )
        XCTAssertTrue(
            InputDebugDiagnostics.shouldEmitLatency(
                elapsedMilliseconds: 12,
                budgetMilliseconds: 8,
                environment: ["KNOWTYPE_INPUT_LATENCY_DEBUG": "1"]
            )
        )
    }

    func testPerfDebugEmitsLatencyBelowBudget() {
        XCTAssertTrue(
            InputDebugDiagnostics.shouldEmitLatency(
                elapsedMilliseconds: 1,
                budgetMilliseconds: 8,
                environment: ["KNOWTYPE_PERF_DEBUG": "1"]
            )
        )
    }

    func testEmitUsesStableKeyValueFormatAndSanitizesWhitespace() {
        let output = DiagnosticOutputBox()
        let emitted = InputDebugDiagnostics.emit(
            category: .panel,
            fields: [
                .init(.stage, "window apply"),
                .init(.panelGeneration, 3),
                .init(.reason, "layout impossible"),
                .init(.handled, false)
            ],
            environment: ["KNOWTYPE_PANEL_DEBUG": "1"],
            stderrSink: { output.append($0) }
        )

        XCTAssertTrue(emitted)
        XCTAssertEqual(
            output.value,
            "KnowType debug: category=panel stage=window_apply panelGeneration=3 reason=layout_impossible handled=false\n"
        )
    }

    func testTraceDoesNotEmitBelowLatencyBudget() {
        let output = DiagnosticOutputBox()
        let value = InputDebugDiagnostics.trace(
            category: .inputLatency,
            stage: "short_stage",
            budgetMilliseconds: 60_000,
            environment: ["KNOWTYPE_INPUT_LATENCY_DEBUG": "1"],
            stderrSink: { output.append($0) }
        ) {
            42
        }

        XCTAssertEqual(value, 42)
        XCTAssertEqual(output.value, "")
    }

    func testTraceEmitsWhenPerfDebugIsEnabled() {
        let output = DiagnosticOutputBox()
        let value = InputDebugDiagnostics.trace(
            category: .inputLatency,
            stage: "short_stage",
            budgetMilliseconds: 60_000,
            environment: ["KNOWTYPE_PERF_DEBUG": "1"],
            stderrSink: { output.append($0) }
        ) {
            42
        }

        XCTAssertEqual(value, 42)
        XCTAssertTrue(output.value.contains("category=input_latency"))
        XCTAssertTrue(output.value.contains("stage=short_stage"))
        XCTAssertTrue(output.value.contains("elapsedMs="))
        XCTAssertTrue(output.value.contains("budgetMs=60000.00"))
    }

    func testTurnTraceEmitsWhenTurnDebugIsEnabled() {
        let output = DiagnosticOutputBox()
        let value = InputDebugDiagnostics.trace(
            category: .turn,
            stage: "turn_effect.insert_text",
            environment: ["KNOWTYPE_TURN_DEBUG": "1"],
            stderrSink: { output.append($0) }
        ) {
            42
        }

        XCTAssertEqual(value, 42)
        XCTAssertTrue(output.value.contains("category=turn"))
        XCTAssertTrue(output.value.contains("stage=turn_effect.insert_text"))
        XCTAssertTrue(output.value.contains("elapsedMs="))
        XCTAssertFalse(output.value.contains("budgetMs="))
    }

    func testFormattedDiagnosticsDoNotContainSensitivePayloadsWhenCallersUseAllowedMetadata() {
        let line = InputDebugDiagnostics.formatLine(
            category: .ai,
            fields: [
                .init(.stage, "transport_started"),
                .init(.requestID, "request-1"),
                .init(.rawLength, 18),
                .init(.rawRevision, 7),
                .init(.provider, "spark"),
                .init(.reason, "waiting_for_stable_input")
            ]
        )

        XCTAssertFalse(line.contains("nihao"))
        XCTAssertFalse(line.contains("候选"))
        XCTAssertFalse(line.contains("committed text"))
        XCTAssertFalse(line.contains("sk-"))
    }

    func testAnchorDiagnosticsExposeProbeMetadataWithoutUserText() {
        let line = InputDebugDiagnostics.formatLine(
            category: .anchor,
            fields: [
                .init(.stage, "rejected"),
                .init(.anchorSource, "lineHeightRect"),
                .init(.probeCount, 7),
                .init(.reason, "offscreen")
            ]
        )

        XCTAssertTrue(line.contains("anchorSource=lineHeightRect"))
        XCTAssertTrue(line.contains("probeCount=7"))
        XCTAssertTrue(line.contains("reason=offscreen"))
        XCTAssertFalse(line.contains("malicious-user-text"))
    }
}

private final class DiagnosticOutputBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = ""

    var value: String {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ line: String) {
        lock.lock()
        storage += line
        lock.unlock()
    }
}
