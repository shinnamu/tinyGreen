import AppKit

// 코어 에러 상태 — single point applyErrorMessage + 클릭 분기 + 시스템 레벨 alert.
// errorItemClicked(action.swift) 가 여기로 분기. menubar.swift start/showMenuBarIcon 이 updateError/applyErrorMessage 호출.
extension StatusMenu {
    func handlePermissionsClick() {
        // 클릭 시점에 권한 다시 체크 후 분기 — 알림 발생 후 사용자가 grant 했을 수도 있음.
        // 부족한 권한 페이지 정확히 열기. 둘 다 OK 인데 errorItem 떠있으면 권한 외 에러
        // (hidutil/LED 등) — AX fallback (가장 흔한 원인).
        let axOk = Permissions.checkAccessibility()
        let imOk = Permissions.checkInputMonitoring()
        switch (axOk, imOk) {
        case (false, true):
            Permissions.openAccessibilitySettings()
        case (true, false):
            Permissions.openInputMonitoringSettings()
        case (false, false), (true, true):
            // 둘 다 부족 시 AX 우선 (사이드바에서 IM 도 같이 보임).
            // 둘 다 OK 시 권한 외 에러 — AX fallback.
            Permissions.openAccessibilitySettings()
        }
    }

    /// F3-F5 — 자세한 정보 alert. 시스템 설정으로 가도 의미 없는 시스템 레벨 실패.
    /// 본문에 'GitHub' 안내만 (클릭 불가 plain text, URL 없음) — 사용자가 browser 에서 직접 연다.
    /// F5 (ledOpen) 만 환경 자연 원인 (외장 키보드 미지원) 가능성 — suppression button 표시
    /// + 닫기 = errorState clear (메뉴바 주황 도트 + errorItem hide). 다음 시작 시 LED 실패
    /// 또 발생하면 다시 표시 (체크 안 했을 때).
    func showSystemLevelFailureAlert(category: SystemFailure) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        let content = Self.systemLevelAlertContent(for: category)
        alert.messageText = content.title
        alert.informativeText = content.body
        alert.addButton(withTitle: "닫기")
        if category == .ledOpen {
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = "이 메시지 다시 보지 않음"
        }
        alert.runModal()
        if category == .ledOpen {
            if alert.suppressionButton?.state == .on {
                Settings.ledOpenAlertSuppressed = true
            }
            // F5 만 dismissable — 닫기 = errorState clear. F2/F3/F4 는 진짜 문제라 영구 유지.
            Notification.postTinyGreenCoreError(nil)
        }
    }

    private struct AlertContent {
        let title: String
        let body: String
    }

    private static func systemLevelAlertContent(for category: SystemFailure) -> AlertContent {
        switch category {
        case .mappingApply:
            return AlertContent(
                title: "키 매핑 적용 실패",
                body: """
                전환 키 매핑 설정에 실패했습니다.

                앱을 종료하고 다시 실행해보세요.
                문제가 계속되면 GitHub에 알려주세요.
                """
            )
        case .routerStart:
            return AlertContent(
                title: "키 입력 감지 실패",
                body: """
                전환 키 입력 감지에 실패했습니다.

                앱을 종료하고 다시 실행해보세요.
                문제가 계속되면 GitHub에 알려주세요.
                """
            )
        case .ledOpen:
            // F5 — GitHub 안내 미포함 (외장 키보드 호환성 자연 원인일 가능성).
            return AlertContent(
                title: "키보드 LED 연결 실패",
                body: """
                키보드 LED 제어에 실패했습니다.

                외장 키보드라면 LED 제어를 지원하지 않을 수 있습니다.
                내장 키보드에서도 실패한다면 앱을 종료하고 다시 실행해보세요.
                """
            )
        }
    }

    func updateError(_ notif: Notification) {
        let msg = notif.userInfo?[Notification.errorMessageKey] as? String
        let categoryRaw = notif.userInfo?[Notification.errorCategoryKey] as? String
        let category = categoryRaw.flatMap(CoreErrorCategory.init(rawValue:))
        applyErrorMessage(msg, category: category)
    }

    /// 코어 에러 메시지 적용 — single point. updateError 알림 + showMenuBarIcon 둘 다에서 호출.
    /// hide 중 (errorItem nil) 이어도 lastErrorMessage / lastErrorCategory / errorActive 는
    /// store 갱신 — show 시 복구 가능.
    func applyErrorMessage(_ msg: String?, category: CoreErrorCategory?) {
        lastErrorMessage = msg
        lastErrorCategory = msg == nil ? nil : category
        led.setError(active: msg != nil)
        guard let item = errorItem else { return }
        if let msg = msg {
            item.attributedTitle = Self.secondaryMenuTitle(msg)
            // G6 VoiceOver 라벨 — 클릭 동작 안내. 갈래는 errorItemClicked 와 같은 축 (systemFailure).
            let actionHint = category?.systemFailure == nil
                ? "클릭하면 시스템 설정 열기."
                : "클릭하면 자세한 정보."
            item.setAccessibilityLabel("\(msg). \(actionHint)")
            item.isHidden = false
        } else {
            item.isHidden = true
        }
    }
}
