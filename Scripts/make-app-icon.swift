#!/usr/bin/env swift
// Draws Clamshell's app icon (an original scallop-shell mark) in the three iOS appearances.
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Usage: swift Scripts/make-app-icon.swift Clamshell/Assets.xcassets/AppIcon.appiconset
//
// The mark is deliberately a seashell, not a hinged two-screen device: Clamshell must not use
// any console's shell design or likeness (see the app-store-compliance skill).

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let outputDirectory = URL(filePath: CommandLine.arguments.dropFirst().first ?? ".")

enum Appearance: String, CaseIterable {
    case light = "AppIcon.png"
    case dark = "AppIcon-Dark.png"
    case tinted = "AppIcon-Tinted.png"
}

func colour(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// Scallop outline: a fan of ribs around a pivot, with a scalloped outer edge and two "ears"
/// at the hinge.
func shellPath(pivot: CGPoint, radius: CGFloat, ribs: Int) -> CGPath {
    let path = CGMutablePath()
    let start = CGFloat.pi * 1.10, end = CGFloat.pi * 1.90 // fan opens upward (y grows down)
    func point(_ angle: CGFloat, _ r: CGFloat) -> CGPoint {
        CGPoint(x: pivot.x + cos(angle) * r, y: pivot.y + sin(angle) * r)
    }
    path.move(to: pivot)
    path.addLine(to: point(start, radius))
    for i in 0..<ribs {
        let a0 = start + (end - start) * CGFloat(i) / CGFloat(ribs)
        let a1 = start + (end - start) * CGFloat(i + 1) / CGFloat(ribs)
        path.addQuadCurve(to: point(a1, radius), control: point((a0 + a1) / 2, radius * 1.09))
    }
    path.closeSubpath()

    // Hinge: one rounded base under the fan, wider at the top, like a scallop's auricles.
    let top = radius * 0.30, bottom = radius * 0.17, depth = radius * 0.15
    let base = CGMutablePath()
    base.move(to: CGPoint(x: pivot.x - top, y: pivot.y - radius * 0.04))
    base.addLine(to: CGPoint(x: pivot.x + top, y: pivot.y - radius * 0.04))
    base.addQuadCurve(to: CGPoint(x: pivot.x + bottom, y: pivot.y + depth),
                      control: CGPoint(x: pivot.x + top, y: pivot.y + depth))
    base.addLine(to: CGPoint(x: pivot.x - bottom, y: pivot.y + depth))
    base.addQuadCurve(to: CGPoint(x: pivot.x - top, y: pivot.y - radius * 0.04),
                      control: CGPoint(x: pivot.x - top, y: pivot.y + depth))
    base.closeSubpath()
    path.addPath(base)
    return path
}

func ribGrooves(pivot: CGPoint, radius: CGFloat, ribs: Int) -> CGPath {
    let path = CGMutablePath()
    let start = CGFloat.pi * 1.10, end = CGFloat.pi * 1.90
    for i in 1..<ribs {
        let angle = start + (end - start) * CGFloat(i) / CGFloat(ribs)
        path.move(to: CGPoint(x: pivot.x + cos(angle) * radius * 0.16, y: pivot.y + sin(angle) * radius * 0.16))
        path.addLine(to: CGPoint(x: pivot.x + cos(angle) * radius * 0.97, y: pivot.y + sin(angle) * radius * 0.97))
    }
    return path
}

func draw(_ appearance: Appearance) -> CGImage? {
    guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    // Flip so y grows downward, like the geometry above.
    context.translateBy(x: 0, y: CGFloat(size))
    context.scaleBy(x: 1, y: -1)
    let full = CGRect(x: 0, y: 0, width: size, height: size)

    // Background (iOS masks the corners itself, so fill edge to edge).
    switch appearance {
    case .light:
        let gradient = CGGradient(colorsSpace: nil, colors: [colour(0x0E7C86), colour(0x2B2F8F)] as CFArray,
                                  locations: [0, 1])!
        context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size, y: size), options: [])
    case .dark:
        context.setFillColor(colour(0x0B0E1A))
        context.fill(full)
    case .tinted:
        context.setFillColor(colour(0x000000))
        context.fill(full)
    }

    let pivot = CGPoint(x: 512, y: 700)
    let radius: CGFloat = 430
    let ribs = 9
    let shell = shellPath(pivot: pivot, radius: radius, ribs: ribs)

    // Soft shadow under the shell on the colourful background only.
    if appearance == .light {
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: 18), blur: 40, color: colour(0x000000, 0.35))
        context.addPath(shell)
        context.setFillColor(colour(0xFFFFFF))
        context.fillPath()
        context.restoreGState()
    }

    // Shell body: white-to-pearl gradient (or a single tone for dark/tinted).
    context.saveGState()
    context.addPath(shell)
    context.clip()
    let body: [CGColor] = switch appearance {
    case .light: [colour(0xFFFFFF), colour(0xE6F4F5)]
    case .dark: [colour(0x5ED3D9), colour(0x3A8FC9)]
    case .tinted: [colour(0xFFFFFF), colour(0xC8C8C8)]
    }
    let gradient = CGGradient(colorsSpace: nil, colors: body as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 512, y: pivot.y - radius), end: pivot, options: [])
    context.restoreGState()

    // Rib grooves.
    context.addPath(ribGrooves(pivot: pivot, radius: radius, ribs: ribs))
    context.setLineCap(.round)
    context.setLineWidth(14)
    let groove: CGColor = switch appearance {
    case .light: colour(0x0E7C86, 0.35)
    case .dark: colour(0x0B0E1A, 0.45)
    case .tinted: colour(0x000000, 0.35)
    }
    context.setStrokeColor(groove)
    context.strokePath()
    return context.makeImage()
}

for appearance in Appearance.allCases {
    guard let image = draw(appearance) else { fatalError("could not draw \(appearance)") }
    let url = outputDirectory.appending(path: appearance.rawValue)
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { fatalError("could not write \(url.path)") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("could not finalize \(url.path)") }
    print("Wrote \(url.path)")
}
