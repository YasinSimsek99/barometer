import AppKit

enum StatusTextImage {
    static func make(text: String, isStale: Bool) -> NSImage {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(isStale ? 0.55 : 1),
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributed.size()
        let size = NSSize(width: ceil(textSize.width) + 2, height: 22)
        let image = NSImage(size: size, flipped: false) { rect in
            attributed.draw(at: NSPoint(
                x: 1,
                y: rect.midY - textSize.height / 2 + 0.35
            ))
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = text
        return image
    }
}
