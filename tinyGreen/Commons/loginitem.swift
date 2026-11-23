import ServiceManagement
import os

private let log = Logger.tinyGreen("LoginItem")

/// macOS 13+ "로그인 시 열기" 토글 — SMAppService 래퍼.
/// 시스템에 등록/조회만 담당, Permissions·Settings 와 같은 OS-서비스 래퍼 종(種).
/// UI 글루(토글 메뉴·첫 실행 물음)는 Menu/action.swift.
enum LoginItem {
    static var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    static var isEnabled: Bool {
        status == .enabled
    }

    @discardableResult
    static func setEnabled(_ on: Bool) -> Bool {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            log.error("Login Item 변경 실패: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
