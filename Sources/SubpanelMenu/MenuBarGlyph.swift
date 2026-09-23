import AppKit

/// The menu-bar glyph: the app icon's breaker panel reduced to a monochrome
/// template silhouette (enclosure with the bolt and breaker well cut out,
/// three breakers, two conduit feet) that reads at 18 pt. As a template
/// image, macOS tints it for light, dark and highlighted menu bars.
/// Geometry mirrors `scripts/make-icon.swift`; see plans/design-system.md.
/// Lives in the menu-bar app (`SubpanelMenu`), the only thing in the menu bar.
@MainActor
enum MenuBarGlyph {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.addPath(path)
            context.setFillColor(NSColor.black.cgColor)
            context.fillPath(using: .evenOdd)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Subpanel"
        return image
    }()

    /// 18×18 pt, y-down. Filled with the even-odd rule: the bolt and the
    /// breaker well are holes; the breakers inside the well are filled again.
    private static var path: CGPath {
        let path = CGMutablePath()
        path.addPath(CGPath(roundedRect: CGRect(x: 3, y: 0.5, width: 12, height: 13.5), cornerWidth: 2.2, cornerHeight: 2.2, transform: nil))
        path.addLines(between: [
            CGPoint(x: 9.9, y: 1.9), CGPoint(x: 7.0, y: 5.6), CGPoint(x: 8.9, y: 5.6),
            CGPoint(x: 8.0, y: 8.1), CGPoint(x: 11.1, y: 4.6), CGPoint(x: 9.2, y: 4.6),
        ])
        path.closeSubpath()
        path.addPath(CGPath(roundedRect: CGRect(x: 4.6, y: 9.1, width: 8.8, height: 3.5), cornerWidth: 1, cornerHeight: 1, transform: nil))
        for x in [5.55, 8.1, 10.65] {
            path.addPath(CGPath(roundedRect: CGRect(x: x, y: 9.8, width: 1.8, height: 2.1), cornerWidth: 0.4, cornerHeight: 0.4, transform: nil))
        }
        for x in [5.4, 10.8] {
            path.addPath(CGPath(roundedRect: CGRect(x: x, y: 14.6, width: 1.8, height: 2.9), cornerWidth: 0.5, cornerHeight: 0.5, transform: nil))
        }
        return path
    }
}
