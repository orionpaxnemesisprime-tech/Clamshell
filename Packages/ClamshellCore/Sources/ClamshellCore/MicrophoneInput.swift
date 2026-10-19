// SPDX-License-Identifier: GPL-3.0-or-later

import AVFAudio
import Synchronization

/// The device microphone as a `MicrophoneSource`.
///
/// Capture starts only when a game opens its microphone (that is also when permission is
/// requested) and stops when the game closes it. Audio is processed in memory only.
/// If permission is denied the game simply hears silence.
public final class MicrophoneInput: MicrophoneSource, @unchecked Sendable {
    // @unchecked: `engine` and `converter` are touched only on `queue`; the ring is lock-free.

    private let ring = MonoSampleRing(capacity: 16_384)
    private let queue = DispatchQueue(label: "com.foldingduo.Clamshell.microphone")
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private let wanted = Atomic<Bool>(false)

    /// Called on the main actor when the user denies microphone access.
    public var onPermissionDenied: (@Sendable () -> Void)?

    public init() {}

    public func start() {
        wanted.store(true, ordering: .relaxed)
        AVAudioApplication.requestRecordPermission { [self] granted in
            guard granted else {
                if let onPermissionDenied { DispatchQueue.main.async(execute: onPermissionDenied) }
                return
            }
            queue.async { [self] in
                guard wanted.load(ordering: .relaxed) else { return } // closed again meanwhile
                startCapture()
            }
        }
    }

    public func stop() {
        wanted.store(false, ordering: .relaxed)
        queue.async { [self] in stopCapture() }
    }

    public func read(into buffer: UnsafeMutableBufferPointer<Int16>) -> Int {
        ring.read(into: buffer)
    }

    // MARK: Capture (on `queue`)

    private func startCapture() {
        guard !engine.isRunning else { return }
        do {
            #if os(iOS)
            try AVAudioSession.sharedInstance().setCategory(
                .playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])
            try AVAudioSession.sharedInstance().setActive(true)
            #endif

            let input = engine.inputNode
            let inputFormat = input.outputFormat(forBus: 0)
            guard inputFormat.sampleRate > 0,
                  let outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                                   sampleRate: EmulatorCore.microphoneSampleRate,
                                                   channels: 1, interleaved: true),
                  let converter = AVAudioConverter(from: inputFormat, to: outputFormat)
            else { return }
            self.converter = converter
            ring.flush()

            let ring = ring
            input.installTap(onBus: 0, bufferSize: 1_024, format: inputFormat) { buffer, _ in
                let capacity = AVAudioFrameCount(Double(buffer.frameLength) * outputFormat.sampleRate
                                                 / inputFormat.sampleRate) + 16
                guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity)
                else { return }
                nonisolated(unsafe) var supplied = false
                converter.convert(to: output, error: nil) { _, status in
                    if supplied {
                        status.pointee = .noDataNow
                        return nil
                    }
                    supplied = true
                    status.pointee = .haveData
                    return buffer
                }
                if let samples = output.int16ChannelData?[0] {
                    ring.write(UnsafeBufferPointer(start: samples, count: Int(output.frameLength)))
                }
            }
            try engine.start()
        } catch {
            stopCapture()
        }
    }

    private func stopCapture() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        converter = nil
        ring.flush()
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        #endif
    }
}
