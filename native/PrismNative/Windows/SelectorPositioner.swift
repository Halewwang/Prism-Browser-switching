import Foundation

struct SelectorPositioner: Sendable {
    private let pointerSpacing: CGFloat

    init(pointerSpacing: CGFloat = 12) {
        self.pointerSpacing = pointerSpacing
    }

    func origin(
        panelSize: CGSize,
        pointer: CGPoint,
        visibleFrames: [CGRect]
    ) -> CGPoint {
        let proposed = CGPoint(
            x: pointer.x + pointerSpacing,
            y: pointer.y - panelSize.height - pointerSpacing
        )
        guard let visibleFrame = selectedFrame(for: pointer, from: visibleFrames) else {
            return proposed
        }

        return CGPoint(
            x: clamped(
                proposed.x,
                lowerBound: visibleFrame.minX,
                availableLength: visibleFrame.width,
                panelLength: panelSize.width
            ),
            y: clamped(
                proposed.y,
                lowerBound: visibleFrame.minY,
                availableLength: visibleFrame.height,
                panelLength: panelSize.height
            )
        )
    }

    private func selectedFrame(for pointer: CGPoint, from frames: [CGRect]) -> CGRect? {
        if let containing = frames.first(where: { $0.contains(pointer) }) {
            return containing
        }

        return frames.enumerated().min { lhs, rhs in
            let leftDistance = squaredDistance(from: pointer, to: lhs.element)
            let rightDistance = squaredDistance(from: pointer, to: rhs.element)
            if leftDistance == rightDistance {
                return lhs.offset < rhs.offset
            }
            return leftDistance < rightDistance
        }?.element
    }

    private func squaredDistance(from point: CGPoint, to frame: CGRect) -> CGFloat {
        let dx: CGFloat
        if point.x < frame.minX {
            dx = frame.minX - point.x
        } else if point.x > frame.maxX {
            dx = point.x - frame.maxX
        } else {
            dx = 0
        }

        let dy: CGFloat
        if point.y < frame.minY {
            dy = frame.minY - point.y
        } else if point.y > frame.maxY {
            dy = point.y - frame.maxY
        } else {
            dy = 0
        }

        return dx * dx + dy * dy
    }

    private func clamped(
        _ value: CGFloat,
        lowerBound: CGFloat,
        availableLength: CGFloat,
        panelLength: CGFloat
    ) -> CGFloat {
        guard panelLength <= availableLength else { return lowerBound }
        let upperBound = lowerBound + availableLength - panelLength
        return min(max(value, lowerBound), upperBound)
    }
}
