// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// The icon and title a game file carries in its banner (what the console's menu shows).
///
/// Layout (GBATEK "DS Cartridge Icon/Title"; melonDS `NDSBanner`): header word at 0x68 holds
/// the banner offset; in the banner, a 32x32 4-bit icon in 8x8 tiles at +0x20, a 16-colour
/// BGR555 palette at +0x220 (colour 0 transparent) and UTF-16 titles at +0x240 (Japanese),
/// +0x340 (English), each 128 characters with lines separated by "\n".
public struct GameBanner: Sendable, Equatable {
    /// Title lines (usually name, subtitle, author), English version.
    public var titleLines: [String]
    /// 32x32 RGBA8 icon pixels, premultiplied, row-major.
    public var iconRGBA: [UInt8]

    public static let iconSize = 32

    /// The bytes needed from the file: header offset word, then 0x440 bytes of banner.
    static let bannerOffsetPosition = 0x68
    static let bannerLength = 0x440

    /// Reads just the header and banner from a file on disk; nil if there is no banner.
    public static func read(from url: URL) -> GameBanner? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: UInt64(bannerOffsetPosition))) != nil,
              let offsetBytes = try? handle.read(upToCount: 4), offsetBytes.count == 4
        else { return nil }
        let offset = offsetBytes.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self)) }
        guard offset >= 0x200,
              (try? handle.seek(toOffset: UInt64(offset))) != nil,
              let banner = try? handle.read(upToCount: bannerLength), banner.count == bannerLength
        else { return nil }
        return parse(banner: Array(banner))
    }

    /// Parses the first 0x440 bytes of a banner.
    public static func parse(banner: [UInt8]) -> GameBanner? {
        guard banner.count >= bannerLength else { return nil }

        func u16(_ index: Int) -> UInt16 { UInt16(banner[index]) | UInt16(banner[index + 1]) << 8 }

        // Title: 128 UTF-16 code units, NUL-terminated.
        var units: [UInt16] = []
        for i in 0..<128 {
            let unit = u16(0x340 + i * 2)
            if unit == 0 { break }
            units.append(unit)
        }
        let title = String(decoding: units, as: UTF16.self)
        let lines = title.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        // Palette: BGR555 -> RGBA8; colour 0 is transparent.
        var palette = [(UInt8, UInt8, UInt8, UInt8)](repeating: (0, 0, 0, 0), count: 16)
        for i in 1..<16 {
            let colour = u16(0x220 + i * 2)
            func expand(_ value: UInt16) -> UInt8 { UInt8((value << 3) | (value >> 2)) }
            palette[i] = (expand(colour & 0x1F), expand((colour >> 5) & 0x1F), expand((colour >> 10) & 0x1F), 255)
        }

        // Icon: 4x4 tiles of 8x8 pixels, two pixels per byte (low nibble first).
        var pixels = [UInt8](repeating: 0, count: iconSize * iconSize * 4)
        for tile in 0..<16 {
            for row in 0..<8 {
                for column in 0..<8 {
                    let byte = banner[0x20 + tile * 32 + row * 4 + column / 2]
                    let index = Int(column.isMultiple(of: 2) ? byte & 0x0F : byte >> 4)
                    let x = (tile % 4) * 8 + column
                    let y = (tile / 4) * 8 + row
                    let (r, g, b, a) = palette[index]
                    let offset = (y * iconSize + x) * 4
                    pixels[offset] = r
                    pixels[offset + 1] = g
                    pixels[offset + 2] = b
                    pixels[offset + 3] = a
                }
            }
        }

        let hasIcon = pixels.enumerated().contains { $0.offset % 4 == 3 && $0.element != 0 }
        guard !lines.isEmpty || hasIcon else { return nil }
        return GameBanner(titleLines: lines, iconRGBA: pixels)
    }

    /// The icon as a CGImage (32x32), for display with nearest-neighbour scaling.
    public func iconImage() -> CGImage? {
        guard let provider = CGDataProvider(data: Data(iconRGBA) as CFData) else { return nil }
        return CGImage(width: Self.iconSize, height: Self.iconSize, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: Self.iconSize * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
