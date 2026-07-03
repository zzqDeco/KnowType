import Foundation
import XCTest

final class AIDebugLogSummaryScriptTests: XCTestCase {
    func testSummarizesCancellationFixtureWithoutLeakingUserText() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let output = try runSummary(
            rootURL: rootURL,
            fixture: rootURL.appendingPathComponent("Tests/Fixtures/ai-debug-cancellation.log")
        )

        XCTAssertTrue(output.contains("transport_started=2"), output)
        XCTAssertTrue(output.contains("transport_cancellation_requested=2"), output)
        XCTAssertTrue(output.contains("transport_cancelled_by_new_input=1"), output)
        XCTAssertTrue(output.contains("provider_error=1 timeout=1 unavailable=0"), output)
        XCTAssertTrue(output.contains("handleKeyTotalMs: count=4 min=5.00 p50=10.00 p90=40.00 p95=40.00 max=40.00"), output)

        for sensitive in ["woxiang", "SECRET_PROMPT", "sk-test", "候选", "输出"] {
            XCTAssertFalse(output.contains(sensitive), "summary leaked \(sensitive): \(output)")
        }
    }

    func testEmptyLogSucceedsWithZeroEvents() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let emptyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("knowtype-empty-ai-log-\(UUID().uuidString).log")
        try Data().write(to: emptyURL)
        defer { try? FileManager.default.removeItem(at: emptyURL) }

        let output = try runSummary(rootURL: rootURL, fixture: emptyURL)

        XCTAssertTrue(output.contains("aiEvents=0"), output)
        XCTAssertTrue(output.contains("handleKeyTotalMs: count=0"), output)
        XCTAssertTrue(output.contains("transportSamples:\n  none"), output)
    }

    func testMissingLogFileFailsClearly() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("knowtype-missing-ai-log-\(UUID().uuidString).log")

        let result = try runSummaryProcess(rootURL: rootURL, fixture: missingURL)

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.stderr.contains("log file does not exist"), result.stderr)
    }

    private func runSummary(rootURL: URL, fixture: URL) throws -> String {
        let result = try runSummaryProcess(rootURL: rootURL, fixture: fixture)
        XCTAssertEqual(result.status, 0, result.stderr)
        return result.stdout
    }

    private func runSummaryProcess(rootURL: URL, fixture: URL) throws -> (
        status: Int32,
        stdout: String,
        stderr: String
    ) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [
            rootURL.appendingPathComponent("scripts/summarize-ai-debug-log.py").path,
            fixture.path
        ]
        process.environment = [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"
        ]

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        try process.run()
        process.waitUntilExit()

        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = error.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: outputData, encoding: .utf8) ?? ""
        let stderr = String(data: errorData, encoding: .utf8) ?? ""
        return (process.terminationStatus, stdout, stderr)
    }
}
