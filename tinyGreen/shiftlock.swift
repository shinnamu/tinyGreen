import Foundation
import os

private let log = Logger.tinyGreen("ShiftLock")

final class ShiftLock {
    private(set) var isActive: Bool = false

    func toggle() {
        guard Settings.shiftLockEnabled else { return }
        setActive(!isActive)
    }

    func reset() {
        setActive(false)
    }

    private func setActive(_ active: Bool) {
        guard isActive != active else { return }
        isActive = active
        log.info("Shift Lock \(active ? "활성" : "해제", privacy: .public)")
        NotificationCenter.default.post(
            name: .tinyGreenShiftLockChanged,
            object: nil,
            userInfo: [Notification.shiftLockActiveKey: active]
        )
    }
}
