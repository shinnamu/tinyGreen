import AppKit

extension StatusMenu {
    func handlePermissionsClick() {
        let axOk = Permissions.checkAccessibility()
        let imOk = Permissions.checkInputMonitoring()
        switch (axOk, imOk) {
        case (false, true):
            Permissions.openAccessibilitySettings()
        case (true, false):
            Permissions.openInputMonitoringSettings()
        case (false, false), (true, true):
            Permissions.openAccessibilitySettings()
        }
    }

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
                Caps Lock 키 매핑 설정에 실패했습니다.

                앱을 종료하고 다시 실행해보세요.
                문제가 계속되면 GitHub에 알려주세요.
                """
            )
        case .routerStart:
            return AlertContent(
                title: "키 입력 감지 실패",
                body: """
                Caps Lock 입력 감지에 실패했습니다.

                앱을 종료하고 다시 실행해보세요.
                문제가 계속되면 GitHub에 알려주세요.
                """
            )
        case .ledOpen:
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

    func applyErrorMessage(_ msg: String?, category: CoreErrorCategory?) {
        lastErrorMessage = msg
        lastErrorCategory = msg == nil ? nil : category
        led.setError(active: msg != nil)
        guard let item = errorItem else { return }
        if let msg = msg {
            item.attributedTitle = Self.secondaryMenuTitle(msg)
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
