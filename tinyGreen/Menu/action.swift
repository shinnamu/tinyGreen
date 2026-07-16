import AppKit
import Carbon.HIToolbox
import ServiceManagement

extension StatusMenu {
    @objc func quitClicked() {
        NSApp.terminate(nil)
    }

    @objc func errorItemClicked() {
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
            body: "다시 보이게 하려면 Spotlight에서 tinyGreen을 여세요. 앱은 백그라운드에서 계속 동작합니다.",
            confirm: "숨기기", cancel: "취소"
        ) else { return }
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItem = nil
        errorItem = nil
        led.detach()
    }

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
                body: "시스템 설정 → 일반 → 로그인 항목에서 tinyGreen을 켜주세요.",
                confirm: "시스템 설정 열기", cancel: "닫기"
            ) {
                Permissions.openLoginItemsSettings()
            }
        }
    }

    func confirm(title: String, body: String, confirm: String, cancel: String) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.addButton(withTitle: confirm)
        alert.addButton(withTitle: cancel)
        return alert.runModal() == .alertFirstButtonReturn
    }

    func setToggleImage(_ item: NSMenuItem, isOn: Bool) {
        item.image = isOn ? Glyphs.checkmark : nil
    }

    func setLoginImage(_ item: NSMenuItem) {
        setToggleImage(item, isOn: LoginItem.isEnabled)
    }

    func setShowInputSourceImage(_ item: NSMenuItem) {
        setToggleImage(item, isOn: Settings.showInputSource)
    }

    func setShiftLockEnabledImage(_ item: NSMenuItem) {
        setToggleImage(item, isOn: Settings.shiftLockEnabled)
    }

    func setShiftLockMenuBarIndicatorImage(_ item: NSMenuItem) {
        setToggleImage(item, isOn: Settings.shiftLockMenuBarIndicatorEnabled)
    }

    @objc func toggleShowInputSource(_ sender: NSMenuItem) {
        Settings.showInputSource.toggle()
        setShowInputSourceImage(sender)
        led.refresh()
    }

    @objc func toggleShiftLockEnabled(_ sender: NSMenuItem) {
        Settings.shiftLockEnabled.toggle()
        setShiftLockEnabledImage(sender)
        if !Settings.shiftLockEnabled {
            shiftLock?.reset()
        }
    }

    @objc func toggleShiftLockMenuBarIndicatorEnabled(_ sender: NSMenuItem) {
        Settings.shiftLockMenuBarIndicatorEnabled.toggle()
        setShiftLockMenuBarIndicatorImage(sender)
        led.refresh()
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

    func postSettingsChanged() {
        NotificationCenter.default.post(name: .tinyGreenSettingsChanged, object: nil)
    }
}

extension StatusMenu: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        if let item = loginMenuItem { setLoginImage(item) }
        updateSecureInputNote()
    }

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
