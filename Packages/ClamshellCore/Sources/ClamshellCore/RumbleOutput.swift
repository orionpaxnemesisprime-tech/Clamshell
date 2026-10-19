// SPDX-License-Identifier: GPL-3.0-or-later

import CoreHaptics
import Foundation
import Synchronization

/// Receives Rumble Pak motor pulses. Called on the emulation thread; must return quickly.
public protocol RumbleSink: AnyObject, Sendable {
    func start(milliseconds: Int)
    func stop()
}

/// Plays Rumble Pak pulses on the device's Taptic Engine.
///
/// Games toggle the motor rapidly (melonDS reports each toggle as a 16 ms pulse), so each
/// pulse plays a short continuous haptic; a stop cuts the current one off.
public final class RumbleOutput: RumbleSink, @unchecked Sendable {
    // @unchecked: all Core Haptics state is touched only on `queue`; `intensity` is a Mutex.

    private let queue = DispatchQueue(label: "com.foldingduo.Clamshell.rumble", qos: .userInteractive)
    private var engine: CHHapticEngine?
    private var player: (any CHHapticPatternPlayer)?

    /// Intensity 0...1 of the motor.
    public var intensity: Float {
        get { intensityStore.withLock { $0 } }
        set { intensityStore.withLock { $0 = min(max(newValue, 0), 1) } }
    }
    private let intensityStore = Mutex<Float>(0.7)

    public init() {}

    /// False on devices without a Taptic Engine (and in the Simulator).
    public static var isSupported: Bool { CHHapticEngine.capabilitiesForHardware().supportsHaptics }

    public func start(milliseconds: Int) {
        let duration = max(Double(milliseconds), 16) / 1_000
        let intensity = intensity
        queue.async { [self] in
            guard let engine = runningEngine() else { return }
            try? player?.stop(atTime: CHHapticTimeImmediate)
            let event = CHHapticEvent(eventType: .hapticContinuous, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.2),
            ], relativeTime: 0, duration: duration)
            guard let pattern = try? CHHapticPattern(events: [event], parameters: []),
                  let player = try? engine.makePlayer(with: pattern)
            else { return }
            self.player = player
            try? player.start(atTime: CHHapticTimeImmediate)
        }
    }

    public func stop() {
        queue.async { [self] in
            try? player?.stop(atTime: CHHapticTimeImmediate)
            player = nil
        }
    }

    private func runningEngine() -> CHHapticEngine? {
        guard Self.isSupported else { return nil }
        if engine == nil {
            engine = try? CHHapticEngine()
            engine?.playsHapticsOnly = true
            engine?.isAutoShutdownEnabled = true
            engine?.resetHandler = { [weak self] in
                self?.queue.async { try? self?.engine?.start() }
            }
        }
        try? engine?.start()
        return engine
    }
}
