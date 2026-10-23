// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Deadline-based frame limiter. Error never accumulates: each deadline is the previous
/// deadline plus one period, not "now" plus one period.
struct FramePacer {
    let period: Duration
    /// If the loop falls this far behind (e.g. after a stall), re-anchor instead of racing.
    /// Shorter lags are caught up with back-to-back frames: sleeps can overshoot by tens of
    /// milliseconds (low-power modes, virtual machines), and re-anchoring after each one
    /// would lose time for good and slow the game down.
    let maxLag: Duration
    private let clock = ContinuousClock()
    private var deadline: ContinuousClock.Instant

    init(frameRate: Double, maxLag: Duration = .milliseconds(250)) {
        period = .seconds(1 / frameRate)
        self.maxLag = maxLag
        deadline = clock.now
    }

    mutating func reset() {
        deadline = clock.now
    }

    /// Sleeps until the next frame is due.
    mutating func waitForNextFrame() {
        deadline += period
        let now = clock.now
        if now - deadline > maxLag {
            deadline = now
            return
        }
        let remaining = deadline - now
        if remaining > .zero {
            Thread.sleep(forTimeInterval: Double(remaining.components.seconds)
                         + Double(remaining.components.attoseconds) / 1e18)
        }
    }
}
