import Foundation
import os

private let log = Logger.tinyGreen("ShiftLock")

/// Shift Lock 모드 — ALL CAPS 입력 활성 여부.
/// 단일 진실 출처. 다른 컴포넌트는 알림으로만 받음.
/// 시스템 Caps Lock 비트와 무관 (F19 매핑이라 시스템 비트 못 건드림).
/// 매 알파벳 keydown 에 Shift flag 끼얹기 (1878 Shift Lock 방식, letters-only 는 1968 Kerr).
final class ShiftLock {
    private(set) var isActive: Bool = false

    /// Caps Lock 전환 모드에서만 Router가 호출한다. autorepeat 은 호출자 (Router) 가 거름.
    func toggle() {
        setActive(!isActive)
    }

    /// 전환 모드 변경 또는 종료 때.
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
