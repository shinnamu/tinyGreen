import AppKit

// 기능 키 메뉴 — 배선은 코어(Remap·Router)가 소유하고, 이 파일은 켜고 끄는 표면만 만든다(ADR-0008).
extension StatusMenu {
    func buildExtraKeyMenuItem() -> NSMenuItem {
        let subMenu = NSMenu(title: "기능 키")
        subMenu.showsStateColumn = false

        extraItems = ExtraKey.allCases.map { key in
            let item = NSMenuItem(title: key.menuTitle, action: #selector(toggleExtraKey(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = key
            subMenu.addItem(item)
            return item
        }
        syncExtraKeyMenu()

        let item = NSMenuItem(title: "기능 키", action: nil, keyEquivalent: "")
        item.submenu = subMenu
        item.image = Glyphs.symbol("command")
        return item
    }

    /// 켜짐 ✓ 와, 모드 때문에 배선에서 빠진 항목의 비활성·이유를 다시 그린다.
    func syncExtraKeyMenu() {
        let mode = Settings.transitionKey
        let effective = ExtraWiring.effective(enabled: Set(ExtraKey.allCases), mode: mode)
        for item in extraItems {
            guard let key = item.representedObject as? ExtraKey else { continue }
            let available = effective.contains(key)
            item.image = Settings.extraEnabled(key) ? Glyphs.checkmark : Glyphs.stateDotEmpty
            item.isEnabled = available
            if #available(macOS 14.4, *) {
                item.subtitle = available ? nil : "Right Command 모드에서는 Caps Lock이 F18을 씁니다"
            }
        }
    }

    @objc func toggleExtraKey(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? ExtraKey, let onExtraChange else { return }
        _ = onExtraChange(key, !Settings.extraEnabled(key))
        syncExtraKeyMenu()
    }
}
