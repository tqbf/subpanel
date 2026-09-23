#!/usr/bin/env swift
//
// make-icon.swift — render the app icon at every macOS size.
//
// Subpanel's mark is an electrical subpanel: a dark breaker enclosure with a
// hazard sign and a bank of three breakers, standing on two conduits, on a
// light macOS icon tile. (It's a pun. Each breaker is an app routed on
// its own circuit.) Drawn from the reference artwork's geometry in pure
// CoreGraphics — no assets, no dependencies — so every size is crisp. The
// Makefile runs `iconutil -c icns build/AppIcon.iconset` on the PNGs this
// writes.

import AppKit

let iconsetDir = "build/AppIcon.iconset"
try? FileManager.default.createDirectory(
    atPath: iconsetDir, withIntermediateDirectories: true)

// (filename, pixel dimension) — the set iconutil expects.
let variants: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

func gradient(_ top: CGColor, _ bottom: CGColor) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [top, bottom] as CFArray, locations: [0, 1])!
}

func roundedRect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> CGPath {
    CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: r, cornerHeight: r, transform: nil)
}

/// Fills `path` with a vertical gradient between `top` and `bottom` (y-down
/// artwork coordinates, so "top" is the smaller y).
func fill(_ ctx: CGContext, _ path: CGPath, top: CGColor, bottom: CGColor) {
    let box = path.boundingBoxOfPath
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.drawLinearGradient(gradient(top, bottom), start: CGPoint(x: 0, y: box.minY), end: CGPoint(x: 0, y: box.maxY), options: [])
    ctx.restoreGState()
}

func stroke(_ ctx: CGContext, _ path: CGPath, _ color: CGColor, width: CGFloat) {
    ctx.saveGState()
    ctx.setStrokeColor(color)
    ctx.setLineWidth(width)
    ctx.setLineJoin(.round)
    ctx.setLineCap(.round)
    ctx.addPath(path)
    ctx.strokePath()
    ctx.restoreGState()
}

func draw(into ctx: CGContext, size s: CGFloat) {
    // --- The tile: Apple's icon grid (824/1024 centered, ~22.4% corners), a
    // light "painted wall" gradient, and the standard soft drop shadow.
    let inset = s * 100 / 1024
    let tile = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: tile.width * 0.2237, cornerHeight: tile.width * 0.2237, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.010), blur: s * 0.025, color: rgb(0, 0, 0, 0.30))
    ctx.addPath(tilePath)
    ctx.setFillColor(rgb(236, 238, 242))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()
    ctx.drawLinearGradient(gradient(rgb(250, 251, 253), rgb(214, 219, 227)), start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.minY), options: [])
    ctx.restoreGState()

    // --- The panel, drawn in the reference artwork's own coordinates:
    // 1254 px square, y pointing down; the object spans x 313–941,
    // y 138–1117. Scale it to 80% of the tile's height, centered.
    let k = (tile.height * 0.80) / (1117 - 138)
    ctx.saveGState()
    ctx.translateBy(x: tile.midX, y: tile.midY)
    ctx.scaleBy(x: k, y: -k)
    ctx.translateBy(x: -627, y: -627.5)

    let ink = rgb(22, 23, 25)
    let inkTop = rgb(48, 50, 54)
    let line = rgb(250, 250, 252)

    // Enclosure and conduit feet, with a soft contact shadow on the wall.
    let enclosure = roundedRect(313, 138, 628, 867, 62)
    let feet = CGMutablePath()
    for x in [445.0, 723.0] {
        feet.addPath(roundedRect(x, 1005, 85, 112, 14))
    }
    let body = CGMutablePath()
    body.addPath(enclosure)
    body.addPath(feet)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: rgb(0, 0, 0, 0.35))
    ctx.addPath(body)
    ctx.setFillColor(ink)
    ctx.fillPath()
    ctx.restoreGState()
    fill(ctx, feet, top: rgb(10, 10, 12), bottom: ink)
    // The gap between enclosure and conduits, as in the reference.
    ctx.setFillColor(rgb(0, 0, 0, 0.55))
    ctx.fill(CGRect(x: 440, y: 1005, width: 373, height: 14))
    fill(ctx, enclosure, top: inkTop, bottom: ink)
    // A faint top-edge highlight gives the metal box some form.
    stroke(ctx, roundedRect(320, 145, 614, 853, 56), rgb(255, 255, 255, 0.10), width: 5)

    // Hazard sign: the classic yellow triangle with a dark bolt.
    let triangle = CGMutablePath()
    triangle.move(to: CGPoint(x: 626, y: 236))
    triangle.addLine(to: CGPoint(x: 805, y: 543))
    triangle.addLine(to: CGPoint(x: 447, y: 543))
    triangle.closeSubpath()
    // Rounded corners come from stroking the outline with round joins; fill
    // the interior and that stroke separately with the same gradient (one
    // combined winding-rule clip leaves a seam along the inner edge).
    let signGradient = gradient(rgb(255, 222, 89), rgb(255, 184, 0))
    for region in [triangle, triangle.copy(strokingWithWidth: 27, lineCap: .round, lineJoin: .round, miterLimit: 10)] {
        ctx.saveGState()
        ctx.addPath(region)
        ctx.clip()
        ctx.drawLinearGradient(signGradient, start: CGPoint(x: 0, y: 222), end: CGPoint(x: 0, y: 557), options: [])
        ctx.restoreGState()
    }

    let bolt = CGMutablePath()
    bolt.addLines(between: [
        CGPoint(x: 640, y: 324), CGPoint(x: 570, y: 424), CGPoint(x: 612, y: 424),
        CGPoint(x: 590, y: 500), CGPoint(x: 666, y: 398), CGPoint(x: 624, y: 398),
    ])
    bolt.closeSubpath()
    ctx.addPath(bolt)
    ctx.setFillColor(ink)
    ctx.fillPath()
    stroke(ctx, bolt, ink, width: 12)

    // Breaker bank: a white-framed well holding three breakers, all on.
    stroke(ctx, roundedRect(363.5, 611.5, 528, 305, 60), line, width: 27)
    for x in [410.0, 567.0, 723.0] {
        stroke(ctx, roundedRect(x + 10, 680, 98, 170, 16), line, width: 20)
        ctx.addPath(roundedRect(x + 31, 709, 60, 57, 5))
        ctx.setFillColor(line)
        ctx.fillPath()
    }

    ctx.restoreGState()
}

for (name, px) in variants {
    let dim = CGFloat(px)
    guard let ctx = CGContext(
        data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { continue }
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high
    draw(into: ctx, size: dim)
    guard let image = ctx.makeImage() else { continue }
    let rep = NSBitmapImageRep(cgImage: image)
    guard let png = rep.representation(using: .png, properties: [:]) else { continue }
    try? png.write(to: URL(fileURLWithPath: "\(iconsetDir)/\(name)"))
}

print("✓ wrote \(variants.count) icons to \(iconsetDir)")
