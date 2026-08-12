import CoreGraphics

enum SelectorMetrics {
    static let panelSize = CGSize(width: 425, height: 200)
    static let outerRadius: CGFloat = 15
    static let outerInset: CGFloat = 7
    static let outerTrailingInset: CGFloat = 6
    static let headerHeight: CGFloat = 40
    static let headerGap: CGFloat = 5
    static let sourceWidth: CGFloat = 75
    static let cancelWidth: CGFloat = 79
    static let viewportSize = CGSize(width: 412, height: 142)
    static let viewportLeadingInset: CGFloat = 6
    static let viewportTrailingInset: CGFloat = 6
    static let fixedItemWidth: CGFloat = 130
    static let fixedItemGap: CGFloat = 5
    static let scrollingItemGap: CGFloat = 8
    static let itemHeight: CGFloat = 130
    static let recoveryStatusHeight: CGFloat = 29
    static let recoveryStripHeight: CGFloat = viewportSize.height - recoveryStatusHeight
    static let recoveryItemHeight: CGFloat = recoveryStripHeight - 12
    static let cardRadius: CGFloat = 10
    static let iconSize: CGFloat = 45
    static let compactIconSize: CGFloat = 40
    static let recoveryIconSize: CGFloat = 32
    static let shortcutSize: CGFloat = 20

    static var headerURLWidth: CGFloat {
        panelSize.width
            - outerInset
            - outerTrailingInset
            - sourceWidth
            - cancelWidth
            - 2 * headerGap
    }

    static func itemWidth(browserCount: Int) -> CGFloat {
        guard browserCount > 3 else { return fixedItemWidth }
        return (viewportSize.width - viewportLeadingInset - 3 * scrollingItemGap) / 3.5
    }

    static func itemGap(browserCount: Int) -> CGFloat {
        browserCount > 3 ? scrollingItemGap : fixedItemGap
    }

    static func browserCenterX(index: Int, browserCount: Int) -> CGFloat {
        let width = itemWidth(browserCount: browserCount)
        return viewportLeadingInset + CGFloat(index) * (width + itemGap(browserCount: browserCount)) + width / 2
    }

    static func contentWidth(browserCount: Int) -> CGFloat {
        guard browserCount > 0 else { return viewportSize.width }
        let itemsWidth = CGFloat(browserCount) * itemWidth(browserCount: browserCount)
        let gapsWidth = CGFloat(max(browserCount - 1, 0)) * itemGap(browserCount: browserCount)
        return max(
            viewportSize.width,
            viewportLeadingInset + itemsWidth + gapsWidth + viewportTrailingInset
        )
    }

    static func maxOffset(browserCount: Int) -> CGFloat {
        max(0, contentWidth(browserCount: browserCount) - viewportSize.width)
    }

    static func clampedOffset(_ value: CGFloat, browserCount: Int) -> CGFloat {
        min(max(value, 0), maxOffset(browserCount: browserCount))
    }

    static func revealOffset(
        browserIndex: Int,
        browserCount: Int,
        currentOffset: CGFloat
    ) -> CGFloat {
        guard browserCount > 0, (0 ..< browserCount).contains(browserIndex) else {
            return clampedOffset(currentOffset, browserCount: browserCount)
        }
        let width = itemWidth(browserCount: browserCount)
        let minX = viewportLeadingInset
            + CGFloat(browserIndex) * (width + itemGap(browserCount: browserCount))
        let maxX = minX + width
        let visibleMinX = clampedOffset(currentOffset, browserCount: browserCount)
        let visibleMaxX = visibleMinX + viewportSize.width
        if minX < visibleMinX {
            return clampedOffset(minX, browserCount: browserCount)
        }
        if maxX > visibleMaxX {
            return clampedOffset(maxX - viewportSize.width, browserCount: browserCount)
        }
        return visibleMinX
    }
}
