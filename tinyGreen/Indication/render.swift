import AppKit
import CoreText
import SwiftUI

enum Render {


    static func menuBarDot(active: Bool, error: Bool = false) -> NSImage {
        let canvas = NSSize(width: 6, height: NSStatusBar.system.thickness)
        if error {
            return dotImage(canvas: canvas, diameter: 6, color: .systemOrange, template: false)
        }
        let color: NSColor = active ? .systemGreen : .black
        return dotImage(canvas: canvas, diameter: 6, color: color, template: !active)
    }

    static func menuBarInputSourceImage(wide: Bool, lit: Bool, isKorean: Bool) -> NSImage {
        let charAreaWidth: CGFloat = 22
        let extraLeft: CGFloat = wide ? 2 : 0
        let boxWidth: CGFloat = charAreaWidth + extraLeft
        let boxHeight: CGFloat = 16
        let canvas = NSSize(width: boxWidth, height: NSStatusBar.system.thickness)
        let img = NSImage(size: canvas, flipped: false) { rect in
            let boxRect = NSRect(
                x: 0,
                y: (rect.height - boxHeight) / 2,
                width: boxWidth,
                height: boxHeight
            )
            let charBoxRect: NSRect? = wide
                ? NSRect(x: boxRect.minX + extraLeft, y: boxRect.minY, width: charAreaWidth, height: boxHeight)
                : nil
            let boxFilled = wide ? true : isKorean
            drawBox(in: boxRect, charBox: charBoxRect, char: isKorean ? "한" : "A", filled: boxFilled, color: menuBarGlyphColor)

            if wide {
                let dotDiameter: CGFloat = 3
                let inset: CGFloat = 3
                let dotRect = NSRect(
                    x: boxRect.minX + inset,
                    y: boxRect.maxY - dotDiameter - inset,
                    width: dotDiameter,
                    height: dotDiameter
                )
                if lit {
                    NSColor.systemGreen.setFill()
                    NSBezierPath(ovalIn: dotRect).fill()
                } else {
                    NSGraphicsContext.current?.cgContext.setBlendMode(.destinationOut)
                    NSBezierPath(ovalIn: dotRect).fill()
                    NSGraphicsContext.current?.cgContext.setBlendMode(.normal)
                }
            }
            return true
        }
        img.isTemplate = false
        img.cacheMode = .never
        return img
    }

    static func menuBarInputSourceImageGreen(isKorean: Bool) -> NSImage {
        let boxWidth: CGFloat = 22
        let boxHeight: CGFloat = 16
        let canvas = NSSize(width: boxWidth, height: NSStatusBar.system.thickness)
        let img = NSImage(size: canvas, flipped: false) { rect in
            let boxRect = NSRect(
                x: 0,
                y: (rect.height - boxHeight) / 2,
                width: boxWidth,
                height: boxHeight
            )
            drawBox(in: boxRect, char: isKorean ? "한" : "A", filled: isKorean, color: .systemGreen)
            return true
        }
        img.isTemplate = false
        img.cacheMode = .never
        return img
    }


    static func dotImage(canvas: NSSize, diameter: CGFloat, color: NSColor, template: Bool) -> NSImage {
        let img = NSImage(size: canvas, flipped: false) { rect in
            let dot = NSRect(
                x: (rect.width - diameter) / 2,
                y: (rect.height - diameter) / 2,
                width: diameter,
                height: diameter
            )
            color.setFill()
            NSBezierPath(ovalIn: dot).fill()
            return true
        }
        img.isTemplate = template
        return img
    }

    static func drawBox(in rect: NSRect, charBox: NSRect? = nil, char: String, filled: Bool, color: NSColor) {
        let font = indicatorFont(size: 12)
        let textSize = NSAttributedString(string: char, attributes: [.font: font]).size()
        let charRect = charBox ?? rect
        let textPoint = NSPoint(
            x: charRect.minX + (charRect.width - textSize.width) / 2,
            y: charRect.minY + (charRect.height - textSize.height) / 2
        )
        let textColor: NSColor = filled ? .black : color

        if filled {
            color.setFill()
            continuousRoundedRect(rect, radius: 5).fill()
            NSGraphicsContext.current?.cgContext.setBlendMode(.destinationOut)
        } else {
            color.setStroke()
            let inset: CGFloat = 0.5
            let path = continuousRoundedRect(rect.insetBy(dx: inset, dy: inset), radius: 5)
            path.lineWidth = 1
            path.stroke()
        }
        NSAttributedString(string: char, attributes: [
            .font: font,
            .foregroundColor: textColor
        ]).draw(at: textPoint)
        if filled {
            NSGraphicsContext.current?.cgContext.setBlendMode(.normal)
        }
    }


    private static let indicatorFontRegistered: Bool = {
        guard let url = Bundle.main.url(forResource: "tg-indicator", withExtension: "otf") else {
            return false
        }
        return CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }()

    private static func indicatorFont(size: CGFloat) -> NSFont {
        if indicatorFontRegistered, let f = NSFont(name: "tinyGreen Indicator", size: size) {
            return f
        }
        return NSFont.systemFont(ofSize: size, weight: .semibold)
    }

    private static let menuBarGlyphColor: NSColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil ? .white : .black
    }

    private static func continuousRoundedRect(_ rect: NSRect, radius: CGFloat) -> NSBezierPath {
        let cg = RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect).cgPath
        let path = NSBezierPath()
        cg.applyWithBlock { ptr in
            let e = ptr.pointee
            switch e.type {
            case .moveToPoint:
                path.move(to: e.points[0])
            case .addLineToPoint:
                path.line(to: e.points[0])
            case .addQuadCurveToPoint:
                let s = path.currentPoint, cp = e.points[0], end = e.points[1]
                path.curve(to: end,
                           controlPoint1: NSPoint(x: s.x + 2.0/3.0 * (cp.x - s.x),
                                                  y: s.y + 2.0/3.0 * (cp.y - s.y)),
                           controlPoint2: NSPoint(x: end.x + 2.0/3.0 * (cp.x - end.x),
                                                  y: end.y + 2.0/3.0 * (cp.y - end.y)))
            case .addCurveToPoint:
                path.curve(to: e.points[2], controlPoint1: e.points[0], controlPoint2: e.points[1])
            case .closeSubpath:
                path.close()
            @unknown default:
                break
            }
        }
        return path
    }
}
