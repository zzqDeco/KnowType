import CoreGraphics
import Foundation
import KnowTypeCore

enum CandidatePanelLayoutOrientation: Sendable, Equatable {
    case horizontal
    case vertical
}

public enum CandidatePanelPlacementPreference: String, Sendable, Equatable {
    case automatic
    case preferVisualBelow
    case preferVisualAbove
}

enum CandidatePanelVerticalPlacement: String, Sendable, Equatable {
    case visualBelowCaret
    case visualAboveCaret
}

struct CandidatePanelLayoutInsets: Sendable, Equatable {
    var top: CGFloat
    var left: CGFloat
    var bottom: CGFloat
    var right: CGFloat

    init(top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }

    var horizontal: CGFloat {
        left + right
    }

    var vertical: CGFloat {
        top + bottom
    }
}

struct CandidatePanelLayoutConfiguration: Sendable, Equatable {
    var horizontalMinimumWidth: CGFloat = 220
    var horizontalMaximumWidth: CGFloat = 720
    var verticalMinimumWidth: CGFloat = 220
    var verticalMaximumWidth: CGFloat = 560
    var horizontalRowHeight: CGFloat = 26
    var verticalRowHeight: CGFloat = 26
    var minimumVerticalRowHeight: CGFloat = 20
    var contentInsets = CandidatePanelLayoutInsets(top: 4, left: 5, bottom: 4, right: 5)
    var itemInsets = CandidatePanelLayoutInsets(top: 1, left: 5, bottom: 1, right: 7)
    var horizontalItemSpacing: CGFloat = 2
    var verticalItemSpacing: CGFloat = 2
    var minimumShortcutWidth: CGFloat = 0
    var shortcutTextSpacing: CGFloat = 3
    var accessoryWidth: CGFloat = 12
    var accessoryTextSpacing: CGFloat = 4
    var visibleFrameInset: CGFloat = 8
    var verticalAnchorSpacing: CGFloat = 6
    var minimumHorizontalCandidateCount: Int = 4
    var maximumHorizontalCandidateCount: Int = 6

    init(layoutMode: CandidatePanelLayoutMode = .adaptive) {
        if layoutMode == .verticalPreferred {
            minimumHorizontalCandidateCount = Int.max
            maximumHorizontalCandidateCount = Int.max
        }
    }
}

protocol CandidatePanelTextMeasuring {
    func textWidth(for row: CandidatePanelRenderRow) -> CGFloat
    func shortcutWidth(for label: String) -> CGFloat
}

struct CandidatePanelLayoutItem: Sendable, Equatable {
    var rowIndex: Int
    var frame: CGRect
    var textWidthLimit: CGFloat
    var isTruncated: Bool
    var shortcutLabelWidth: CGFloat

    init(
        rowIndex: Int,
        frame: CGRect,
        textWidthLimit: CGFloat,
        isTruncated: Bool,
        shortcutLabelWidth: CGFloat = 0
    ) {
        self.rowIndex = rowIndex
        self.frame = frame
        self.textWidthLimit = textWidthLimit
        self.isTruncated = isTruncated
        self.shortcutLabelWidth = shortcutLabelWidth
    }
}

struct CandidatePanelLayoutPlan: Sendable, Equatable {
    var orientation: CandidatePanelLayoutOrientation
    var verticalPlacement: CandidatePanelVerticalPlacement
    var panelSize: CGSize
    var panelOrigin: CGPoint
    var contentInsets: CandidatePanelLayoutInsets
    var itemSpacing: CGFloat
    var items: [CandidatePanelLayoutItem]
}

struct CandidatePanelLayoutEngine {
    private struct MeasuredRow {
        var rowIndex: Int
        var row: CandidatePanelRenderRow
        var textWidth: CGFloat
        var shortcutWidth: CGFloat

        var hasShortcut: Bool {
            row.shortcutLabel != nil
        }
    }

    private struct LayoutMeasurement {
        var rows: [MeasuredRow]
        var panelSize: CGSize
        var rowHeight: CGFloat
        var itemSpacing: CGFloat
        var sharedShortcutLabelWidth: CGFloat?
    }

    private struct PlacementOrigin {
        var origin: CGPoint
        var verticalPlacement: CandidatePanelVerticalPlacement
    }

    var configuration: CandidatePanelLayoutConfiguration
    var textMeasurer: CandidatePanelTextMeasuring

    init(
        configuration: CandidatePanelLayoutConfiguration = CandidatePanelLayoutConfiguration(),
        textMeasurer: CandidatePanelTextMeasuring
    ) {
        self.configuration = configuration
        self.textMeasurer = textMeasurer
    }

    func layout(
        model: CandidatePanelRenderModel,
        anchorRect: CGRect,
        screenProvider: ScreenGeometryProviding,
        placementPreference: CandidatePanelPlacementPreference = .automatic
    ) -> CandidatePanelLayoutPlan? {
        guard !model.rows.isEmpty,
              CandidateAnchorValidation.isUsable(anchorRect, screenProvider: screenProvider) else {
            return nil
        }

        let anchor = CandidateAnchorValidation.normalized(anchorRect)
        guard let visibleFrame = screenProvider.screen(containing: anchor)?.visibleFrame else {
            return nil
        }

        let measuredRows = model.rows.enumerated().map { index, row in
            MeasuredRow(
                rowIndex: index,
                row: row,
                textWidth: ceil(textMeasurer.textWidth(for: row)),
                shortcutWidth: row.shortcutLabel.map { ceil(textMeasurer.shortcutWidth(for: $0)) } ?? 0
            )
        }
        let availableWidth = max(0, visibleFrame.width - configuration.visibleFrameInset * 2)
        let availableHeight = max(0, visibleFrame.height - configuration.visibleFrameInset * 2)
        let orientation = orientation(for: measuredRows, availableWidth: availableWidth)
        guard let measurement = measurement(
            for: measuredRows,
            orientation: orientation,
            availableWidth: availableWidth,
            availableHeight: availableHeight
        ) else {
            return nil
        }
        guard let placementOrigin = origin(
            for: anchor,
            panelSize: measurement.panelSize,
            visibleFrame: visibleFrame,
            placementPreference: placementPreference
        ) else {
            return nil
        }
        let items = layoutItems(
            for: measurement.rows,
            orientation: orientation,
            panelSize: measurement.panelSize,
            rowHeight: measurement.rowHeight,
            itemSpacing: measurement.itemSpacing,
            sharedShortcutLabelWidth: measurement.sharedShortcutLabelWidth
        )

        return CandidatePanelLayoutPlan(
            orientation: orientation,
            verticalPlacement: placementOrigin.verticalPlacement,
            panelSize: measurement.panelSize,
            panelOrigin: placementOrigin.origin,
            contentInsets: configuration.contentInsets,
            itemSpacing: measurement.itemSpacing,
            items: items
        )
    }

    private func orientation(
        for rows: [MeasuredRow],
        availableWidth: CGFloat
    ) -> CandidatePanelLayoutOrientation {
        if rows.contains(where: { $0.row.kind == .preedit }) {
            return .vertical
        }
        guard rows.count >= configuration.minimumHorizontalCandidateCount else {
            return .vertical
        }
        guard rows.count <= configuration.maximumHorizontalCandidateCount else {
            return .vertical
        }

        return horizontalNaturalWidth(for: rows) <= horizontalMaximumWidth(availableWidth: availableWidth)
            ? .horizontal
            : .vertical
    }

    private func measurement(
        for rows: [MeasuredRow],
        orientation: CandidatePanelLayoutOrientation,
        availableWidth: CGFloat,
        availableHeight: CGFloat
    ) -> LayoutMeasurement? {
        switch orientation {
        case .horizontal:
            let maximumWidth = horizontalMaximumWidth(availableWidth: availableWidth)
            let height = ceil(configuration.horizontalRowHeight + configuration.contentInsets.vertical)
            guard height <= availableHeight else {
                return nil
            }
            let width = clamp(
                horizontalNaturalWidth(for: rows),
                minimum: min(configuration.horizontalMinimumWidth, maximumWidth),
                maximum: maximumWidth
            )
            return LayoutMeasurement(
                rows: rows,
                panelSize: CGSize(width: ceil(width), height: height),
                rowHeight: configuration.horizontalRowHeight,
                itemSpacing: configuration.horizontalItemSpacing,
                sharedShortcutLabelWidth: nil
            )
        case .vertical:
            guard let metrics = verticalMetrics(
                rowCount: rows.count,
                availableHeight: availableHeight
            ) else {
                return nil
            }
            let maximumWidth = verticalMaximumWidth(availableWidth: availableWidth)
            let sharedShortcutLabelWidth = verticalSharedShortcutLabelWidth(for: rows)
            let width = clamp(
                verticalNaturalWidth(for: rows, sharedShortcutLabelWidth: sharedShortcutLabelWidth),
                minimum: min(configuration.verticalMinimumWidth, maximumWidth),
                maximum: maximumWidth
            )
            return LayoutMeasurement(
                rows: rows,
                panelSize: CGSize(
                    width: ceil(width),
                    height: ceil(metrics.height)
                ),
                rowHeight: metrics.rowHeight,
                itemSpacing: metrics.itemSpacing,
                sharedShortcutLabelWidth: sharedShortcutLabelWidth
            )
        }
    }

    private func verticalMetrics(
        rowCount: Int,
        availableHeight: CGFloat
    ) -> (height: CGFloat, rowHeight: CGFloat, itemSpacing: CGFloat)? {
        guard rowCount > 0 else {
            return nil
        }
        let naturalHeight = verticalHeight(
            rowCount: rowCount,
            rowHeight: configuration.verticalRowHeight,
            itemSpacing: configuration.verticalItemSpacing
        )
        guard naturalHeight > availableHeight else {
            return (
                height: naturalHeight,
                rowHeight: configuration.verticalRowHeight,
                itemSpacing: configuration.verticalItemSpacing
            )
        }

        let availableContentHeight = availableHeight - configuration.contentInsets.vertical
        guard availableContentHeight >= CGFloat(rowCount) * configuration.minimumVerticalRowHeight else {
            return nil
        }

        let gapCount = max(rowCount - 1, 0)
        let itemSpacing = min(
            configuration.verticalItemSpacing,
            gapCount > 0
                ? (availableContentHeight - CGFloat(rowCount) * configuration.minimumVerticalRowHeight) / CGFloat(gapCount)
                : 0
        )
        let rowHeight = max(
            configuration.minimumVerticalRowHeight,
            (availableContentHeight - CGFloat(gapCount) * itemSpacing) / CGFloat(rowCount)
        )
        return (
            height: verticalHeight(rowCount: rowCount, rowHeight: rowHeight, itemSpacing: itemSpacing),
            rowHeight: rowHeight,
            itemSpacing: itemSpacing
        )
    }

    private func verticalHeight(rowCount: Int, rowHeight: CGFloat, itemSpacing: CGFloat) -> CGFloat {
        configuration.contentInsets.vertical
            + CGFloat(rowCount) * rowHeight
            + CGFloat(max(rowCount - 1, 0)) * itemSpacing
    }

    private func layoutItems(
        for rows: [MeasuredRow],
        orientation: CandidatePanelLayoutOrientation,
        panelSize: CGSize,
        rowHeight: CGFloat,
        itemSpacing: CGFloat,
        sharedShortcutLabelWidth: CGFloat?
    ) -> [CandidatePanelLayoutItem] {
        switch orientation {
        case .horizontal:
            return horizontalItems(for: rows, panelSize: panelSize, rowHeight: rowHeight)
        case .vertical:
            return verticalItems(
                for: rows,
                panelSize: panelSize,
                rowHeight: rowHeight,
                itemSpacing: itemSpacing,
                sharedShortcutLabelWidth: sharedShortcutLabelWidth
            )
        }
    }

    private func horizontalItems(
        for rows: [MeasuredRow],
        panelSize: CGSize,
        rowHeight: CGFloat
    ) -> [CandidatePanelLayoutItem] {
        var x = configuration.contentInsets.left
        return rows.map { row in
            let shortcutLabelWidth = shortcutLabelWidth(for: row, sharedShortcutLabelWidth: nil)
            let width = naturalItemWidth(for: row, shortcutLabelWidth: shortcutLabelWidth)
            let frame = CGRect(
                x: x,
                y: configuration.contentInsets.top,
                width: width,
                height: rowHeight
            )
            x += width + configuration.horizontalItemSpacing
            let textLimit = textWidthLimit(for: row, itemWidth: width, shortcutLabelWidth: shortcutLabelWidth)
            return CandidatePanelLayoutItem(
                rowIndex: row.rowIndex,
                frame: frame,
                textWidthLimit: textLimit,
                isTruncated: row.textWidth > textLimit,
                shortcutLabelWidth: shortcutLabelWidth
            )
        }
    }

    private func verticalItems(
        for rows: [MeasuredRow],
        panelSize: CGSize,
        rowHeight: CGFloat,
        itemSpacing: CGFloat,
        sharedShortcutLabelWidth: CGFloat?
    ) -> [CandidatePanelLayoutItem] {
        let width = max(0, panelSize.width - configuration.contentInsets.horizontal)
        var y = configuration.contentInsets.top
        return rows.map { row in
            let shortcutLabelWidth = shortcutLabelWidth(
                for: row,
                sharedShortcutLabelWidth: sharedShortcutLabelWidth
            )
            let frame = CGRect(
                x: configuration.contentInsets.left,
                y: y,
                width: width,
                height: rowHeight
            )
            y += rowHeight + itemSpacing
            let textLimit = textWidthLimit(
                for: row,
                itemWidth: width,
                shortcutLabelWidth: shortcutLabelWidth
            )
            return CandidatePanelLayoutItem(
                rowIndex: row.rowIndex,
                frame: frame,
                textWidthLimit: textLimit,
                isTruncated: row.textWidth > textLimit,
                shortcutLabelWidth: shortcutLabelWidth
            )
        }
    }

    private func origin(
        for anchor: CGRect,
        panelSize: CGSize,
        visibleFrame: CGRect,
        placementPreference: CandidatePanelPlacementPreference
    ) -> PlacementOrigin? {
        guard panelSize.width > 0,
              panelSize.height > 0 else {
            return nil
        }

        let minX = visibleFrame.minX + configuration.visibleFrameInset
        let maxX = visibleFrame.maxX - panelSize.width - configuration.visibleFrameInset
        let minY = visibleFrame.minY + configuration.visibleFrameInset
        let maxY = visibleFrame.maxY - panelSize.height - configuration.visibleFrameInset
        let visualBelowY = anchor.minY - panelSize.height - configuration.verticalAnchorSpacing
        let visualAboveY = anchor.maxY + configuration.verticalAnchorSpacing
        let verticalOrder: [CandidatePanelVerticalPlacement] = switch placementPreference {
        case .automatic, .preferVisualBelow:
            [.visualBelowCaret, .visualAboveCaret]
        case .preferVisualAbove:
            [.visualAboveCaret, .visualBelowCaret]
        }
        let chosenPlacement = verticalOrder.first { placement in
            let y = proposedY(for: placement, visualBelowY: visualBelowY, visualAboveY: visualAboveY)
            return y >= minY && y <= maxY
        } ?? verticalOrder[0]
        let chosenY = proposedY(
            for: chosenPlacement,
            visualBelowY: visualBelowY,
            visualAboveY: visualAboveY
        )

        return PlacementOrigin(
            origin: CGPoint(
                x: clamp(anchor.minX, minimum: minX, maximum: maxX),
                y: clamp(chosenY, minimum: minY, maximum: maxY)
            ),
            verticalPlacement: chosenPlacement
        )
    }

    private func proposedY(
        for placement: CandidatePanelVerticalPlacement,
        visualBelowY: CGFloat,
        visualAboveY: CGFloat
    ) -> CGFloat {
        switch placement {
        case .visualBelowCaret:
            visualBelowY
        case .visualAboveCaret:
            visualAboveY
        }
    }

    private func horizontalNaturalWidth(for rows: [MeasuredRow]) -> CGFloat {
        let rowWidth = rows.reduce(CGFloat(0)) { partial, row in
            partial + naturalItemWidth(
                for: row,
                shortcutLabelWidth: shortcutLabelWidth(for: row, sharedShortcutLabelWidth: nil)
            )
        }
        let spacing = CGFloat(max(rows.count - 1, 0)) * configuration.horizontalItemSpacing
        return configuration.contentInsets.horizontal + rowWidth + spacing
    }

    private func verticalNaturalWidth(
        for rows: [MeasuredRow],
        sharedShortcutLabelWidth: CGFloat?
    ) -> CGFloat {
        let itemWidth = rows.map { row in
            naturalItemWidth(
                for: row,
                shortcutLabelWidth: shortcutLabelWidth(
                    for: row,
                    sharedShortcutLabelWidth: sharedShortcutLabelWidth
                )
            )
        }.max() ?? 0
        return configuration.contentInsets.horizontal + itemWidth
    }

    private func naturalItemWidth(for row: MeasuredRow, shortcutLabelWidth: CGFloat) -> CGFloat {
        configuration.itemInsets.horizontal
            + shortcutSlotWidth(shortcutLabelWidth: shortcutLabelWidth)
            + accessorySlotWidth(for: row)
            + row.textWidth
    }

    private func textWidthLimit(
        for row: MeasuredRow,
        itemWidth: CGFloat,
        shortcutLabelWidth: CGFloat
    ) -> CGFloat {
        max(
            0,
            itemWidth
                - configuration.itemInsets.horizontal
                - shortcutSlotWidth(shortcutLabelWidth: shortcutLabelWidth)
                - accessorySlotWidth(for: row)
        )
    }

    private func verticalSharedShortcutLabelWidth(for rows: [MeasuredRow]) -> CGFloat? {
        rows
            .filter(\.hasShortcut)
            .map { max(configuration.minimumShortcutWidth, $0.shortcutWidth) }
            .max()
    }

    private func shortcutLabelWidth(
        for row: MeasuredRow,
        sharedShortcutLabelWidth: CGFloat?
    ) -> CGFloat {
        guard row.hasShortcut else {
            return 0
        }
        return max(configuration.minimumShortcutWidth, sharedShortcutLabelWidth ?? row.shortcutWidth)
    }

    private func shortcutSlotWidth(shortcutLabelWidth: CGFloat) -> CGFloat {
        guard shortcutLabelWidth > 0 else {
            return 0
        }
        return shortcutLabelWidth + configuration.shortcutTextSpacing
    }

    private func accessorySlotWidth(for row: MeasuredRow) -> CGFloat {
        guard row.row.accessory != nil else {
            return 0
        }
        return configuration.accessoryWidth + configuration.accessoryTextSpacing
    }

    private func horizontalMaximumWidth(availableWidth: CGFloat) -> CGFloat {
        max(0, min(configuration.horizontalMaximumWidth, availableWidth))
    }

    private func verticalMaximumWidth(availableWidth: CGFloat) -> CGFloat {
        max(0, min(configuration.verticalMaximumWidth, availableWidth))
    }

    private func clamp(_ value: CGFloat, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
        guard maximum >= minimum else {
            return minimum
        }
        return min(max(value, minimum), maximum)
    }
}
