import AppKit
import SwiftUI

/// Development aid: `SUBPANEL_SNAPSHOT_DIR=/tmp/shots open build/Subpanel.app`
/// (or run the binary with that variable) opens every window, renders each to
/// a PNG with `cacheDisplay` — the app's own pixels, so no Screen Recording
/// permission is needed — and quits. `SUBPANEL_SNAPSHOT_APPEARANCE=dark`
/// renders dark mode. This is how UI changes get a visual check from an
/// agent shell (SWIFTUI-RULES §9.3); see plans/design-system.md.
@MainActor
enum DevSnapshot {
    static var directory: URL? {
        ProcessInfo.processInfo.environment["SUBPANEL_SNAPSHOT_DIR"].map { URL(filePath: $0) }
    }

    static func run(openWindow: OpenWindowAction, openSettings: OpenSettingsAction) async {
        guard let directory else { return }
        if ProcessInfo.processInfo.environment["SUBPANEL_SNAPSHOT_APPEARANCE"] == "dark" {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        openWindow(id: WindowID.welcome)
        openWindow(id: WindowID.apps)
        openSettings()
        try? await Task.sleep(for: .seconds(3))

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for window in NSApp.windows where window.isVisible && window.frame.width > 100 {
            guard let png = windowServerImage(window) ?? (window.contentView?.superview).flatMap(render)
            else { continue }
            let name = window.title.isEmpty ? "window-\(window.windowNumber)" : window.title
            try? png.write(to: directory.appending(path: name.replacing(" ", with: "-") + ".png"))
        }
        NSApp.terminate(nil)
    }

    /// The window exactly as composited, via the window server. An app may
    /// always capture its *own* windows without Screen Recording permission.
    /// `CGWindowListCreateImage` is marked unavailable to Swift (Apple wants
    /// ScreenCaptureKit, which does need permission) but still exists, so
    /// this dev-only path looks it up at runtime.
    private static func windowServerImage(_ window: NSWindow) -> Data? {
        typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else { return nil }
        let create = unsafeBitCast(symbol, to: CreateImage.self)
        let optionIncludingWindow: UInt32 = 1 << 3
        let boundsIgnoreFraming: UInt32 = 1 << 0
        guard let image = create(.null, optionIncludingWindow, UInt32(window.windowNumber), boundsIgnoreFraming)?
            .takeRetainedValue()
        else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    /// Fallback: renders the view's layer tree — what's actually composited, including
    /// layer-backed SwiftUI content inside scroll views that `cacheDisplay`
    /// misses (grouped Forms render blank with it).
    private static func render(_ view: NSView) -> Data? {
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        guard let layer = view.layer else { return nil }
        let scale = view.window?.backingScaleFactor ?? 2
        let width = Int(view.bounds.width * scale)
        let height = Int(view.bounds.height * scale)
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(NSColor.windowBackgroundColor.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        if layer.isGeometryFlipped == false, view.isFlipped {
            context.translateBy(x: 0, y: view.bounds.height)
            context.scaleBy(x: 1, y: -1)
        }
        layer.render(in: context)
        guard let image = context.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}
