// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing
@testable import ClamshellCore

@Suite(.serialized)
struct FramePacerTests {
    private let clock = ContinuousClock()

    @Test func catchesUpAfterAnOversleep() {
        var pacer = FramePacer(frameRate: 60)
        // A 100 ms oversleep is 6 frames behind but under maxLag: the next frames are due at
        // once, so the game keeps its average speed.
        Thread.sleep(forTimeInterval: 0.1)
        let start = clock.now
        for _ in 0..<5 { pacer.waitForNextFrame() }
        #expect(clock.now - start < .milliseconds(20))
    }

    @Test func reanchorsAfterAStall() {
        var pacer = FramePacer(frameRate: 60, maxLag: .milliseconds(250))
        Thread.sleep(forTimeInterval: 0.4)
        pacer.waitForNextFrame() // re-anchors; doesn't wait
        let start = clock.now
        pacer.waitForNextFrame() // back to normal pacing: waits about one period
        #expect(clock.now - start > .milliseconds(10))
    }
}
