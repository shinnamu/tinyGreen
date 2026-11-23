import AppKit

/// 메뉴 글리프 — 메뉴 항목 이미지/타이틀 (✓·라디오 도트·한/A 박스 타이틀·SF Symbol).
/// 모두 dynamic 색 + isTemplate vibrancy 매칭. 그리기 원시는 Indication/render(Render.dotImage·drawBox)를 빌린다.
enum Glyphs {

    /// 메뉴 항목 이미지 표준 — menu font (default 13pt) 와 매칭.
    /// HIG: SF Symbol weight/scale 은 인접 텍스트 metric 에 맞춰야 정렬됨.
    private static let menuSymbolConfig = NSImage.SymbolConfiguration(
        pointSize: 13, weight: .regular, scale: .medium
    )

    /// SF Symbol (info.circle 등) — template, 다크/라이트 자동.
    static func symbol(_ name: String) -> NSImage? {
        let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        let configured = img?.withSymbolConfiguration(menuSymbolConfig)
        configured?.isTemplate = true
        return configured
    }

    /// 토글 ✓ — state column 대신 image column 에 배치 (native 너비 매칭).
    static let checkmark: NSImage? = symbol("checkmark")

    /// 서브메뉴 라디오 선택 표시 — 6pt 초록 도트.
    static let stateDot: NSImage = menuDot(.systemGreen)

    /// 라디오 미선택 자리에 두는 투명 placeholder — image column 너비 일관 유지 (stateDot 와 동일 canvas).
    static let stateDotEmpty: NSImage = NSImage(size: NSSize(width: 12, height: 12))

    /// 경고/에러 표시 — 6pt 주황 도트 (메뉴 아이템 image column).
    /// macOS 창 제어 버튼 메타포: 주황 = minimize 톤 = warning/caution (recoverable).
    static let errorDot: NSImage = menuDot(.systemOrange)

    /// 종료 액션 표시 — 6pt 빨간 도트 (메뉴 아이템 image column).
    /// macOS 창 제어 버튼 메타포: 빨강 = close 톤 = destructive (프로세스 종료).
    static let quitDot: NSImage = menuDot(.systemRed)

    /// "한" filled 박스 + suffix — 한 번만 만들어 캐시.
    static let hanTitle: NSAttributedString = boxedTitle(char: "한", filled: true, suffix: "에서")
    /// "A" stroke 박스 + suffix — 한 번만 만들어 캐시.
    static let aTitle: NSAttributedString = boxedTitle(char: "A", filled: false, suffix: "에서")

    // MARK: - Private helpers

    /// 메뉴 아이템 image column 도트 — 12×12 canvas, 6pt diameter, non-template (고정 색).
    private static func menuDot(_ color: NSColor) -> NSImage {
        Render.dotImage(canvas: NSSize(width: 12, height: 12), diameter: 6, color: color, template: false)
    }

    /// NSTextAttachment baseline 보정 — image bottom 이 텍스트 baseline 보다 ~3pt 아래.
    /// 메뉴 폰트 metric 의존이라 명명 상수.
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

    /// 박스 (라운드 사각) + 글자. macOS native input source indicator 매칭.
    /// 박스 22×16, stroke outer edge fit. template image — `controlTextColor` 는 시스템 vibrancy 가 덮음.
    /// 그리기는 Render.drawBox 를 빌림 (그리기 원시는 render 소유).
    private static func boxImage(char: String, filled: Bool) -> NSImage {
        let size = NSSize(width: 22, height: 16)
        let img = NSImage(size: size, flipped: false) { rect in
            Render.drawBox(in: rect, char: char, filled: filled, color: .controlTextColor)
            return true
        }
        // template → 시스템 alpha 채널만 사용, 색 + vibrancy 자동 (메뉴 글자색 매칭)
        img.isTemplate = true
        return img
    }
}
