import AppKit

extension StatusMenu {
    private static let transitionKeyChoices: [TransitionKey] = [.capsLock, .rightCommand]

    func buildTransitionKeyMenuItem() -> NSMenuItem {
        let subMenu = NSMenu(title: "한/영 전환 키")
        subMenu.showsStateColumn = true

        transitionKeyItems = Self.transitionKeyChoices.map { key in
            let item = NSMenuItem(title: key.menuTitle, action: #selector(selectTransitionKey(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = key
            item.state = key == Settings.transitionKey ? .on : .off
            if #available(macOS 14.4, *) {
                item.subtitle = "영문 대문자 잠금 \(key.lockKeyGlyphs)"
            }
            item.setAccessibilityLabel("\(key.menuTitle)를 전환 키로 사용 — 영문 대문자 잠금은 \(key.lockKeyGlyphs)")
            subMenu.addItem(item)
            return item
        }

        let item = NSMenuItem(title: "한/영 전환 키", action: nil, keyEquivalent: "")
        item.submenu = subMenu
        item.image = Glyphs.symbol("keyboard")
        transitionKeyMenuItem = item
        return item
    }

    func syncTransitionKeyMenu(to selected: TransitionKey? = nil) {
        let current = selected ?? Settings.transitionKey
        for item in transitionKeyItems {
            guard let key = item.representedObject as? TransitionKey else { continue }
            item.state = key == current ? .on : .off
        }
    }
}
