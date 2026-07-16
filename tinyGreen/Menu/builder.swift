import AppKit

extension StatusMenu {
    func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.showsStateColumn = false
        menu.delegate = self

        let about = NSMenuItem(title: "tinyGreen에 관하여", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        about.image = Glyphs.symbol("info.circle")
        menu.addItem(about)

        let error = NSMenuItem(title: "", action: #selector(errorItemClicked), keyEquivalent: "")
        error.target = self
        error.image = Glyphs.errorDot
        error.isHidden = true
        errorItem = error
        menu.addItem(error)

        let secure = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        secure.image = Glyphs.symbol("lock.fill")
        secure.isEnabled = false
        secure.isHidden = true
        secureInputItem = secure
        menu.addItem(secure)

        menu.addItem(NSMenuItem.separator())

        let showSource = NSMenuItem(title: "입력 소스 보기", action: #selector(toggleShowInputSource(_:)), keyEquivalent: "")
        showSource.target = self
        setShowInputSourceImage(showSource)
        menu.addItem(showSource)

        menu.addItem(buildShiftLockMenuItem())

        menu.addItem(buildLEDMenuItem(kind: .menuBar))
        menu.addItem(buildLEDMenuItem(kind: .capsLock))

        menu.addItem(NSMenuItem.separator())

        let hide = NSMenuItem(title: "메뉴 막대에서 숨기기", action: #selector(hideMenuBarIcon), keyEquivalent: "")
        hide.target = self
        hide.image = Glyphs.symbol("eye.slash")
        menu.addItem(hide)

        let login = NSMenuItem(title: "로그인 시 열기", action: #selector(toggleLoginItem(_:)), keyEquivalent: "")
        login.target = self
        setLoginImage(login)
        loginMenuItem = login
        menu.addItem(login)

        let quit = NSMenuItem(title: "tinyGreen 종료", action: #selector(quitClicked), keyEquivalent: "q")
        quit.target = self
        quit.image = Glyphs.quitDot
        menu.addItem(quit)

        return menu
    }

    func buildShiftLockMenuItem() -> NSMenuItem {
        let subMenu = NSMenu(title: "Shift Lock")
        subMenu.showsStateColumn = false

        let useItem = NSMenuItem(title: "사용", action: #selector(toggleShiftLockEnabled(_:)), keyEquivalent: "")
        useItem.target = self
        setShiftLockEnabledImage(useItem)
        shiftLockMenuItem = useItem
        subMenu.addItem(useItem)

        let indicatorItem = NSMenuItem(title: "메뉴 막대 인디케이터", action: #selector(toggleShiftLockMenuBarIndicatorEnabled(_:)), keyEquivalent: "")
        indicatorItem.target = self
        setShiftLockMenuBarIndicatorImage(indicatorItem)
        shiftLockMenuBarIndicatorItem = indicatorItem
        subMenu.addItem(indicatorItem)

        let item = NSMenuItem(title: "Shift Lock", action: nil, keyEquivalent: "")
        item.submenu = subMenu
        item.image = Glyphs.symbol("capslock")
        return item
    }

    func buildLEDMenuItem(kind: LEDKind) -> NSMenuItem {
        let enabled = kind.enabled
        let current = LEDLanguage(inverted: kind.inverted)
        let ledMenu = NSMenu(title: kind.menuTitle)
        ledMenu.showsStateColumn = false

        let useItem = NSMenuItem(title: "사용", action: #selector(toggleLEDEnabled(_:)), keyEquivalent: "")
        useItem.target = self
        useItem.representedObject = kind
        useItem.image = enabled ? Glyphs.checkmark : Glyphs.stateDotEmpty
        ledMenu.addItem(useItem)

        ledMenu.addItem(NSMenuItem.separator())

        for lang in [LEDLanguage.korean, .english] {
            let title = lang == .korean ? Glyphs.hanTitle : Glyphs.aTitle
            let item = NSMenuItem(title: "", action: #selector(selectLEDLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = lang
            item.image = (lang == current) ? Glyphs.stateDot : Glyphs.stateDotEmpty
            item.attributedTitle = title
            item.setAccessibilityLabel(lang == .korean ? "한국어 입력 시 인디케이터 켜기" : "영어 입력 시 인디케이터 켜기")
            item.isEnabled = enabled
            ledMenu.addItem(item)
        }

        let item = NSMenuItem(title: kind.menuTitle, action: nil, keyEquivalent: "")
        item.submenu = ledMenu
        item.image = Glyphs.symbol(kind.symbolName)
        return item
    }
}
