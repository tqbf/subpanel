#!/usr/bin/env swift
//
// make-icon.swift — render the app icon at every macOS size.
//
// Draws a simple "document" glyph (a few text lines over a small table grid)
// on a rounded-rect tile with a soft gradient. Pure CoreGraphics, no assets,
// no dependencies — runs under plain `swift`. The Makefile runs
// `iconutil -c icns build/AppIcon.iconset` on the PNGs this writes.
//
// Replace the `drawGlyph` body with your own mark when you fork the template.

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

func draw(into ctx: CGContext, size s: CGFloat) {
    // Background tile — rounded rect with a soft vertical gradient.
    let inset = s * 0.06
    let tile = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let corner = s * 0.22
    let tilePath = CGPath(roundedRect: tile, cornerWidth: corner, cornerHeight: corner, transform: nil)

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let grad = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            CGColor(red: 0.30, green: 0.46, blue: 0.95, alpha: 1),
            CGColor(red: 0.16, green: 0.28, blue: 0.78, alpha: 1),
        ] as CFArray,
        locations: [0, 1])!
    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0), options: [])
    ctx.restoreGState()

    drawGlyph(into: ctx, tile: tile)
}

func drawGlyph(into ctx: CGContext, tile: CGRect) {
    // A white "page" centered in the tile.
    let pageW = tile.width * 0.52
    let pageH = pageW * 1.28
    let page = CGRect(
        x: tile.midX - pageW / 2,
        y: tile.midY - pageH / 2,
        width: pageW, height: pageH)
    let radius = pageW * 0.08
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.96))
    ctx.addPath(CGPath(roundedRect: page, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.fillPath()

    let accent = CGColor(red: 0.20, green: 0.34, blue: 0.85, alpha: 1)
    let muted = CGColor(red: 0.62, green: 0.68, blue: 0.82, alpha: 1)
    let padX = page.width * 0.16
    let lineH = page.height * 0.045
    let lineGap = page.height * 0.075

    // Three "text lines" at the top — the first (a heading) is accent-tinted
    // and wider; the next two are muted body lines.
    var y = page.maxY - page.height * 0.16
    let lineSpecs: [(CGColor, CGFloat)] = [
        (accent, 0.68), (muted, 0.56), (muted, 0.44),
    ]
    for (color, widthFraction) in lineSpecs {
        let bar = CGRect(
            x: page.minX + padX, y: y - lineH,
            width: (page.width - 2 * padX) * widthFraction, height: lineH)
        ctx.setFillColor(color)
        ctx.addPath(CGPath(roundedRect: bar, cornerWidth: lineH / 2, cornerHeight: lineH / 2, transform: nil))
        ctx.fillPath()
        y -= lineGap
    }

    // A small 2×3 "table" grid in the lower half — the data table.
    let gridTop = y - page.height * 0.04
    let gridRect = CGRect(
        x: page.minX + padX, y: page.minY + page.height * 0.14,
        width: page.width - 2 * padX, height: gridTop - (page.minY + page.height * 0.14))
    ctx.setStrokeColor(muted)
    ctx.setLineWidth(max(1, page.width * 0.012))
    ctx.addRect(gridRect)
    // Two interior verticals, one interior horizontal.
    for i in 1...2 {
        let x = gridRect.minX + gridRect.width * CGFloat(i) / 3
        ctx.move(to: CGPoint(x: x, y: gridRect.minY))
        ctx.addLine(to: CGPoint(x: x, y: gridRect.maxY))
    }
    let midY = gridRect.minY + gridRect.height / 2
    ctx.move(to: CGPoint(x: gridRect.minX, y: midY))
    ctx.addLine(to: CGPoint(x: gridRect.maxX, y: midY))
    ctx.strokePath()
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
