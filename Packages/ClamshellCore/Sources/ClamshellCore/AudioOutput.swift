// SPDX-License-Identifier: GPL-3.0-or-later

import AVFAudio

/// Plays an `AudioRingBuffer` through `AVAudioEngine`.
///
/// The render block only reads the lock-free ring, so it is real-time safe.
public final class AudioOutput {
    private let engine = AVAudioEngine()
    private let source: AVAudioSourceNode

    public init(ring: AudioRingBuffer, sampleRate: Double) {
        // Standard format: deinterleaved Float32, one buffer per channel.
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        source = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard buffers.count >= 2,
                  let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                  let right = buffers[1].mData?.assumingMemoryBound(to: Float.self)
            else { return noErr }
            ring.read(left: left, right: right, frames: Int(frameCount))
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
    }

    public var isRunning: Bool { engine.isRunning }

    public func start() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
        #endif
        if !engine.isRunning {
            try engine.start()
        }
    }

    public func stop() {
        engine.stop()
    }
}
