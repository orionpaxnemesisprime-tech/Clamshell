// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics

/// On-screen controls placed around the two screens, plus hit-testing for touches.
public struct ControlsLayout: Sendable, Equatable {
    public enum Control: Sendable, Hashable, CaseIterable {
        case dpad, faceButtons, l, r, select, start
    }

    public enum Placement: Sendable, Equatable {
        /// D-pad and face buttons beside the touch screen.
        case beside
        /// Controls in a band below the screens.
        case below
        /// Not enough free space: translucent controls over the screen edges.
        case overlay
    }

    public static let dpadSize: CGFloat = 132
    public static let faceSize: CGFloat = 140
    public static let shoulderSize = CGSize(width: 76, height: 36)
    public static let smallButtonSize = CGSize(width: 64, height: 30)
    private static let margin: CGFloat = 12
    /// Height of the band the `.below` placement needs.
    public static let bandHeight: CGFloat = faceSize + smallButtonSize.height + 3 * margin

    public var placement: Placement
    public var frames: [Control: CGRect]

    public init(container: CGRect, screens: ScreenLayout) {
        let screensFrame = screens.top.union(screens.bottom)
        let left = CGRect(x: container.minX, y: container.minY,
                          width: max(0, screensFrame.minX - container.minX), height: container.height)
        let right = CGRect(x: screensFrame.maxX, y: container.minY,
                           width: max(0, container.maxX - screensFrame.maxX), height: container.height)
        let below = CGRect(x: container.minX, y: screensFrame.maxY,
                           width: container.width, height: max(0, container.maxY - screensFrame.maxY))
        let besideWidth = Self.faceSize + 2 * Self.margin

        if left.width >= besideWidth && right.width >= besideWidth {
            placement = .beside
            // Thumbs rest beside the touch screen, which is where the hands are.
            let anchorY = screens.bottom.midY
            frames = Self.cluster(left: left, right: right, centerY: anchorY, container: container)
        } else if below.height >= Self.bandHeight {
            placement = .below
            let band = below.insetBy(dx: Self.margin, dy: Self.margin)
            frames = Self.cluster(left: CGRect(x: band.minX, y: band.minY, width: besideWidth, height: band.height),
                                  right: CGRect(x: band.maxX - besideWidth, y: band.minY,
                                                width: besideWidth, height: band.height),
                                  centerY: band.minY + Self.faceSize / 2, container: container)
        } else {
            placement = .overlay
            let inset = container.insetBy(dx: Self.margin, dy: Self.margin)
            let side = CGRect(x: 0, y: 0, width: besideWidth, height: inset.height)
            frames = Self.cluster(left: side.offsetBy(dx: inset.minX - Self.margin, dy: inset.minY),
                                  right: side.offsetBy(dx: inset.maxX - besideWidth + Self.margin, dy: inset.minY),
                                  centerY: inset.maxY - Self.faceSize / 2 - Self.smallButtonSize.height - Self.margin,
                                  container: container)
        }
    }

    /// D-pad + Select on the left, face buttons + Start on the right, shoulders at the top
    /// corners of the container.
    private static func cluster(left: CGRect, right: CGRect, centerY: CGFloat, container: CGRect) -> [Control: CGRect] {
        func square(_ size: CGFloat, centerX: CGFloat) -> CGRect {
            CGRect(x: centerX - size / 2, y: centerY - size / 2, width: size, height: size)
        }
        let dpad = square(dpadSize, centerX: left.midX)
        let face = square(faceSize, centerX: right.midX)
        let small = smallButtonSize
        let shoulder = shoulderSize
        return [
            .dpad: dpad,
            .faceButtons: face,
            .select: CGRect(x: dpad.midX - small.width / 2, y: face.maxY + margin, width: small.width, height: small.height),
            .start: CGRect(x: face.midX - small.width / 2, y: face.maxY + margin, width: small.width, height: small.height),
            .l: CGRect(x: container.minX + margin, y: container.minY + margin, width: shoulder.width, height: shoulder.height),
            .r: CGRect(x: container.maxX - margin - shoulder.width, y: container.minY + margin,
                       width: shoulder.width, height: shoulder.height),
        ]
    }

    /// Keys pressed by a touch at `point` (empty if it misses every control).
    public func keys(at point: CGPoint) -> EmulatorKeys {
        for (control, frame) in frames where frame.contains(point) {
            switch control {
            case .dpad: return Self.dpadKeys(at: point, in: frame)
            case .faceButtons: return Self.faceKey(at: point, in: frame)
            case .l: return .l
            case .r: return .r
            case .select: return .select
            case .start: return .start
            }
        }
        return []
    }

    /// Eight-way D-pad: each direction covers a 135° cone, so diagonals are easy to hit.
    static func dpadKeys(at point: CGPoint, in frame: CGRect) -> EmulatorKeys {
        let dx = point.x - frame.midX
        let dy = point.y - frame.midY
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > frame.width * 0.12 else { return [] }
        let threshold: CGFloat = 0.38 // sin(22.5°)
        var keys: EmulatorKeys = []
        if dx / length > threshold { keys.insert(.right) }
        if dx / length < -threshold { keys.insert(.left) }
        if dy / length > threshold { keys.insert(.down) }
        if dy / length < -threshold { keys.insert(.up) }
        return keys
    }

    /// Face buttons in a diamond: X top, B bottom, Y left, A right.
    static func faceKey(at point: CGPoint, in frame: CGRect) -> EmulatorKeys {
        let dx = point.x - frame.midX
        let dy = point.y - frame.midY
        if abs(dx) > abs(dy) { return dx > 0 ? .a : .y }
        return dy < 0 ? .x : .b
    }
}
