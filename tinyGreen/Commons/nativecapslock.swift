import AppKit
import IOKit.hidsystem

enum NativeCapsLock {
    static func isOn() -> Bool {
        CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift)
    }

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
