#!/usr/bin/env swift
// Renders the Warp app icon, the "Scan" beam from the Spectrum design pass: a rounded
// spectrum beam (the app's Palette.spectrum, teal -> cobalt -> violet -> ember -> amber,
// fading in from the left and ending clean on amber) lying on a grey-shaded ground.
// No bloom: the beam carries a faint top-light and bottom-shadow for body instead.
//
// tvOS icons are parallax image stacks, so the mark is two layers:
//   Back   the shaded ground - three soft grey fields over a diagonal base, a darker floor
//   Front  the beam
// The top shelf images are single flat renders of the same mark.
//
// Usage: swift scripts/make-icon.swift            (writes straight into Warp/Assets.xcassets)
//        swift scripts/make-icon.swift <out dir>   (writes the PNGs to a directory instead)

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Colors (mirrors Warp/Sources/UI/Theme/Palette.swift)

let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        colorSpace: srgb,
        components: [
            CGFloat((hex >> 16) & 0xFF) / 255,
            CGFloat((hex >> 8) & 0xFF) / 255,
            CGFloat(hex & 0xFF) / 255,
            alpha,
        ])!
}

func gradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
    CGGradient(colorsSpace: srgb, colors: stops.map(\.1) as CFArray, locations: stops.map(\.0))!
}

// MARK: - Contexts

func makeContext(_ w: Int, _ h: Int) -> CGContext {
    let ctx = CGContext(
        data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
        space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high
    return ctx
}

func writePNG(_ image: CGImage, to url: URL) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("could not write \(url.path)") }
    print("wrote \(url.path)")
}

// MARK: - The mark

/// Geometry for a canvas of the given size. The beam scales with the height, so it reads
/// the same on the 5:3 icon and the 8:3 top shelf. Fractions below are the design's
/// 400x240 coordinates; CoreGraphics' origin is bottom-left, so vertical fractions flip.
struct Mark {
    let w: CGFloat
    let h: CGFloat
    var rect: CGRect { CGRect(x: 0, y: 0, width: w, height: h) }
    var unit: CGFloat { h / 240 }

    /// SVG-style point: fractions of the canvas, y measured from the top.
    func at(_ fx: CGFloat, _ fy: CGFloat) -> CGPoint { CGPoint(x: w * fx, y: h * (1 - fy)) }
    /// SVG objectBoundingBox radius: a fraction of the canvas diagonal / sqrt(2).
    func radius(_ f: CGFloat) -> CGFloat { f * ((w * w + h * h) / 2).squareRoot() }

    func radialField(in ctx: CGContext, center: CGPoint, r: CGFloat, stops: [(CGFloat, CGColor)]) {
        ctx.drawRadialGradient(gradient(stops), startCenter: center, startRadius: 0, endCenter: center, endRadius: r, options: [])
    }

    /// The shaded ground: the back layer.
    func back() -> CGImage {
        let ctx = makeContext(Int(w), Int(h))
        // diagonal base, light top-left to dark bottom-right
        ctx.drawLinearGradient(
            gradient([(0, rgb(0x14171E)), (0.5, rgb(0x0E1016)), (1, rgb(0x07080B))]),
            start: at(0, 0), end: at(1, 1), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        // a broad grey field up-right of centre
        radialField(in: ctx, center: at(0.62, 0.42), r: radius(0.6),
                    stops: [(0, rgb(0x3A3F4B, 0.55)), (0.5, rgb(0x23262E, 0.25)), (1, rgb(0x23262E, 0))])
        // a smaller one low-left
        radialField(in: ctx, center: at(0.18, 0.85), r: radius(0.5),
                    stops: [(0, rgb(0x2A2D36, 0.5)), (1, rgb(0x2A2D36, 0))])
        // a corner lift top-right
        radialField(in: ctx, center: at(0.9, 0.1), r: radius(0.4),
                    stops: [(0, rgb(0x31353F, 0.4)), (1, rgb(0x31353F, 0))])
        // the floor darkening at the bottom edge
        ctx.drawLinearGradient(
            gradient([(0, rgb(0x000000, 0)), (0.6, rgb(0x000000, 0)), (1, rgb(0x000000, 0.5))]),
            start: at(0, 0), end: at(0, 1), options: [])
        return ctx.makeImage()!
    }

    /// The beam: the front layer.
    func front() -> CGImage {
        let ctx = makeContext(Int(w), Int(h))
        let beamW = 320 * unit
        let beamH = 22 * unit
        let beam = CGRect(x: (w - beamW) / 2, y: (h - beamH) / 2, width: beamW, height: beamH)
        let path = CGPath(roundedRect: beam, cornerWidth: beamH / 2, cornerHeight: beamH / 2, transform: nil)
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        // the ramp, fading in from nothing on the left and ending clean on amber
        ctx.drawLinearGradient(
            gradient([
                (0, rgb(0x3FD1C4, 0)), (0.16, rgb(0x3FD1C4)), (0.4, rgb(0x5FA0FF)),
                (0.6, rgb(0xA78BFA)), (0.8, rgb(0xFF4D55)), (1, rgb(0xFFB84D)),
            ]),
            start: CGPoint(x: beam.minX, y: 0), end: CGPoint(x: beam.maxX, y: 0), options: [])
        ctx.restoreGState()
        // top-light and bottom-shadow for body, fading in with the ramp so the transparent
        // left end does not carry a grey ghost of the shading
        let shade = makeContext(Int(w), Int(h))
        shade.addPath(path)
        shade.clip()
        shade.drawLinearGradient(
            gradient([(0, rgb(0xFFFFFF, 0.18)), (0.5, rgb(0xFFFFFF, 0)), (1, rgb(0x000000, 0.28))]),
            start: CGPoint(x: 0, y: beam.maxY), end: CGPoint(x: 0, y: beam.minY), options: [])
        shade.setBlendMode(.destinationIn)
        shade.drawLinearGradient(
            gradient([(0, rgb(0x000000, 0)), (0.16, rgb(0x000000, 1))]),
            start: CGPoint(x: beam.minX, y: 0), end: CGPoint(x: beam.maxX, y: 0), options: [.drawsAfterEndLocation])
        ctx.draw(shade.makeImage()!, in: rect)
        return ctx.makeImage()!
    }

    /// Both layers flattened: the top shelf images and a preview of the icon.
    func flat() -> CGImage {
        let ctx = makeContext(Int(w), Int(h))
        ctx.draw(back(), in: rect)
        ctx.draw(front(), in: rect)
        return ctx.makeImage()!
    }
}

// MARK: - Output

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let brand = root.appendingPathComponent("Warp/Assets.xcassets/App Icon & Top Shelf Image.brandassets")
let outDir = CommandLine.arguments.count > 1 ? URL(fileURLWithPath: CommandLine.arguments[1]) : nil

func out(_ catalogPath: String, _ name: String) -> URL {
    if let outDir { return outDir.appendingPathComponent(name) }
    return brand.appendingPathComponent(catalogPath).appendingPathComponent(name)
}

let iconLayers = "App Icon.imagestack"
let storeLayers = "App Icon - App Store.imagestack"
let layerDir = "imagestacklayer/Content.imageset"

// 400x240 @1x and @2x
for (scale, suffix) in [(1, "@1x"), (2, "@2x")] {
    let m = Mark(w: CGFloat(400 * scale), h: CGFloat(240 * scale))
    writePNG(m.front(), to: out("\(iconLayers)/Front.\(layerDir)", "icon-front\(suffix).png"))
    writePNG(m.back(), to: out("\(iconLayers)/Back.\(layerDir)", "icon-back\(suffix).png"))
}

// 1280x768 App Store
do {
    let m = Mark(w: 1280, h: 768)
    writePNG(m.front(), to: out("\(storeLayers)/Front.\(layerDir)", "store-front.png"))
    writePNG(m.back(), to: out("\(storeLayers)/Back.\(layerDir)", "store-back.png"))
}

// Top shelf 1920x720 and wide 2320x720, @1x and @2x
for (scale, suffix) in [(1, "@1x"), (2, "@2x")] {
    writePNG(Mark(w: CGFloat(1920 * scale), h: CGFloat(720 * scale)).flat(),
             to: out("Top Shelf Image.imageset", "topshelf\(suffix).png"))
    writePNG(Mark(w: CGFloat(2320 * scale), h: CGFloat(720 * scale)).flat(),
             to: out("Top Shelf Image Wide.imageset", "topshelf-wide\(suffix).png"))
}

if let outDir {
    writePNG(Mark(w: 800, h: 480).flat(), to: outDir.appendingPathComponent("preview.png"))
}
