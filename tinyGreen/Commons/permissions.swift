import AppKit
import ApplicationServices
import IOKit
import IOKit.hid

/// Accessibility / Input Monitoring 권한 체크 + 안내.
enum Permissions {
    static func checkAccessibility() -> Bool {
        return AXIsProcessTrusted()
    }

    static func checkInputMonitoring() -> Bool {
        return IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    /// 첫 호출이면 시스템 prompt 표시(동기) + 시스템 설정 목록에 앱 등록.
    /// 반환: granted=true.
    @discardableResult
    static func requestInputMonitoring() -> Bool {
        return IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    static func openAccessibilitySettings() {
        openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    static func openInputMonitoringSettings() {
        openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    static func openLoginItemsSettings() {
        openSettings("x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
    }

    static func openSettings(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    /// "시스템 설정 열기" 를 누르면 true.
    static func showMissingAlert(missing: [String]) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "TinyGreen 권한 설정"
        alert.informativeText = """
        tinyGreen을 사용하려면 다음 권한이 필요합니다:

        • \(missing.joined(separator: "\n• "))
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "시스템 설정 열기")
        alert.addButton(withTitle: "나중에")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
