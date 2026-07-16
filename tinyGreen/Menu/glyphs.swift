import AppKit

enum Glyphs {

    private static let menuSymbolConfig = NSImage.SymbolConfiguration(
        pointSize: 13, weight: .regular, scale: .medium
    )

    static func symbol(_ name: String) -> NSImage? {
        let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        let configured = img?.withSymbolConfiguration(menuSymbolConfig)
        configured?.isTemplate = true
        return configured
    }

    static let checkmark: NSImage? = symbol("checkmark")

    static let stateDot: NSImage = menuDot(.systemGreen)

    static let stateDotEmpty: NSImage = NSImage(size: NSSize(width: 12, height: 12))

    static let errorDot: NSImage = menuDot(.systemOrange)

    static let quitDot: NSImage = menuDot(.systemRed)

    static let hanTitle: NSAttributedString = boxedTitle(char: "한", filled: true, suffix: "에서")
    static let aTitle: NSAttributedString = boxedTitle(char: "A", filled: false, suffix: "에서")


    private static func menuDot(_ color: NSColor) -> NSImage {
        Render.dotImage(canvas: NSSize(width: 12, height: 12), diameter: 6, color: color, template: false)
    }

    private static let attachmentBaselineOffset: CGFloat = -3

    private static func boxedTitle(char: String, filled: Bool, suffix: String) -> NSAttributedString {
        let img = boxImage(char: char, filled: filled)
        let attachment = NSTextAttachment()
        attachment.image = img
        attachment.bounds = NSRect(
            x: 0,
            y: attachmentBaselineOffset,
            width: img.size.width,
            height: img.size.height
        )
        let result = NSMutableAttributedString()
        result.append(NSAttributedString(attachment: attachment))
        result.append(NSAttributedString(
            string: " " + suffix,
            attributes: [.font: NSFont.menuFont(ofSize: 0)]
        ))
        return result
    }

    private static func boxImage(char: String, filled: Bool) -> NSImage {
        let size = NSSize(width: 22, height: 16)
        let img = NSImage(size: size, flipped: false) { rect in
            Render.drawBox(in: rect, char: char, filled: filled, color: .controlTextColor)
            return true
        }
        img.isTemplate = true
        return img
    }
}
