import Foundation
import IOKit
import IOKit.hid
import os

private let log = Logger.tinyGreen("CapsLockLED")

/// 키보드 Caps Lock LED 제어. default 매핑: 영어 활성=ON, 한국어 활성=OFF.
/// (한국어 사용자 기준 영어가 특수 상태 시그널 — Apple Caps Lock LED 메타포 일치).
/// 메뉴 "키보드 인디케이터 → 한에서/A에서" 라디오로 반전 가능 (`ledInverted` UserDefault).
/// IOHIDManager 로 키보드 매칭 (GenericDesktop / Keyboard) + hot-plug 콜백.
/// 매칭된 모든 디바이스의 LED element (page 0x08, usage 0x02) 에 값 set.
///
/// 무엇을 비출지(우선순위 easterEgg>shiftLock>base)는 `Priority` 가 정해 `indicate(intent)` 로 준다.
/// 여기선 *어떻게* — intent 의 층을 LED 게이트로 옮긴다:
///   - easterEgg(lit) → lit (모스 시퀀스)
///   - shiftLock(blink) → blink (점멸은 Apple Caps Lock LED 메타포라 항상 honor — 설정 무관)
///   - base → capsLockLEDShouldBeOn(isKorean) (capsLockLEDEnabled + ledInverted 게이트)
final class CapsLockLED {
    private var manager: IOHIDManager?
    /// device → LED element 캐시. matched 콜백에서 한 번 fetch.
    private var deviceElements: [(IOHIDDevice, [IOHIDElement])] = []
    /// 마지막으로 받은 intent — 디바이스 hot-plug / 설정 변경 / wake 재적용의 기준.
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
            // 사용자가 이전에 "이 메시지 다시 보지 않음" 선택 시 errorState + alert 둘 다 silent.
            // 외장 키보드는 LED 제어 미지원이 자연 원인 — 영구 경고 노이즈 회피.
            if !Settings.ledOpenAlertSuppressed {
                Notification.postTinyGreenCoreError("키보드 LED 연결 실패", category: .ledOpen)
                NotificationCenter.default.post(name: .tinyGreenAutoShowLEDOpenAlert, object: nil)
            }
        }
        manager = mgr

        // 설정 변경(LED 매핑 반전 / 사용 토글) — base 게이트 재계산. intent 상태는 불변이라
        // 마지막 intent 를 그대로 다시 그린다 (Priority 는 설정을 모름 = 표면 게이트).
        observers.add(name: .tinyGreenSettingsChanged) { [weak self] _ in
            guard let self = self else { return }
            self.applyToHardware(self.effectiveOn(self.lastIntent))
        }
    }

    /// 코어 종료 시 LED를 끈다 — 두 모드 다 대문자 잠금이 앱 소유 합성 상태라
    /// 종료와 함께 해제되므로, 남길 native 상태가 없다.
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

    /// Priority 가 intent 변할 때마다 호출 (AppDelegate 배선). main thread.
    func indicate(_ intent: Priority.DisplayIntent) {
        lastIntent = intent
        applyToHardware(effectiveOn(intent))
        // base(한영 전환) 변화에만 0.3s 재push — BT 키보드 idle wake-up race 안전망:
        // idle 에서 첫 keyDown 으로 깨는 ~50-200ms transition 중 IOHIDDeviceSetValue 가
        // silently override 되어 hardware 가 옛 상태로 복원되는 "한 번 깜박" 보정. active 안정화 후 재push.
        // 점멸/이스터에그 tick 은 키보드 이미 active 라 불필요(200ms 마다 쌓이지도 않게).
        if case .base = intent.layer {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self = self else { return }
                self.applyToHardware(self.effectiveOn(self.lastIntent))
            }
        }
    }

    /// 논리 상태 변화 없이 현재 intent 를 하드웨어에 강제 재적용.
    /// 시스템 sleep→wake 후 BT/외장 키보드가 LED 를 자기 상태로 리셋했을 때 동기화 복구.
    /// 즉시 + 0.3s 재적용 — re-enumerate 시 matched 콜백이 새 device 를 잡고, 연결 유지 시
    /// 기존 handle 로 재push. 0.3s 가 wake transition 중 device 재확보 타이밍 완충.
    /// stop() 후 fire 해도 deviceElements 비어 no-op (안전).
    func reassert() {
        applyToHardware(effectiveOn(lastIntent))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self else { return }
            self.applyToHardware(self.effectiveOn(self.lastIntent))
        }
    }

    /// intent 층을 LED 출력으로. 점멸은 항상 honor, base 만 사용/반전 게이트.
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
        // 새 디바이스에 현재 intent 즉시 반영 (Easter Egg / blink / base 우선순위).
        c.apply(c.effectiveOn(c.lastIntent), to: device, elements: elements)
    }

    private static let removed: IOHIDDeviceCallback = { ctx, _, _, device in
        guard let ctx = ctx else { return }
        let c = Unmanaged<CapsLockLED>.fromOpaque(ctx).takeUnretainedValue()
        c.deviceElements.removeAll { CFEqual($0.0, device) }
    }
}
