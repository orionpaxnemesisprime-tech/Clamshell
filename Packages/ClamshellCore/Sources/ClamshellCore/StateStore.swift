// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Save-state slots on disk, per game (keyed by ROM SHA-1, like `SaveStore`).
///
/// File format: `CLSS` magic, UInt16 format version, UInt8 length + melonDS version (UTF-8),
/// 40-byte ROM SHA-1 (hex), then the melonDS state compressed with LZFSE (raw states are
/// ~19 MB, mostly zeros). A PNG thumbnail sits next to it.
public struct StateStore: Sendable {
    public struct Slot: Sendable, Identifiable, Equatable {
        public let index: Int
        public let date: Date?
        public let thumbnailURL: URL?
        public var id: Int { index }
        public var isEmpty: Bool { date == nil }
    }

    public enum StateError: Error, Equatable {
        case empty
        case corrupt
        case differentGame
    }

    static let magic = Array("CLSS".utf8)
    static let formatVersion: UInt16 = 1

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    private func gameDirectory(_ romID: String) -> URL { directory.appending(path: romID, directoryHint: .isDirectory) }
    func stateURL(romID: String, slot: Int) -> URL { gameDirectory(romID).appending(path: "slot-\(slot).state") }
    func thumbnailURL(romID: String, slot: Int) -> URL { gameDirectory(romID).appending(path: "slot-\(slot).png") }

    public func slots(romID: String, count: Int) -> [Slot] {
        (0..<count).map { index in
            let url = stateURL(romID: romID, slot: index)
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            let thumbnail = thumbnailURL(romID: romID, slot: index)
            let hasThumbnail = FileManager.default.fileExists(atPath: thumbnail.path(percentEncoded: false))
            return Slot(index: index, date: date, thumbnailURL: date != nil && hasThumbnail ? thumbnail : nil)
        }
    }

    public func write(_ state: [UInt8], thumbnail: Data?, romID: String, slot: Int) throws {
        try FileManager.default.createDirectory(at: gameDirectory(romID), withIntermediateDirectories: true)
        var file = Self.magic
        withUnsafeBytes(of: Self.formatVersion.littleEndian) { file.append(contentsOf: $0) }
        let version = Array(EmulatorCore.melonDSVersion.utf8.prefix(255))
        file.append(UInt8(version.count))
        file.append(contentsOf: version)
        file.append(contentsOf: Array(romID.utf8).prefix(40))
        let compressed = try (Data(state) as NSData).compressed(using: .lzfse) as Data
        file.append(contentsOf: compressed)
        try Data(file).write(to: stateURL(romID: romID, slot: slot), options: .atomic)

        let thumbnailURL = thumbnailURL(romID: romID, slot: slot)
        if let thumbnail {
            try thumbnail.write(to: thumbnailURL, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: thumbnailURL)
        }
    }

    /// The melonDS state from a slot, after checking it belongs to this game.
    public func read(romID: String, slot: Int) throws(StateError) -> [UInt8] {
        guard let data = try? Data(contentsOf: stateURL(romID: romID, slot: slot)) else { throw .empty }
        let bytes = Array(data)
        guard bytes.count > 7, Array(bytes[0..<4]) == Self.magic else { throw .corrupt }
        let version = UInt16(bytes[4]) | UInt16(bytes[5]) << 8
        guard version == Self.formatVersion else { throw .corrupt }
        let versionLength = Int(bytes[6])
        let idStart = 7 + versionLength
        let payloadStart = idStart + 40
        guard bytes.count > payloadStart else { throw .corrupt }
        guard Array(bytes[idStart..<payloadStart]) == Array(romID.utf8) else { throw .differentGame }
        guard let state = try? (Data(bytes[payloadStart...]) as NSData).decompressed(using: .lzfse) as Data
        else { throw .corrupt }
        return Array(state)
    }

    public func delete(romID: String, slot: Int) {
        try? FileManager.default.removeItem(at: stateURL(romID: romID, slot: slot))
        try? FileManager.default.removeItem(at: thumbnailURL(romID: romID, slot: slot))
    }
}

extension ScreenFrame {
    /// Both screens stacked (256x384) as PNG data, for save-state thumbnails.
    public func pngData() -> Data? {
        let width = Self.width
        let height = Self.height * 2
        var pixels = top + bottom
        for i in pixels.indices { pixels[i] |= 0xFF00_0000 } // emulator alpha is undefined
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue)
            .union(.byteOrder32Little) // BGRA in memory
        guard let provider = CGDataProvider(data: Data(bytes: pixels, count: pixels.count * 4) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info,
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}

extension FrameStore {
    /// A copy of the newest frame, if any.
    public func latestFrame() -> ScreenFrame? {
        withLatestFrame { top, bottom, _ in
            var frame = ScreenFrame()
            frame.top = Array(top)
            frame.bottom = Array(bottom)
            return frame
        }
    }
}
