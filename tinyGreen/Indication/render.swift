import AppKit
import CoreText
import SwiftUI

/// 비춤의 생김새 — 메뉴바 상태이미지 + 그리기 원시(도트·박스·라운드 path·폰트).
/// 도형은 dynamic 색 + isTemplate vibrancy 매칭. Menu/glyphs 가 원시(dotImage·drawBox)를 빌린다.
enum Render {

    // MARK: - 상태이미지 (메뉴바)

    /// 메뉴바 도트 — 활성=systemGreen raster, 비활성=template (시스템 vibrancy 자동), 경고=systemOrange raster.
    /// 색 시멘틱: 초록=active, 주황=warning(에러), 빨강=destructive(종료) — macOS 창 제어 버튼 매핑.
    static func menuBarDot(active: Bool, error: Bool = false) -> NSImage {
        let canvas = NSSize(width: 6, height: NSStatusBar.system.thickness)
        if error {
            return dotImage(canvas: canvas, diameter: 6, color: .systemOrange, template: false)
        }
        let color: NSColor = active ? .systemGreen : .black
        return dotImage(canvas: canvas, diameter: 6, color: color, template: !active)
    }

    /// 입력 소스 박스 메뉴바 이미지 — "입력 소스 보기" ON 시 사용.
    /// `wide` — 메뉴바 LED 사용 토글 ON 여부. true 면 박스 24×16 (좌측 2pt 비대칭 확장, 도트 자리 보호), false 면 22×16 (대칭).
    /// `lit` — 현재 입력 언어가 LED 켜는 언어인지 (`menuBarLEDShouldBeOn`). true 면 좌상단 3pt 초록 도트.
    /// `wide=true`+`lit=false` 일 때는 박스만 넓고 도트 없음 (자리만 보호 — 토글 시 layout shift 방지).
    /// `wide=false` 면 lit 무시 (도트 자리 없음 → 도트 없음).
    /// 박스 색 menuBarGlyphColor (다이나믹), 도트 systemGreen.
    /// `cacheMode = .never` — appearance 변화 시 stale 캐시 방지.
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
            // wide=true 면 글자는 우측 22pt 안에서 중앙 정렬 (좌측 2pt 도트 자리 보호).
            // wide=false 면 charBox=nil → drawBox 가 boxRect 전체 기준 중앙 정렬 (대칭).
            let charBoxRect: NSRect? = wide
                ? NSRect(x: boxRect.minX + extraLeft, y: boxRect.minY, width: charAreaWidth, height: boxHeight)
                : nil
            // wide=true (도트 같이) 면 박스 항상 filled — 한/A 구분 신호는 도트 (cutout vs 초록 fill) 가 담당.
            // wide=false (showInputSource only) 면 macOS 기본 패턴 (한 filled / A outline).
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
                    // LED 켜짐 → 초록 fill 도트 (cutout 자리에 paint).
                    NSColor.systemGreen.setFill()
                    NSBezierPath(ovalIn: dotRect).fill()
                } else {
                    // LED 꺼짐 → 도트 자리 cutout (구멍, vibrancy 비침). 한/A 분기 없음 — 박스 항상 filled 라
                    // cutout 패턴 일관 적용 가능. 사용자 의도: cutout 이 base, lit 시 그 위에 초록 fill paint.
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

    /// 메뉴바 박스 (narrow 22×16) systemGreen variant — Shift Lock 깜빡임 phase.
    /// 박스만 (LED OFF + 입력 소스 보기 ON) 케이스에서 정상 ↔ green 토글용.
    /// 한 = fill green (cutout 글자), A = stroke green (글자 green).
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

    // MARK: - 그리기 원시 — glyphs 가 빌림 (internal)

    /// 도트 이미지 — glyphs(stateDot·errorDot·quitDot) + menuBarDot 공유.
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

    /// 박스 (라운드 사각) + 글자를 주어진 rect 에 직접 그리기 — glyphs(boxImage) + menuBarInputSource 공유.
    /// filled = solid fill + cut-out (글자 자리 transparent → vibrancy 비침).
    /// !filled = stroke 박스 + 글자만 color.
    /// 글자 폰트 = Pretendard 서브셋 (indicatorFont). 한/A 균일 12pt — 옛 A-only
    /// 0.5pt hand-tune 은 matched metric 으로 불필요해져 제거 (2026-05-18).
    /// 합성 이미지 (메뉴바 도트+박스) 와 standalone boxImage 양쪽에서 재사용.
    /// `color` 호출처 명시:
    ///   - 메뉴 항목용 boxImage(template) → `.controlTextColor` (시스템 vibrancy 가 덮으니 의도 표시)
    ///   - 메뉴바 composite(non-template) → `menuBarGlyphColor` (full contrast 다이나믹).
    /// `charBox` — 글자 중앙 정렬 영역. nil 이면 `rect` 사용 (기본 — symmetric box).
    /// 박스 좌측 비대칭 확장 시 (메뉴바 입력 소스 박스) 글자는 원래 영역 안에서 중앙 유지하도록 사용.
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

    // MARK: - 그리기 원시 — render 내부 전용 (private)

    /// Pretendard 서브셋 (Resources/Fonts/tg-indicator.otf, family "tinyGreen Indicator").
    /// OFL-1.1, RFN 회피 리네임, 1.7KB (한·A 글자만). 1회 .process 등록.
    private static let indicatorFontRegistered: Bool = {
        guard let url = Bundle.main.url(forResource: "tg-indicator", withExtension: "otf") else {
            return false
        }
        return CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }()

    /// 메뉴바 한/A 박스 글자 폰트. Pretendard 서브셋 — 한/A metric 이 설계로 맞춰져
    /// 옛 hand-tune (filled ? 12 : 12.5pt) 불필요 (mockup 실측 확인, 2026-05-18).
    /// 로드 실패 시 시스템 semibold 폴백 — 폰트 없어도 동작 (안전).
    private static func indicatorFont(size: CGFloat) -> NSFont {
        if indicatorFontRegistered, let f = NSFont(name: "tinyGreen Indicator", size: size) {
            return f
        }
        return NSFont.systemFont(ofSize: size, weight: .semibold)
    }

    /// 메뉴바 글자 색 매칭 — pure black/white (alpha 1.0) 다이나믹.
    /// `controlTextColor` 의 alpha 0.85 보다 contrast 높음 — template image vibrancy 와 매칭.
    /// composite 메뉴바 이미지 (template 처리 불가) 에서 풀-콘트라스트 유지 용도.
    private static let menuBarGlyphColor: NSColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil ? .white : .black
    }

    /// Apple 현행 'continuous' corner. SwiftUI `RoundedRectangle(.continuous)` 가
    /// 그리는 path 를 그대로 사용 — Apple OS 코드가 직접 생성하므로 *정의상* 동일
    /// (PaintCode iOS7 역추출 근사 폐기). deployment 13.0 라 `NSBezierPath(cgPath:)`
    /// (macOS14+) 불가 → CGPath 를 `applyWithBlock` 으로 순회해 NSBezierPath 재구성.
    /// NSBezierPath 반환 이유: drawBox 의 NSColor fill/stroke·destinationOut cutout·
    /// dynamic 색(menuBarGlyphColor 등) 흐름을 한 줄도 안 건드리려 — 회귀 표면 0.
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
                // NSBezierPath 는 cubic 만 — quad → cubic 승격
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
