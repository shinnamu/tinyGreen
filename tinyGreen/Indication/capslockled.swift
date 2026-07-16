import Foundation
import IOKit
import IOKit.hid
import os

private let log = Logger.tinyGreen("CapsLockLED")

final class CapsLockLED {
    private var manager: IOHIDManager?
    private var deviceElements: [(IOHIDDevice, [IOHIDElement])] = []
    private var lastIntent = Priority.DisplayIntent(layer: .base, isKorean: false)

    private let observers = ObserverBag()

    func start() {
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let match: [String: Any] = [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard
        ]
        IOHIDManagerSetDeviceMatching(mgr, match as CFDictionary)

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(mgr, CapsLockLED.matched, selfPtr)
        IOHIDManagerRegisterDeviceRemovalCallback(mgr, CapsLockLED.removed, selfPtr)

        IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        let result = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        if result != kIOReturnSuccess {
            let hex = String(format: "0x%08X", result)
            log.error("IOHIDManagerOpen 실패: \(hex, privacy: .public)")
            if !Settings.ledOpenAlertSuppressed {
                Notification.postTinyGreenCoreError("키보드 LED 연결 실패", category: .ledOpen)
                NotificationCenter.default.post(name: .tinyGreenAutoShowLEDOpenAlert, object: nil)
            }
        }
        manager = mgr

        observers.add(name: .tinyGreenSettingsChanged) { [weak self] _ in
            guard let self = self else { return }
            self.applyToHardware(self.effectiveOn(self.lastIntent))
        }
    }

    func stop() {
        observers.removeAll()
        for (device, elements) in deviceElements {
            apply(false, to: device, elements: elements)
        }
        lastIntent = Priority.DisplayIntent(layer: .base, isKorean: false)
        if let mgr = manager {
            IOHIDManagerUnscheduleFromRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        manager = nil
        deviceElements.removeAll()
    }

    func indicate(_ intent: Priority.DisplayIntent) {
        lastIntent = intent
        applyToHardware(effectiveOn(intent))
        if case .base = intent.layer {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self = self else { return }
                self.applyToHardware(self.effectiveOn(self.lastIntent))
            }
        }
    }

    func reassert() {
        applyToHardware(effectiveOn(lastIntent))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self else { return }
            self.applyToHardware(self.effectiveOn(self.lastIntent))
        }
    }

    private func effectiveOn(_ intent: Priority.DisplayIntent) -> Bool {
        switch intent.layer {
        case .easterEgg(let lit): return lit
        case .shiftLock(let blink): return blink
        case .base: return Settings.capsLockLEDShouldBeOn(isKorean: intent.isKorean)
        }
    }

    private func applyToHardware(_ on: Bool) {
        for (device, elements) in deviceElements {
            apply(on, to: device, elements: elements)
        }
    }

    private func apply(_ on: Bool, to device: IOHIDDevice, elements: [IOHIDElement]) {
        for el in elements {
            let value = IOHIDValueCreateWithIntegerValue(
                kCFAllocatorDefault,
                el,
                mach_absolute_time(),
                on ? 1 : 0
            )
            IOHIDDeviceSetValue(device, el, value)
        }
    }

    private static func capsLockElements(of device: IOHIDDevice) -> [IOHIDElement] {
        let match: [String: Any] = [
            kIOHIDElementUsagePageKey: kHIDPage_LEDs,
            kIOHIDElementUsageKey: kHIDUsage_LED_CapsLock
        ]
        guard let raw = IOHIDDeviceCopyMatchingElements(device, match as CFDictionary, IOOptionBits(kIOHIDOptionsTypeNone)),
              let elements = raw as? [IOHIDElement] else {
            return []
        }
        return elements
    }

    private static let matched: IOHIDDeviceCallback = { ctx, _, _, device in
        guard let ctx = ctx else { return }
        let c = Unmanaged<CapsLockLED>.fromOpaque(ctx).takeUnretainedValue()
        guard !c.deviceElements.contains(where: { CFEqual($0.0, device) }) else { return }
        let elements = capsLockElements(of: device)
        c.deviceElements.append((device, elements))
        c.apply(c.effectiveOn(c.lastIntent), to: device, elements: elements)
    }

    private static let removed: IOHIDDeviceCallback = { ctx, _, _, device in
        guard let ctx = ctx else { return }
        let c = Unmanaged<CapsLockLED>.fromOpaque(ctx).takeUnretainedValue()
        c.deviceElements.removeAll { CFEqual($0.0, device) }
    }
}
