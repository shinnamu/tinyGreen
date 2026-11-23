import AppKit

// 메뉴 구축 — buildMenu / buildLEDMenuItem. (전환 키 서브메뉴는 transitionkey.swift)
// menubar.swift 의 makeStatusItem 이 buildMenu() 호출.
extension StatusMenu {
    func buildMenu() -> NSMenu {
        let menu = NSMenu()
        // 토글 ✓ 는 image column 으로 옮김 — state column reservation 폭 제거 (native menu 너비 매칭).
        menu.showsStateColumn = false
        menu.delegate = self

        let about = NSMenuItem(title: "TinyGreen에 관하여", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        about.image = Glyphs.symbol("info.circle")
        menu.addItem(about)

        // 에러 항목 — 평소 hidden, 코어 에러 발생 시 unhide. 클릭 시 시스템 설정 열기.
        // 메뉴바 빨간 도트와 시각 언어 통일 (6pt 도트).
        let error = NSMenuItem(title: "", action: #selector(errorItemClicked), keyEquivalent: "")
        error.target = self
        error.image = Glyphs.errorDot
        error.isHidden = true
        errorItem = error
        menu.addItem(error)

        // 보안 입력 안내 — 평소 hidden. 메뉴 열 때 IsSecureEventInputEnabled 검사해 표시.
        // 비밀번호 칸·Terminal "Secure Keyboard Entry" 등 보안 입력 활성 시 시스템이
        // CGEventTap 에 키를 안 줘 Caps 한영 전환이 조용히 안 먹음 — 버그처럼 보이는
        // 정상 상태를 설명하는 정보 줄 (비활성·클릭 없음, 에러 아님이라 주황 도트 대신 lock).
        let secure = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        secure.image = Glyphs.symbol("lock.fill")
        secure.isEnabled = false
        secure.isHidden = true
        secureInputItem = secure
        menu.addItem(secure)

        menu.addItem(NSMenuItem.separator())

        // 가운데 그룹 — 배선(전환 키)과 비춤(입력 소스 보기·두 LED 표면).
        menu.addItem(buildTransitionKeyMenuItem())
        menu.addItem(buildExtraKeyMenuItem())

        let showSource = NSMenuItem(title: "입력 소스 보기", action: #selector(toggleShowInputSource(_:)), keyEquivalent: "")
        showSource.target = self
        setShowInputSourceImage(showSource)
        menu.addItem(showSource)

        menu.addItem(buildLEDMenuItem(kind: .menuBar))
        menu.addItem(buildLEDMenuItem(kind: .capsLock))

        menu.addItem(NSMenuItem.separator())

        // 마지막 그룹 — 앱 lifecycle (숨기기 → 자동 시작 → 종료).
        let hide = NSMenuItem(title: "메뉴 막대에서 숨기기", action: #selector(hideMenuBarIcon), keyEquivalent: "")
        hide.target = self
        hide.image = Glyphs.symbol("eye.slash")
        menu.addItem(hide)

        let login = NSMenuItem(title: "로그인 시 열기", action: #selector(toggleLoginItem(_:)), keyEquivalent: "")
        login.target = self
        setLoginImage(login)
        loginMenuItem = login
        menu.addItem(login)

        let quit = NSMenuItem(title: "TinyGreen 종료", action: #selector(quitClicked), keyEquivalent: "q")
        quit.target = self
        quit.image = Glyphs.quitDot
        menu.addItem(quit)

        Self.forceImagesVisible(in: menu)
        return menu
    }

    /// macOS 27부터 AppKit이 메뉴 항목 이미지를 기본으로 숨긴다(`preferredImageVisibility = .automatic`).
    /// 우리 메뉴는 이미지 칼럼이 상태 표시(✓·라디오 도트·에러 도트)를 겸하므로 전부 `.visible`로 고정.
    /// 속성은 항목에 남으므로 동적으로 이미지를 바꿔도 유지된다 — 구축 때 한 번만 재귀로 준다 (2026-09-17).
    static func forceImagesVisible(in menu: NSMenu) {
        guard #available(macOS 27.0, *) else { return }
        for item in menu.items {
            item.preferredImageVisibility = .visible
            if let sub = item.submenu { forceImagesVisible(in: sub) }
        }
    }

    func buildLEDMenuItem(kind: LEDKind) -> NSMenuItem {
        let enabled = kind.enabled
        let current = LEDLanguage(inverted: kind.inverted)
        let ledMenu = NSMenu(title: kind.menuTitle)
        // 부모 메뉴와 동일 — state column 끄고 ✓ 를 image column 으로.
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
            // attributedTitle 의 image attachment 은 VoiceOver 가 못 읽음 — 명시 라벨.
            item.setAccessibilityLabel(lang == .korean ? "한국어 입력 시 표시기 켜기" : "영어 입력 시 표시기 켜기")
            item.isEnabled = enabled
            ledMenu.addItem(item)
        }

        let item = NSMenuItem(title: kind.menuTitle, action: nil, keyEquivalent: "")
        item.submenu = ledMenu
        item.image = Glyphs.symbol(kind.symbolName)
        return item
    }
}
