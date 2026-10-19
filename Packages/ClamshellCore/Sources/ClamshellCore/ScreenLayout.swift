// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics

/// How the device is being held, as far as screen placement is concerned.
public enum ScreenPosture: Sendable, Equatable {
    /// Half-folded: top screen on one side of the fold, touch screen on the other.
    /// `fold` is the fold's reserved region in container coordinates; a fold wider than it
    /// is tall splits top/bottom, otherwise left/right.
    case clamshell(fold: CGRect)
    /// Both screens in one stack (fully open in portrait, closed/cover display, iPad).
    case stacked
    /// Both screens next to each other (fully open in landscape, wide windows).
    case sideBySide
}

/// Where the two emulated screens are drawn, and how touches map onto the touch screen.
/// All rects are in the container's coordinate space (points).
public struct ScreenLayout: Sendable, Equatable {
    public static let screenWidth: CGFloat = 256
    public static let screenHeight: CGFloat = 192

    public var top: CGRect
    public var bottom: CGRect

    public init(top: CGRect, bottom: CGRect) {
        self.top = top
        self.bottom = bottom
    }

    /// - Parameters:
    ///   - displayScale: pixels per point; screens snap to whole multiples of the emulated
    ///     resolution in pixels when they are at least 1:1, for crisp nearest-neighbour scaling.
    ///   - spacing: minimum gap between the screens (and between each screen and the fold).
    public init(container: CGRect, posture: ScreenPosture, displayScale: CGFloat = 1, spacing: CGFloat = 8) {
        let (topRegion, bottomRegion): (CGRect, CGRect)
        switch posture {
        case .clamshell(let fold) where fold.width >= fold.height:
            topRegion = CGRect(x: container.minX, y: container.minY, width: container.width,
                               height: max(0, fold.minY - container.minY - spacing))
            bottomRegion = CGRect(x: container.minX, y: fold.maxY + spacing, width: container.width,
                                  height: max(0, container.maxY - fold.maxY - spacing))
        case .clamshell(let fold):
            topRegion = CGRect(x: container.minX, y: container.minY,
                               width: max(0, fold.minX - container.minX - spacing), height: container.height)
            bottomRegion = CGRect(x: fold.maxX + spacing, y: container.minY,
                                  width: max(0, container.maxX - fold.maxX - spacing), height: container.height)
        case .stacked:
            let half = max(0, (container.height - spacing) / 2)
            topRegion = CGRect(x: container.minX, y: container.minY, width: container.width, height: half)
            bottomRegion = CGRect(x: container.minX, y: container.maxY - half, width: container.width, height: half)
        case .sideBySide:
            let half = max(0, (container.width - spacing) / 2)
            topRegion = CGRect(x: container.minX, y: container.minY, width: half, height: container.height)
            bottomRegion = CGRect(x: container.maxX - half, y: container.minY, width: half, height: container.height)
        }

        // Both screens use the same scale so they always look like one device.
        let scale = Self.scale(fitting: [topRegion.size, bottomRegion.size], displayScale: displayScale)
        let size = CGSize(width: Self.screenWidth * scale, height: Self.screenHeight * scale)

        switch posture {
        case .clamshell(let fold) where fold.width >= fold.height:
            // Hug the fold, like the hinge of the original form factor.
            top = Self.place(size, in: topRegion, alignment: .bottom, displayScale: displayScale)
            bottom = Self.place(size, in: bottomRegion, alignment: .top, displayScale: displayScale)
        case .stacked:
            // Keep the pair together in the middle of the container.
            top = Self.place(size, in: topRegion, alignment: .bottom, displayScale: displayScale)
            bottom = Self.place(size, in: bottomRegion, alignment: .top, displayScale: displayScale)
        default:
            top = Self.place(size, in: topRegion, alignment: .center, displayScale: displayScale)
            bottom = Self.place(size, in: bottomRegion, alignment: .center, displayScale: displayScale)
        }
    }

    /// Maps a touch-down to touch-screen coordinates, or nil if it is outside the touch screen.
    public func touchLocation(at point: CGPoint) -> (x: Int, y: Int)? {
        guard bottom.contains(point) else { return nil }
        return clampedTouchLocation(at: point)
    }

    /// Maps a drag to touch-screen coordinates, clamped to the screen's edges.
    public func clampedTouchLocation(at point: CGPoint) -> (x: Int, y: Int) {
        guard bottom.width > 0, bottom.height > 0 else { return (0, 0) }
        let x = Int(((point.x - bottom.minX) / bottom.width * Self.screenWidth).rounded(.down))
        let y = Int(((point.y - bottom.minY) / bottom.height * Self.screenHeight).rounded(.down))
        return (min(max(x, 0), Int(Self.screenWidth) - 1), min(max(y, 0), Int(Self.screenHeight) - 1))
    }

    // MARK: Helpers

    private enum Alignment { case top, center, bottom }

    private static func scale(fitting regions: [CGSize], displayScale: CGFloat) -> CGFloat {
        let fit = regions.map { min($0.width / screenWidth, $0.height / screenHeight) }.min() ?? 0
        guard fit > 0 else { return 0 }
        let pixelsPerDot = fit * displayScale
        guard pixelsPerDot >= 1 else { return fit }
        return pixelsPerDot.rounded(.down) / displayScale
    }

    private static func place(_ size: CGSize, in region: CGRect, alignment: Alignment,
                              displayScale: CGFloat) -> CGRect {
        let x = region.midX - size.width / 2
        let y: CGFloat
        switch alignment {
        case .top: y = region.minY
        case .center: y = region.midY - size.height / 2
        case .bottom: y = region.maxY - size.height
        }
        // Snap the origin to whole pixels so integer scaling stays crisp.
        let snap = { (value: CGFloat) in (value * displayScale).rounded() / displayScale }
        return CGRect(x: snap(x), y: snap(y), width: size.width, height: size.height)
    }
}
