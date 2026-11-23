import AppKit
import IOKit.hidsystem

/// macOS가 소유한 실제 Caps Lock alpha-shift 비트의 읽기/해제 경계.
///
/// Right Command 모드에서만 사용한다. tinyGreen은 이 상태를 표시 입력으로만 읽고,
/// Router의 synthetic Shift 주입 상태에는 절대 복사하지 않는다. 해제는 CGEvent 합성
/// 키가 아니라 IOHIDSetModifierLockState — 합성 Caps Lock 키 이벤트는 HID 드라이버
/// 층이 소유한 실제 잠금 상태에 반영되지 않아(실측 2026-08-04) 신뢰할 수 없다.
enum NativeCapsLock {
    static func isOn() -> Bool {
        CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift)
    }

    /// 현재 native Caps Lock이 켜져 있으면 HID 시스템의 잠금 상태를 직접 끈다.
    /// 상태 전이(LED 포함)는 macOS HID 층이 수행한다. 실패 시 새 매핑을 적용하지
    /// 않는 것이 숨은 alpha-shift를 남기는 것보다 안전하다.
    @discardableResult
    static func turnOffIfNeeded() -> Bool {
        guard isOn() else { return true }

        let service = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass)
        )
        guard service != IO_OBJECT_NULL else { return false }
        defer { IOObjectRelease(service) }

        var connect: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &connect) == KERN_SUCCESS else {
            return false
        }
        defer { IOServiceClose(connect) }

        guard IOHIDSetModifierLockState(connect, Int32(kIOHIDCapsLockState), false) == KERN_SUCCESS else {
            return false
        }
        return !isOn()
    }
}
