// SPDX-License-Identifier: GPL-3.0-or-later
//
// clamshell-catalog: verifies homebrew games for the Find Homebrew catalog (macOS only).
//
//   swift run clamshell-catalog <output-dir> [--default-icon ref.png]... <game.nds>...
//   swift run clamshell-catalog --sheet <out.png> <image.png>...   (review grid)
//
// For each game it boots with a temporary SD card image, runs ten emulated seconds, and
// writes <output-dir>/<file>.png (both screens) and, if the game has a banner icon,
// <output-dir>/<file>.icon.png. It prints one JSON object per game to stdout:
//   {"file", "ok", "reason", "fps", "colours", "title", "icon", "defaultIcon"}
// "defaultIcon" is true when the icon is close to the reference (an SDK's placeholder icon,
// which may depict console hardware and must not be shown in Clamshell).
// "ok" means: loaded, still running after 600 frames, and drawing more than a blank fill.
// A human still reviews the screenshots (error screens can be colourful too).

import ClamshellCore
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct Result: Encodable {
    var file: String
    var ok = false
    var reason = ""
    var fps = 0.0
    var colours = 0
    var title: [String] = []
    var icon: String?
    var defaultIcon = false
}

/// RGBA8 pixels of an image file (drawn into a fixed-size bitmap).
func pixels(of url: URL, size: Int = 32) -> [UInt8]? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
          let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    context.interpolationQuality = .none
    context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    guard let data = context.data else { return nil }
    return Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: size * size * 4))
}

/// Mean absolute per-channel difference, 0...255.
func difference(_ a: [UInt8], _ b: [UInt8]) -> Double {
    guard a.count == b.count, !a.isEmpty else { return 255 }
    return Double(zip(a, b).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }) / Double(a.count)
}

/// Lays out images in a grid (each scaled to fit `cell`) for visual review.
func contactSheet(_ urls: [URL], to output: URL, cell: Int = 192, columns: Int = 6) -> Bool {
    let rows = (urls.count + columns - 1) / columns
    guard let context = CGContext(data: nil, width: columns * cell, height: max(rows, 1) * cell, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return false }
    context.setFillColor(CGColor(gray: 0.5, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: columns * cell, height: rows * cell))
    context.interpolationQuality = .none
    for (index, url) in urls.enumerated() {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { continue }
        let scale = min(CGFloat(cell - 8) / CGFloat(image.width), CGFloat(cell - 8) / CGFloat(image.height))
        let w = CGFloat(image.width) * scale, h = CGFloat(image.height) * scale
        let x = CGFloat(index % columns * cell) + (CGFloat(cell) - w) / 2
        let y = CGFloat((rows - 1 - index / columns) * cell) + (CGFloat(cell) - h) / 2
        context.draw(image, in: CGRect(x: x, y: y, width: w, height: h))
    }
    guard let sheet = context.makeImage() else { return false }
    return writePNG(sheet, to: output)
}

func writePNG(_ image: CGImage, to url: URL) -> Bool {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { return false }
    CGImageDestinationAddImage(destination, image, nil)
    return CGImageDestinationFinalize(destination)
}

func verify(_ path: String, outputDirectory: URL, defaultIcons: [[UInt8]]) -> Result {
    let url = URL(filePath: path)
    var result = Result(file: url.lastPathComponent)
    guard let data = try? Data(contentsOf: url) else {
        result.reason = "unreadable"
        return result
    }

    if let banner = GameBanner.read(from: url) {
        result.title = banner.titleLines
        if let icon = banner.iconImage() {
            let iconURL = outputDirectory.appending(path: "\(url.lastPathComponent).icon.png")
            if writePNG(icon, to: iconURL) {
                result.icon = iconURL.path(percentEncoded: false)
                if let mine = pixels(of: iconURL) {
                    result.defaultIcon = defaultIcons.contains { difference(mine, $0) < 24 }
                }
            }
        }
    }

    let sdCard = FileManager.default.temporaryDirectory.appending(path: "catalog-sd-\(UUID()).img")
    defer {
        try? FileManager.default.removeItem(at: sdCard)
        try? FileManager.default.removeItem(at: sdCard.appendingPathExtension("idx"))
    }
    let core = EmulatorCore()
    do {
        try core.loadROM(Array(data), name: url.lastPathComponent, sdCard: sdCard)
    } catch {
        result.reason = "rejected by the core"
        return result
    }
    core.start()

    let frames = 600
    let start = ContinuousClock.now
    for _ in 0..<frames {
        core.runFrame()
        if !core.isRunning { break }
    }
    let elapsed = ContinuousClock.now - start
    result.fps = Double(frames) / (Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18)

    var frame = ScreenFrame()
    guard core.isRunning, core.copyFrame(into: &frame) else {
        result.reason = "stopped while running"
        return result
    }
    result.colours = Set((frame.top + frame.bottom).map { $0 & 0xFFFFFF }).count
    if let png = frame.pngData() {
        try? png.write(to: outputDirectory.appending(path: "\(url.lastPathComponent).png"))
    }
    result.ok = result.colours > 8
    result.reason = result.ok ? "" : "screens nearly blank"
    return result
}

var arguments = Array(CommandLine.arguments.dropFirst())
if arguments.first == "--sheet", arguments.count >= 3 {
    let ok = contactSheet(arguments.dropFirst(2).map { URL(filePath: $0) }, to: URL(filePath: arguments[1]))
    exit(ok ? 0 : 1)
}
guard arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: clamshell-catalog <output-dir> [--default-icon ref.png] <game.nds>...\n".utf8))
    exit(2)
}
let outputDirectory = URL(filePath: arguments.removeFirst())
var defaultIcons: [[UInt8]] = []
while arguments.first == "--default-icon", arguments.count >= 2 {
    if let reference = pixels(of: URL(filePath: arguments[1])) { defaultIcons.append(reference) }
    arguments.removeFirst(2)
}
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
for path in arguments {
    let result = verify(path, outputDirectory: outputDirectory, defaultIcons: defaultIcons)
    print(String(decoding: try encoder.encode(result), as: UTF8.self))
}
