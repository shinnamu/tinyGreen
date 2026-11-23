import AppKit

// About 패널 — showAbout + NSTextView 링크 색 정규화.
// showAbout 은 builder.swift buildMenu 의 #selector(showAbout) 타깃.
extension StatusMenu {
    @objc func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        let body = """
        한/A·Caps Lock 키의 작은 확장.
        키 매퍼 없이, 전환 딜레이 없이, 작은 초록빛과 함께!


        """
        let linkText = "shinnamu-fyi.neocities.org"
        let credits = NSMutableAttributedString(
            string: body + linkText,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: para
            ]
        )
        // 기존 neocities link — 시스템 기본 파란색 + 밑줄.
        // 아래 normalizeAboutLinkColors() 가 NSTextView 의 default linkTextAttributes 의
        // foregroundColor 를 제거하므로, 여기서 명시적으로 박아야 색 유지됨.
        let range = (credits.string as NSString).range(of: linkText)
        credits.addAttribute(
            .link,
            value: URL(string: "https://shinnamu-fyi.neocities.org/")!,
            range: range
        )
        credits.addAttribute(.foregroundColor, value: NSColor.linkColor, range: range)
        credits.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)

        // "작은 초록빛" — 도구 자체로 가는 의미 있는 링크. systemGreen + 밑줄 없음.
        let greenWord = "작은 초록빛"
        let greenRange = (credits.string as NSString).range(of: greenWord)
        credits.addAttribute(
            .link,
            value: URL(string: "https://github.com/shinnamu/tinyGreen")!,
            range: greenRange
        )
        credits.addAttribute(.foregroundColor, value: NSColor.systemGreen, range: greenRange)
        credits.addAttribute(.underlineStyle, value: 0, range: greenRange)

        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "TinyGreen",
            .credits: credits
        ])

        // 표준 About 패널의 NSTextView 가 link 영역에 default linkColor + 밑줄을
        // 강제 override 해서 attributed string 의 per-range foregroundColor 가 무시됨.
        // linkTextAttributes 에서 foregroundColor 만 제거 → 위에 명시한 색이 살아남음.
        DispatchQueue.main.async { [weak self] in
            self?.normalizeAboutLinkColors()
        }
    }

    /// About 패널의 NSTextView 가 link 영역에 default linkColor 강제 적용하는 동작 우회.
    /// linkTextAttributes 에서 foregroundColor 키 제외 → attributed string 의 색이 그대로 보임.
    /// cursor 는 default 손가락 유지 (hover 시 클릭 가능 단서).
    func normalizeAboutLinkColors() {
        for window in NSApp.windows where window.isVisible {
            if let textView = Self.firstTextView(in: window.contentView) {
                // foregroundColor 와 underlineStyle 둘 다 비움 → attributed string 의
                // per-range 색/밑줄이 살아남. cursor 만 남겨 hover 손가락 유지.
                textView.linkTextAttributes = [
                    .cursor: NSCursor.pointingHand
                ]
            }
        }
    }

    private static func firstTextView(in view: NSView?) -> NSTextView? {
        guard let view = view else { return nil }
        if let tv = view as? NSTextView { return tv }
        for sub in view.subviews {
            if let found = firstTextView(in: sub) { return found }
        }
        return nil
    }
}
