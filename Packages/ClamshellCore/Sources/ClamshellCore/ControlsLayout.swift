// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics

/// On-screen controls placed around the two screens, plus hit-testing for touches.
public struct ControlsLayout: Sendable, Equatable {
    public enum Control: Sendable, Hashable, CaseIterable {
        case dpad, faceButtons, l, r, select, start
        /// Plays a recorded blow into the microphone (shown only while a game listens).
        case blow
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
    /// Height of the shoulder row above the D-pad and face buttons, including its gap.
    private static let shoulderRowHeight: CGFloat = shoulderSize.height + margin
    /// Height of the band the `.below` placement needs.
    public static let bandHeight: CGFloat = shoulderRowHeight + faceSize + smallButtonSize.height + 3 * margin

    public var placement: Placement
    public var frames: [Control: CGRect]

    public init(container: CGRect, screens: ScreenLayout, showsBlow: Bool = false) {
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
            // Thumbs rest beside the touch screen, which is where the hands are. The shoulder
            // row stays level with or below the touch screen's top edge, clear of any fold.
            let anchorY = max(screens.bottom.midY, screens.bottom.minY + Self.shoulderRowHeight + Self.faceSize / 2)
            frames = Self.cluster(left: left, right: right, centerY: anchorY, container: container)
        } else if below.height >= Self.bandHeight {
            placement = .below
            let band = below.insetBy(dx: Self.margin, dy: Self.margin)
            frames = Self.cluster(left: CGRect(x: band.minX, y: band.minY, width: besideWidth, height: band.height),
                                  right: CGRect(x: band.maxX - besideWidth, y: band.minY,
                                                width: besideWidth, height: band.height),
                                  centerY: band.minY + Self.shoulderRowHeight + Self.faceSize / 2,
                                  container: container)
        } else {
            placement = .overlay
            let inset = container.insetBy(dx: Self.margin, dy: Self.margin)
            let side = CGRect(x: 0, y: 0, width: besideWidth, height: inset.height)
            frames = Self.cluster(left: side.offsetBy(dx: inset.minX - Self.margin, dy: inset.minY),
                                  right: side.offsetBy(dx: inset.maxX - besideWidth + Self.margin, dy: inset.minY),
                                  centerY: inset.maxY - Self.faceSize / 2 - Self.smallButtonSize.height - Self.margin,
                                  container: container)
        }
        if showsBlow, let blow = Self.blowFrame(frames: frames, container: container) {
            frames[.blow] = blow
        }
    }

    /// Next to Select if there is room, otherwise just below it.
    private static func blowFrame(frames: [Control: CGRect], container: CGRect) -> CGRect? {
        guard let select = frames[.select] else { return nil }
        let size = smallButtonSize
        let candidates = [
            CGRect(x: select.maxX + margin, y: select.minY, width: size.width, height: size.height),
            CGRect(x: select.minX, y: select.maxY + margin, width: size.width, height: size.height),
            CGRect(x: select.minX - margin - size.width, y: select.minY, width: size.width, height: size.height),
        ]
        return candidates.first { candidate in
            container.contains(candidate) && !frames.values.contains { $0.intersects(candidate) }
        }
    }

    /// D-pad + Select on the left, face buttons + Start on the right, each with its shoulder
    /// button (L or R) just above, within thumb reach.
    private static func cluster(left: CGRect, right: CGRect, centerY: CGFloat, container: CGRect) -> [Control: CGRect] {
        func square(_ size: CGFloat, centerX: CGFloat) -> CGRect {
            CGRect(x: centerX - size / 2, y: centerY - size / 2, width: size, height: size)
        }
        let dpad = square(dpadSize, centerX: left.midX)
        let face = square(faceSize, centerX: right.midX)
        let small = smallButtonSize
        let shoulder = shoulderSize
        // Level with each other, above the taller of the two clusters.
        let shoulderY = max(container.minY + margin, face.minY - margin - shoulder.height)
        return [
            .dpad: dpad,
            .faceButtons: face,
            .select: CGRect(x: dpad.midX - small.width / 2, y: face.maxY + margin, width: small.width, height: small.height),
            .start: CGRect(x: face.midX - small.width / 2, y: face.maxY + margin, width: small.width, height: small.height),
            .l: CGRect(x: dpad.midX - shoulder.width / 2, y: shoulderY, width: shoulder.width, height: shoulder.height),
            .r: CGRect(x: face.midX - shoulder.width / 2, y: shoulderY, width: shoulder.width, height: shoulder.height),
        ]
    }

    /// The control under `point`, if any.
    public func control(at point: CGPoint) -> Control? {
        frames.first { $0.value.contains(point) }?.key
    }

    /// Keys pressed by a touch at `point` (empty if it misses every control).
    public func keys(at point: CGPoint) -> EmulatorKeys {
        for (control, frame) in frames where frame.contains(point) {
            switch control {
            case .blow: return []
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
        directionKeys(dx: point.x - frame.midX, dy: point.y - frame.midY, deadZone: frame.width * 0.12)
    }

    /// Analog stick in place of the D-pad: a thumb that touched down on it keeps steering it
    /// from anywhere, including outside `frame`. Pushing past a quarter of the radius picks
    /// one of the same eight directions as the D-pad.
    public static func stickKeys(at point: CGPoint, in frame: CGRect) -> EmulatorKeys {
        directionKeys(dx: point.x - frame.midX, dy: point.y - frame.midY, deadZone: frame.width / 2 * 0.25)
    }

    /// Where to draw the stick's knob for a thumb at `point`: under the thumb, held within
    /// `travel` of the centre.
    public static func stickKnobCenter(for point: CGPoint, in frame: CGRect, travel: CGFloat) -> CGPoint {
        let dx = point.x - frame.midX
        let dy = point.y - frame.midY
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > travel else { return point }
        return CGPoint(x: frame.midX + dx / length * travel, y: frame.midY + dy / length * travel)
    }

    private static func directionKeys(dx: CGFloat, dy: CGFloat, deadZone: CGFloat) -> EmulatorKeys {
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > deadZone else { return [] }
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
