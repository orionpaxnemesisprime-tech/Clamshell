// SPDX-License-Identifier: GPL-3.0-or-later

import Synchronization

/// Triple-buffered hand-off of emulated frames from the emulation thread to the renderer.
///
/// The writer always has a free slot (one may be "latest", one may be "reading"), so neither
/// side ever waits for the other. The renderer only sees complete frames.
public final class FrameStore: @unchecked Sendable {
    // @unchecked: slot memory is shared, but the Mutex-protected slot protocol guarantees a
    // slot is never written while it is `latest` or `reading`.

    private struct State {
        var latest: Int?
        var reading: Int?
        var generation: UInt64 = 0
    }

    private static let slotCount = 3
    private let pixels = ScreenFrame.pixelCount
    private let storage: UnsafeMutablePointer<UInt32>
    private let state = Mutex(State())

    public init() {
        let count = Self.slotCount * 2 * ScreenFrame.pixelCount
        storage = .allocate(capacity: count)
        storage.initialize(repeating: 0, count: count)
    }

    deinit {
        storage.deallocate()
    }

    private func top(_ slot: Int) -> UnsafeMutablePointer<UInt32> { storage + slot * 2 * pixels }
    private func bottom(_ slot: Int) -> UnsafeMutablePointer<UInt32> { top(slot) + pixels }

    /// Writer side. `fill` writes both screens into the given buffers; return false to discard.
    public func publish(_ fill: (_ top: UnsafeMutablePointer<UInt32>, _ bottom: UnsafeMutablePointer<UInt32>) -> Bool) {
        let slot = state.withLock { state in
            (0..<Self.slotCount).first { $0 != state.latest && $0 != state.reading }!
        }
        guard fill(top(slot), bottom(slot)) else { return }
        state.withLock { state in
            state.latest = slot
            state.generation &+= 1
        }
    }

    /// Generation of the most recently published frame (0 before the first frame).
    public var generation: UInt64 { state.withLock { $0.generation } }

    /// Reader side. Runs `body` with the newest frame if it is newer than `after`.
    /// Keep `body` short: copy or upload the pixels, don't retain the pointers.
    public func withLatestFrame<R>(
        newerThan after: UInt64 = 0,
        _ body: (_ top: UnsafeBufferPointer<UInt32>, _ bottom: UnsafeBufferPointer<UInt32>, _ generation: UInt64) throws -> R
    ) rethrows -> R? {
        let acquired: (slot: Int, generation: UInt64)? = state.withLock { state in
            guard let latest = state.latest, state.generation > after else { return nil }
            state.reading = latest
            return (latest, state.generation)
        }
        guard let acquired else { return nil }
        defer { state.withLock { $0.reading = nil } }
        return try body(UnsafeBufferPointer(start: top(acquired.slot), count: pixels),
                        UnsafeBufferPointer(start: bottom(acquired.slot), count: pixels),
                        acquired.generation)
    }
}
