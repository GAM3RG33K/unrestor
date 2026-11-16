import AppKit
import SwiftUI

/// The menu-bar icon, drawn from the same SVG files as every other Unrestor
/// icon (assets/icon/unrestor-glyph*.svg, copied into the app's Resources).
///
/// A MenuBarExtra label must be a plain Image, so the SVG is drawn into a
/// template NSImage: macOS then recolors it for light, dark, and highlighted
/// menu bars, using only the alpha channel.
enum MenuBarGlyph {
    private static let side: CGFloat = 18

    static func image(awake: Bool) -> Image {
        let name = awake ? "unrestor-glyph" : "unrestor-glyph-resting"
        guard let url = Bundle.main.url(forResource: name, withExtension: "svg"),
              let svg = NSImage(contentsOf: url)
        else {
            // Running from `swift run`, outside the app bundle.
            return Image(systemName: awake ? "eye.fill" : "eye.slash")
        }
        let template = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            svg.draw(in: rect)
            return true
        }
        template.isTemplate = true
        return Image(nsImage: template)
    }
}
