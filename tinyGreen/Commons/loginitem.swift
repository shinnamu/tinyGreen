import ServiceManagement
import os

private let log = Logger.tinyGreen("LoginItem")

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
