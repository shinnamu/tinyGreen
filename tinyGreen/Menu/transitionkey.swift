import AppKit

// 전환 키 메뉴 — 실제 전환/매핑은 코어(Remap)가 소유하고, 이 파일은 선택 표면만 만든다.
extension StatusMenu {
    private static let transitionKeyChoices: [TransitionKey] = [.capsLock, .rightCommand]

    /// 선택한 키를 F19 경유 시스템 입력 소스 단축키에 연결한다.
    /// 한영 전환 자체는 macOS가 수행하고, tinyGreen은 결과를 LED/메뉴 막대에 비춘다.
    func buildTransitionKeyMenuItem() -> NSMenuItem {
        let subMenu = NSMenu(title: "한/영 전환 키")
        subMenu.showsStateColumn = true

        transitionKeyItems = Self.transitionKeyChoices.map { key in
            let item = NSMenuItem(title: key.menuTitle, action: #selector(selectTransitionKey(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = key
            item.state = key == Settings.transitionKey ? .on : .off
            // 고르는 자리에서 그 선택의 배선 결과까지 보여준다 — 대문자 잠금이
            // 모드마다 다른 키에 얹히는 것이 이 메뉴의 유일한 숨은 차이라서.
            // 별도 설명 줄 대신 항목의 공식 부속(subtitle) — 시스템 두 줄 메뉴 문법.
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

    /// 메뉴를 다시 열었을 때 코어가 보관한 현재 선택을 라디오에 반영한다.
    /// callback 실패 뒤에도 호출해, 시각 상태가 실제 설정과 어긋나지 않게 한다.
    func syncTransitionKeyMenu(to selected: TransitionKey? = nil) {
        let current = selected ?? Settings.transitionKey
        for item in transitionKeyItems {
            guard let key = item.representedObject as? TransitionKey else { continue }
            item.state = key == current ? .on : .off
        }
    }
}
