// SPDX-License-Identifier: GPL-3.0-or-later

import AVFAudio

/// Plays an `AudioRingBuffer` through `AVAudioEngine`.
///
/// The render block only reads the lock-free ring, so it is real-time safe. Main-actor only.
@MainActor
public final class AudioOutput: NSObject {
    private let engine = AVAudioEngine()
    private let source: AVAudioSourceNode
    /// Whether the owner wants sound playing (the engine may be stopped by the system).
    private var wantsRunning = false

    public init(ring: AudioRingBuffer, sampleRate: Double) {
        // Standard format: deinterleaved Float32, one buffer per channel.
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        source = Self.makeSourceNode(ring: ring, format: format)
        super.init()
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)

        // Route or category changes (e.g. the microphone opening) stop the engine; restart it.
        // Selector-based observers are removed automatically when this object goes away.
        NotificationCenter.default.addObserver(self, selector: #selector(configurationChanged),
                                               name: .AVAudioEngineConfigurationChange, object: engine)
    }

    /// Builds the node outside the main actor. A closure written in a `@MainActor` initializer
    /// inherits main-actor isolation, and Swift 6 traps when Core Audio then calls it on the
    /// real-time render thread. The render block must stay nonisolated.
    private nonisolated static func makeSourceNode(ring: AudioRingBuffer, format: AVAudioFormat) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { @Sendable _, _, frameCount, audioBufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard buffers.count >= 2,
                  let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                  let right = buffers[1].mData?.assumingMemoryBound(to: Float.self)
            else { return noErr }
            ring.read(left: left, right: right, frames: Int(frameCount))
            return noErr
        }
    }

    /// Posted on an arbitrary thread.
    @objc nonisolated private func configurationChanged(_ notification: Notification) {
        Task { @MainActor in
            guard self.wantsRunning, !self.engine.isRunning else { return }
            try? self.engine.start()
        }
    }

    public var isRunning: Bool { engine.isRunning }

    public func start() throws {
        wantsRunning = true
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        if session.category != .playAndRecord { // keep the microphone's category if it's open
            try session.setCategory(.playback, mode: .default)
        }
        try session.setActive(true)
        #endif
        if !engine.isRunning {
            try engine.start()
        }
    }

    public func stop() {
        wantsRunning = false
        engine.stop()
    }
}
