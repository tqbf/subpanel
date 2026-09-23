import AppKit

/// Development aid: with `SUBPANEL_SNAPSHOT_DIR` set, opens the menu once,
/// photographs it (the app's own windows, through the window server — no
/// Screen Recording permission needed), writes `menu.png`, and exits.
/// `SUBPANEL_SNAPSHOT_APPEARANCE=dark` renders dark mode. The same trick as
/// the main app's `DevSnapshot` (plans/design-system.md).
@MainActor
enum MenuSnapshot {
    static func runIfRequested() async {
        guard let directory = ProcessInfo.processInfo.environment["SUBPANEL_SNAPSHOT_DIR"].map({ URL(filePath: $0) }) else {
            return
        }
        if ProcessInfo.processInfo.environment["SUBPANEL_SNAPSHOT_APPEARANCE"] == "dark" {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        // Let the first poll land so the menu has content.
        try? await Task.sleep(for: .seconds(2))
        guard let button = NSApp.windows.lazy.compactMap({ statusButton(in: $0.contentView) }).first else {
            exit(1)
        }
        // The menu runs a modal tracking loop inside performClick, so the
        // capture has to be a timer that fires in the event-tracking mode.
        let timer = Timer(timeInterval: 1.0, repeats: false) { _ in
            MainActor.assumeIsolated { capture(into: directory) }
            exit(0)
        }
        RunLoop.main.add(timer, forMode: .common)
        button.performClick(nil)
    }

    private static func statusButton(in view: NSView?) -> NSStatusBarButton? {
        guard let view else { return nil }
        if let button = view as? NSStatusBarButton { return button }
        return view.subviews.lazy.compactMap { statusButton(in: $0) }.first
    }

    private static func capture(into directory: URL) {
        typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage"),
              let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]]
        else { return }
        let create = unsafeBitCast(symbol, to: CreateImage.self)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // The menu is our largest on-screen window (the status item is tiny).
        let mine = windows.filter { ($0[kCGWindowOwnerPID as String] as? Int32) == getpid() }
        let menu = mine.max {
            area($0[kCGWindowBounds as String]) < area($1[kCGWindowBounds as String])
        }
        guard let number = menu?[kCGWindowNumber as String] as? UInt32,
              let image = create(.null, 1 << 3, number, 1 << 0)?.takeRetainedValue(),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { return }
        try? png.write(to: directory.appending(path: "menu.png"))
    }

    private static func area(_ bounds: Any?) -> CGFloat {
        guard let dictionary = bounds as? NSDictionary,
              let rect = CGRect(dictionaryRepresentation: dictionary)
        else { return 0 }
        return rect.width * rect.height
    }
}
