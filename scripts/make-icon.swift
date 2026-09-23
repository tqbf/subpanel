#!/usr/bin/env swift
//
// make-icon.swift — render the app icon at every macOS size.
//
// Subpanel's mark: a white panel of three rows on a deep teal tile. Each row
// is a status dot and a bar — a name routed to a backend, the same
// vocabulary as the app's menu and table. Pure CoreGraphics, no assets, no
// dependencies — runs under plain `swift`. The Makefile runs
// `iconutil -c icns build/AppIcon.iconset` on the PNGs this writes.

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
            CGColor(red: 0.13, green: 0.55, blue: 0.60, alpha: 1),
            CGColor(red: 0.06, green: 0.30, blue: 0.40, alpha: 1),
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
    // A white panel, wider than tall, centered in the tile.
    let panelW = tile.width * 0.64
    let panelH = tile.height * 0.50
    let panel = CGRect(x: tile.midX - panelW / 2, y: tile.midY - panelH / 2, width: panelW, height: panelH)
    let radius = panelW * 0.08
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.97))
    ctx.addPath(CGPath(roundedRect: panel, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.fillPath()

    let live = CGColor(red: 0.16, green: 0.72, blue: 0.45, alpha: 1)
    let ink = CGColor(red: 0.10, green: 0.36, blue: 0.44, alpha: 1)
    let muted = CGColor(red: 0.70, green: 0.78, blue: 0.80, alpha: 1)

    // Three rows: dot + bar. The last row's backend is "down" (hollow dot).
    let rows = 3
    let pad = panel.height * 0.17
    let rowPitch = (panel.height - 2 * pad) / CGFloat(rows - 1)
    let dot = panel.height * 0.14
    let barH = panel.height * 0.09
    let barX = panel.minX + panel.width * 0.12 + dot + panel.width * 0.06
    let widths: [CGFloat] = [0.62, 0.48, 0.55]
    for row in 0..<rows {
        let cy = panel.maxY - pad - CGFloat(row) * rowPitch
        let dotRect = CGRect(x: panel.minX + panel.width * 0.12, y: cy - dot / 2, width: dot, height: dot)
        if row < rows - 1 {
            ctx.setFillColor(live)
            ctx.fillEllipse(in: dotRect)
        } else {
            ctx.setStrokeColor(muted)
            ctx.setLineWidth(max(1, dot * 0.2))
            ctx.strokeEllipse(in: dotRect.insetBy(dx: dot * 0.1, dy: dot * 0.1))
        }
        let barW = (panel.maxX - barX - panel.width * 0.1) * widths[row] / 0.62
        let bar = CGRect(x: barX, y: cy - barH / 2, width: barW, height: barH)
        ctx.setFillColor(row < rows - 1 ? ink : muted)
        ctx.addPath(CGPath(roundedRect: bar, cornerWidth: barH / 2, cornerHeight: barH / 2, transform: nil))
        ctx.fillPath()
    }
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
