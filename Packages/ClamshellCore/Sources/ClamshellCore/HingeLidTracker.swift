// SPDX-License-Identifier: GPL-3.0-or-later

/// Turns a foldable device's hinge angle into the emulated console's lid state.
///
/// Hysteresis keeps the lid from flickering near the threshold: it closes below
/// `closeBelow` degrees and only reopens above `openAbove` degrees.
public struct HingeLidTracker: Sendable, Equatable {
    public var closeBelow: Double = 10
    public var openAbove: Double = 30
    public private(set) var isClosed = false

    public init(closeBelow: Double = 10, openAbove: Double = 30) {
        self.closeBelow = closeBelow
        self.openAbove = openAbove
    }

    /// Feeds a new angle (180 = fully open, 0 = closed); returns the lid state.
    @discardableResult
    public mutating func update(angleDegrees: Double) -> Bool {
        if isClosed, angleDegrees > openAbove {
            isClosed = false
        } else if !isClosed, angleDegrees < closeBelow {
            isClosed = true
        }
        return isClosed
    }

    public mutating func reset() {
        isClosed = false
    }
}
