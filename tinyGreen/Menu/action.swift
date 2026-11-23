import AppKit
import Carbon.HIToolbox
import ServiceManagement

// 메뉴 액션 핸들러 + 토글 이미지 helper + NSMenuDelegate.
// errorItemClicked 는 error.swift 의 handlePermissionsClick / showSystemLevelFailureAlert 로 분기 (같은 타입 extension).
extension StatusMenu {
    @objc func quitClicked() {
        NSApp.terminate(nil)
    }

    @objc func errorItemClicked() {
        // 시스템 레벨 실패 (F3-F5) → 자세한 정보 alert. 그 외 (permissions·카테고리 없는 legacy)
        // → 부족한 권한 페이지 시스템 설정 열기 (사용자 해결 가능 경로가 기본 fallback).
        switch lastErrorCategory?.systemFailure {
        case .some(let failure):
            showSystemLevelFailureAlert(category: failure)
        case .none:
            handlePermissionsClick()
        }
    }

    @objc func hideMenuBarIcon() {
        guard confirm(
            title: "메뉴 막대에서 숨기기",
            body: "다시 보이게 하려면 Spotlight에서 TinyGreen을 여세요. 앱은 백그라운드에서 계속 동작합니다.",
            confirm: "숨기기", cancel: "취소"
        ) else { return }
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItem = nil
        errorItem = nil
        led.detach()
        // lastErrorMessage 와 도트 errorActive 는 그대로 — hide 중 발생하는 에러도 store 에 누적되어
        // showMenuBarIcon 시 applyErrorMessage 로 복구. 점멸 타이밍은 Priority 소유라 여기서 정지할 게 없음
        // (button detach 라 도트 refresh 가 no-op, lastIntent 는 계속 갱신).
    }

    /// 첫 실행 (권한 grant 완료 후 코어 시작 시점) 에 한 번만 alert 으로 묻기.
    /// 사용자가 "예/아니오" 어느 쪽이든 누르면 hasAskedAboutLoginItem=true 로 박혀
    /// 다음 실행부터 안 뜸. 메뉴 옵션은 그대로 살아있어 언제든 토글 가능.
    func askAboutLoginItemIfFirstRun() {
        guard !Settings.hasAskedAboutLoginItem else { return }
        if confirm(
            title: "로그인 시 열기",
            body: """
            로그인 시 tinyGreen을 자동으로 열까요?

            메뉴 "로그인 시 열기"에서 언제든 변경 가능합니다.
            """,
            confirm: "지금 켜기", cancel: "나중에"
        ) {
            _ = LoginItem.setEnabled(true)
            if let item = loginMenuItem { setLoginImage(item) }
        }
        Settings.hasAskedAboutLoginItem = true
    }

    @objc func toggleLoginItem(_ sender: NSMenuItem) {
        let next = !LoginItem.isEnabled
        guard LoginItem.setEnabled(next) else { return }
        defer { setLoginImage(sender) }

        if next && LoginItem.status == .requiresApproval {
            if confirm(
                title: "시스템 설정 승인 요청",
                body: "시스템 설정 → 일반 → 로그인 항목에서 TinyGreen을 켜주세요.",
                confirm: "시스템 설정 열기", cancel: "닫기"
            ) {
                Permissions.openLoginItemsSettings()
            }
        }
    }

    /// 2버튼 확인 alert — confirm 버튼 누르면 true. LSUIElement 앱이라 activate 선행 필수
    /// (안 하면 alert 가 다른 창 뒤로 묻힌다). 메뉴 액션의 확인 alert 공통.
    func confirm(title: String, body: String, confirm: String, cancel: String) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.addButton(withTitle: confirm)
        alert.addButton(withTitle: cancel)
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// 토글 메뉴 항목 ✓ image helper.
    func setToggleImage(_ item: NSMenuItem, isOn: Bool) {
        item.image = isOn ? Glyphs.checkmark : nil
    }

    func setLoginImage(_ item: NSMenuItem) {
        setToggleImage(item, isOn: LoginItem.isEnabled)
    }

    func setShowInputSourceImage(_ item: NSMenuItem) {
        setToggleImage(item, isOn: Settings.showInputSource)
    }

    @objc func toggleShowInputSource(_ sender: NSMenuItem) {
        Settings.showInputSource.toggle()
        setShowInputSourceImage(sender)
        led.refresh()
    }

    /// 선택한 물리 키의 매핑 변경은 코어에 위임한다.
    /// 실패하면 Settings를 바꾸지 않는 코어 계약에 따라 이전 라디오 상태를 복원한다.
    @objc func selectTransitionKey(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? TransitionKey else { return }
        guard let onTransitionKeyChange else {
            syncTransitionKeyMenu()
            return
        }
        guard onTransitionKeyChange(key) else {
            syncTransitionKeyMenu()
            return
        }
        // callback이 Settings를 성공 시점에 커밋하지만, 메뉴가 열린 채여도 즉시 보이게 한다.
        syncTransitionKeyMenu(to: key)
    }

    @objc func toggleLEDEnabled(_ sender: NSMenuItem) {
        guard let kind = sender.representedObject as? LEDKind else { return }
        let next = !kind.enabled
        kind.enabled = next
        sender.image = next ? Glyphs.checkmark : Glyphs.stateDotEmpty

        sender.menu?.items.forEach { item in
            if item != sender && !item.isSeparatorItem {
                item.isEnabled = next
            }
        }
        postSettingsChanged()
    }

    @objc func selectLEDLanguage(_ sender: NSMenuItem) {
        guard let lang = sender.representedObject as? LEDLanguage else { return }
        Settings.ledInverted = lang.inverted
        // 매핑이 공통이라 두 LED 메뉴의 라디오 모두 동기화
        syncLEDLanguageRadios(to: lang)
        postSettingsChanged()
    }

    func syncLEDLanguageRadios(to lang: LEDLanguage) {
        statusItem?.menu?.items
            .flatMap { $0.submenu?.items ?? [] }
            .forEach { item in
                guard let itemLang = item.representedObject as? LEDLanguage else { return }
                item.image = (itemLang == lang) ? Glyphs.stateDot : Glyphs.stateDotEmpty
            }
    }

    /// LED 메뉴 토글/라디오 변경 — 입력 소스 자체는 안 바뀌었으니 `.tinyGreenSettingsChanged` 발행.
    /// `.tinyGreenInputSourceChanged` 와 분리해서 한영 전환 부작용 (Shift Lock 자동 해제) 안 일으킴.
    func postSettingsChanged() {
        NotificationCenter.default.post(name: .tinyGreenSettingsChanged, object: nil)
    }
}

extension StatusMenu: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        // Login Item 상태가 외부 (시스템 설정) 에서 바뀌었을 수 있음 — 메뉴 열 때 재동기화.
        if let item = loginMenuItem { setLoginImage(item) }
        syncTransitionKeyMenu()
        syncExtraKeyMenu()
        updateSecureInputNote()
    }

    /// 메뉴 열 때 보안 입력 상태 점검 — 활성이면 안내 줄 표시, 아니면 숨김.
    /// 보안 입력 시 시스템이 CGEventTap 에 키를 안 줘 콜백 자체가 안 불림 — keystroke 시점
    /// 감지 불가, 그래서 메뉴 열 때만 검사 (폴링 타이머 없음 — 미니멀).
    /// IsSecureEventInputEnabled 은 전역 상태 (어느 필드/앱인지 모름) — 문구도 전역으로.
    func updateSecureInputNote() {
        guard let item = secureInputItem else { return }
        if IsSecureEventInputEnabled() {
            item.attributedTitle = Self.secondaryMenuTitle("보안 입력 중 — 한영 전환 일시정지")
            item.setAccessibilityLabel("보안 입력 필드가 활성이라 한영 전환이 잠시 멈췄습니다.")
            item.isHidden = false
        } else {
            item.isHidden = true
        }
    }
}
