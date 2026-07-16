import AppKit

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
        let range = (credits.string as NSString).range(of: linkText)
        credits.addAttribute(
            .link,
            value: URL(string: "https://shinnamu-fyi.neocities.org/")!,
            range: range
        )
        credits.addAttribute(.foregroundColor, value: NSColor.linkColor, range: range)
        credits.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)

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
            .applicationName: "tinyGreen",
            .credits: credits
        ])

        DispatchQueue.main.async { [weak self] in
            self?.normalizeAboutLinkColors()
        }
    }

    func normalizeAboutLinkColors() {
        for window in NSApp.windows where window.isVisible {
            if let textView = Self.firstTextView(in: window.contentView) {
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
