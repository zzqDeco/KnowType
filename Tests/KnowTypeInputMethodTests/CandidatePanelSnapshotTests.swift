#if canImport(AppKit)
import AppKit
import KnowTypeCore
import XCTest
@testable import KnowTypeInputMethod

@MainActor
final class CandidatePanelSnapshotTests: XCTestCase {
    func testLightHorizontalCandidatePanelMatchesBaseline() throws {
        try assertSnapshot(
            name: "candidate-panel-light-horizontal",
            model: lightHorizontalModel(),
            appearance: .snapshotLight,
            layoutMode: .adaptive
        )
    }

    func testDarkVerticalCandidatePanelMatchesBaseline() throws {
        try assertSnapshot(
            name: "candidate-panel-dark-vertical",
            model: darkVerticalModel(),
            appearance: .snapshotDark,
            layoutMode: .verticalPreferred
        )
    }

    func testAIStatusCandidatePanelMatchesBaseline() throws {
        try assertSnapshot(
            name: "candidate-panel-ai-status",
            model: aiStatusModel(),
            appearance: .snapshotLight,
            layoutMode: .adaptive
        )
    }

    private func assertSnapshot(
        name: String,
        model: CandidatePanelRenderModel,
        appearance: CandidatePanelAppearance,
        layoutMode: CandidatePanelLayoutMode,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let layoutPlan = try XCTUnwrap(
            CandidatePanelLayoutEngine(
                configuration: appearance.layoutConfiguration(layoutMode: layoutMode),
                textMeasurer: SnapshotCandidatePanelTextMeasurer()
            ).layout(
                model: model,
                anchorRect: CGRect(x: 60, y: 260, width: 0, height: 18),
                screenProvider: SnapshotScreenProvider()
            ),
            "Snapshot layout should be available",
            file: file,
            line: line
        )
        let pngData = try renderPNG(model: model, layoutPlan: layoutPlan, appearance: appearance)
        let baselineURL = snapshotDirectory.appendingPathComponent("\(name).png")

        if ProcessInfo.processInfo.environment["KNOWTYPE_RECORD_SNAPSHOTS"] == "1" {
            try FileManager.default.createDirectory(at: snapshotDirectory, withIntermediateDirectories: true)
            try pngData.write(to: baselineURL)
            return
        }

        guard FileManager.default.fileExists(atPath: baselineURL.path) else {
            XCTFail(
                "Missing snapshot baseline \(baselineURL.path). Re-run with KNOWTYPE_RECORD_SNAPSHOTS=1.",
                file: file,
                line: line
            )
            return
        }

        let expectedData = try Data(contentsOf: baselineURL)
        if expectedData == pngData {
            return
        }
        guard let expected = NSBitmapImageRep(data: expectedData),
              let actual = NSBitmapImageRep(data: pngData) else {
            XCTFail("Snapshot PNG decoding failed for \(name)", file: file, line: line)
            return
        }
        let comparison = compare(expected: expected, actual: actual)
        if comparison.isAcceptable {
            return
        }

        try writeMismatchArtifacts(name: name, actualData: pngData, expected: expected, actual: actual)
        XCTFail(
            """
            Snapshot \(name) differs: \(comparison.mismatchedPixels) changed pixels, \
            \(comparison.largeDeltaPixels) large-delta pixels, max channel delta \
            \(comparison.maxChannelDelta), average delta \(String(format: "%.2f", comparison.averageChannelDelta)). \
            Artifacts: \(mismatchDirectory.path)
            """,
            file: file,
            line: line
        )
    }

    private func renderPNG(
        model: CandidatePanelRenderModel,
        layoutPlan: CandidatePanelLayoutPlan,
        appearance: CandidatePanelAppearance
    ) throws -> Data {
        let view = CandidatePanelContentView(
            frame: NSRect(origin: .zero, size: layoutPlan.panelSize),
            appearance: appearance
        )
        view.update(model: model, layoutPlan: layoutPlan)
        view.setFrameSize(layoutPlan.panelSize)
        view.layoutSubtreeIfNeeded()

        let pixelWidth = Int(ceil(layoutPlan.panelSize.width))
        let pixelHeight = Int(ceil(layoutPlan.panelSize.height))
        let rep = try XCTUnwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: pixelWidth,
                pixelsHigh: pixelHeight,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        )
        rep.size = layoutPlan.panelSize
        view.cacheDisplay(in: view.bounds, to: rep)
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }

    private func compare(expected: NSBitmapImageRep, actual: NSBitmapImageRep) -> SnapshotComparison {
        guard expected.pixelsWide == actual.pixelsWide,
              expected.pixelsHigh == actual.pixelsHigh else {
            return SnapshotComparison(
                mismatchedPixels: Int.max,
                maxChannelDelta: Int.max,
                totalPixels: max(expected.pixelsWide * expected.pixelsHigh, actual.pixelsWide * actual.pixelsHigh)
            )
        }

        var mismatchedPixels = 0
        var largeDeltaPixels = 0
        var maxChannelDelta = 0
        var totalChannelDelta = 0
        for y in 0..<expected.pixelsHigh {
            for x in 0..<expected.pixelsWide {
                let expectedRGBA = rgba(expected.colorAt(x: x, y: y))
                let actualRGBA = rgba(actual.colorAt(x: x, y: y))
                let deltas = [
                    abs(expectedRGBA.red - actualRGBA.red),
                    abs(expectedRGBA.green - actualRGBA.green),
                    abs(expectedRGBA.blue - actualRGBA.blue),
                    abs(expectedRGBA.alpha - actualRGBA.alpha)
                ]
                let pixelMaxDelta = deltas.max() ?? 0
                maxChannelDelta = max(maxChannelDelta, pixelMaxDelta)
                totalChannelDelta += pixelMaxDelta
                if pixelMaxDelta > 12 {
                    mismatchedPixels += 1
                }
                if pixelMaxDelta > 64 {
                    largeDeltaPixels += 1
                }
            }
        }
        return SnapshotComparison(
            mismatchedPixels: mismatchedPixels,
            largeDeltaPixels: largeDeltaPixels,
            maxChannelDelta: maxChannelDelta,
            totalChannelDelta: totalChannelDelta,
            totalPixels: expected.pixelsWide * expected.pixelsHigh
        )
    }

    private func writeMismatchArtifacts(
        name: String,
        actualData: Data,
        expected: NSBitmapImageRep,
        actual: NSBitmapImageRep
    ) throws {
        try FileManager.default.createDirectory(at: mismatchDirectory, withIntermediateDirectories: true)
        try actualData.write(to: mismatchDirectory.appendingPathComponent("\(name)-actual.png"))
        guard let diffData = diffPNG(expected: expected, actual: actual) else {
            return
        }
        try diffData.write(to: mismatchDirectory.appendingPathComponent("\(name)-diff.png"))
    }

    private func diffPNG(expected: NSBitmapImageRep, actual: NSBitmapImageRep) -> Data? {
        guard expected.pixelsWide == actual.pixelsWide,
              expected.pixelsHigh == actual.pixelsHigh,
              let diff = NSBitmapImageRep(
                  bitmapDataPlanes: nil,
                  pixelsWide: expected.pixelsWide,
                  pixelsHigh: expected.pixelsHigh,
                  bitsPerSample: 8,
                  samplesPerPixel: 4,
                  hasAlpha: true,
                  isPlanar: false,
                  colorSpaceName: .deviceRGB,
                  bytesPerRow: 0,
                  bitsPerPixel: 0
              ) else {
            return nil
        }

        for y in 0..<expected.pixelsHigh {
            for x in 0..<expected.pixelsWide {
                let expectedRGBA = rgba(expected.colorAt(x: x, y: y))
                let actualRGBA = rgba(actual.colorAt(x: x, y: y))
                let delta = max(
                    abs(expectedRGBA.red - actualRGBA.red),
                    abs(expectedRGBA.green - actualRGBA.green),
                    abs(expectedRGBA.blue - actualRGBA.blue),
                    abs(expectedRGBA.alpha - actualRGBA.alpha)
                )
                diff.setColor(delta > 12 ? .systemRed : .clear, atX: x, y: y)
            }
        }
        return diff.representation(using: .png, properties: [:])
    }

    private func rgba(_ color: NSColor?) -> (red: Int, green: Int, blue: Int, alpha: Int) {
        guard let color = color?.usingColorSpace(.deviceRGB) else {
            return (0, 0, 0, 0)
        }
        return (
            Int((color.redComponent * 255).rounded()),
            Int((color.greenComponent * 255).rounded()),
            Int((color.blueComponent * 255).rounded()),
            Int((color.alphaComponent * 255).rounded())
        )
    }

    private var snapshotDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("__Snapshots__", isDirectory: true)
    }

    private var mismatchDirectory: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("KnowTypeCandidatePanelSnapshotDiffs", isDirectory: true)
    }

    private func lightHorizontalModel() -> CandidatePanelRenderModel {
        CandidatePanelRenderModel(
            title: "KnowType",
            previewText: nil,
            rows: [
                row(.prefixCandidate, selection: .prefixCandidate(0), shortcut: "1", text: "方案一", selected: true, role: .lockedPrefix),
                row(.aiRecommendation, selection: .aiRecommendation, shortcut: "2", text: "AI 建议", role: .aiRecommendation),
                row(.prefixCandidate, selection: .prefixCandidate(1), shortcut: "3", text: "方案二", role: .lockedPrefix),
                row(.continuationCandidate, selection: .continuationCandidate(0), shortcut: "⇥", text: "继续", role: .continuation)
            ]
        )
    }

    private func darkVerticalModel() -> CandidatePanelRenderModel {
        CandidatePanelRenderModel(
            title: "KnowType",
            previewText: nil,
            rows: [
                row(.prefixCandidate, selection: .prefixCandidate(0), shortcut: "1", text: "先做最小实现", selected: true, role: .lockedPrefix),
                row(.aiRecommendation, selection: .aiRecommendation, shortcut: "2", text: "AI 推荐句", role: .aiRecommendation),
                row(.prefixCandidate, selection: .prefixCandidate(1), shortcut: "3", text: "完整方案", role: .lockedPrefix),
                row(.prefixCandidate, selection: .prefixCandidate(2), shortcut: "4", text: "风险评估", role: .lockedPrefix),
                row(.continuationCandidate, selection: .continuationCandidate(0), shortcut: "⇥", text: "继续推进", role: .continuation)
            ]
        )
    }

    private func aiStatusModel() -> CandidatePanelRenderModel {
        CandidatePanelRenderModel(
            title: "KnowType",
            previewText: nil,
            rows: [
                row(.prefixCandidate, selection: .prefixCandidate(0), shortcut: "1", text: "这个交互", selected: true, role: .lockedPrefix),
                CandidatePanelRenderRow(
                    kind: .aiRecommendation,
                    selection: nil,
                    shortcutLabel: nil,
                    text: "",
                    isSelected: false,
                    isEnabled: false,
                    visualRole: .aiRecommendation,
                    accessory: .spinner,
                    accessibilityLabel: "AI 状态，AI 推荐中"
                ),
                row(.prefixCandidate, selection: .prefixCandidate(1), shortcut: "2", text: "这个界面", role: .lockedPrefix)
            ]
        )
    }

    private func row(
        _ kind: CandidatePanelRowKind,
        selection: CandidatePanelSelection?,
        shortcut: String?,
        text: String,
        selected: Bool = false,
        enabled: Bool = true,
        role: CandidatePanelVisualRole
    ) -> CandidatePanelRenderRow {
        CandidatePanelRenderRow(
            kind: kind,
            selection: selection,
            shortcutLabel: shortcut,
            text: text,
            isSelected: selected,
            isEnabled: enabled,
            visualRole: role
        )
    }
}

private struct SnapshotComparison {
    var mismatchedPixels: Int
    var largeDeltaPixels: Int = 0
    var maxChannelDelta: Int
    var totalChannelDelta: Int = 0
    var totalPixels: Int

    var averageChannelDelta: Double {
        guard totalPixels > 0 else {
            return 0
        }
        return Double(totalChannelDelta) / Double(totalPixels)
    }

    var isAcceptable: Bool {
        mismatchedPixels <= max(8, totalPixels / 5)
            && largeDeltaPixels <= max(4, totalPixels / 50)
            && maxChannelDelta <= 180
            && averageChannelDelta <= 8
    }
}

private struct SnapshotCandidatePanelTextMeasurer: CandidatePanelTextMeasuring {
    func textWidth(for row: CandidatePanelRenderRow) -> CGFloat {
        switch row.visualRole {
        case .lockedPrefix:
            return min(CGFloat(row.text.count) * 16, 210)
        case .aiRecommendation:
            return min(CGFloat(row.text.count) * 15, 290)
        case .continuation:
            return min(CGFloat(row.text.count) * 15, 230)
        case .rawInput:
            return min(CGFloat(row.text.count) * 10, 180)
        }
    }

    func shortcutWidth(for label: String) -> CGFloat {
        CGFloat(label.count) * 7
    }
}

private struct SnapshotScreenProvider: ScreenGeometryProviding {
    var screens: [CandidateAnchorScreen] = [
        CandidateAnchorScreen(
            identifier: "snapshot",
            frame: CGRect(x: 0, y: 0, width: 900, height: 600),
            visibleFrame: CGRect(x: 0, y: 0, width: 900, height: 600)
        )
    ]
}
#endif
