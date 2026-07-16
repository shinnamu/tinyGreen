import AppKit
import Carbon.HIToolbox
import os

private let log = Logger.tinyGreen("Router")

final class Router {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapRunLoop: CFRunLoop?
    var shiftLock: ShiftLock?

    private struct TapState {
        var isKorean = false
        var shiftLockActive = false
    }
    private let tapState = OSAllocatedUnfairLock(initialState: TapState())

    func update(isKorean: Bool) {
        tapState.withLock { $0.isKorean = isKorean }
    }

    func update(shiftLockActive: Bool) {
        tapState.withLock { $0.shiftLockActive = shiftLockActive }
    }
    var onShiftCapsKorean: (() -> Void)?
    var onTapNeedsRecreate: (() -> Void)?

    private static let alphabetKeyCodes: Set<Int64> = [
        Int64(kVK_ANSI_A), Int64(kVK_ANSI_B), Int64(kVK_ANSI_C), Int64(kVK_ANSI_D),
        Int64(kVK_ANSI_E), Int64(kVK_ANSI_F), Int64(kVK_ANSI_G), Int64(kVK_ANSI_H),
        Int64(kVK_ANSI_I), Int64(kVK_ANSI_J), Int64(kVK_ANSI_K), Int64(kVK_ANSI_L),
        Int64(kVK_ANSI_M), Int64(kVK_ANSI_N), Int64(kVK_ANSI_O), Int64(kVK_ANSI_P),
        Int64(kVK_ANSI_Q), Int64(kVK_ANSI_R), Int64(kVK_ANSI_S), Int64(kVK_ANSI_T),
        Int64(kVK_ANSI_U), Int64(kVK_ANSI_V), Int64(kVK_ANSI_W), Int64(kVK_ANSI_X),
        Int64(kVK_ANSI_Y), Int64(kVK_ANSI_Z)
    ]

    @discardableResult
    func start() -> Bool {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        if let tap = createTap(at: .cghidEventTap, mask: mask, ctx: selfPtr) {
            attach(tap)
            return true
        }

        if let tap = createTap(at: .cgSessionEventTap, mask: mask, ctx: selfPtr) {
            log.notice("CGEventTap → cgSessionEventTap fallback 사용")
            attach(tap)
            return true
        }

        log.error("CGEventTap 생성 실패 (cghid + cgSession 양쪽) — Accessibility / Input Monitoring 권한 확인 필요")
        return false
    }

    private func createTap(at location: CGEventTapLocation, mask: CGEventMask, ctx: UnsafeMutableRawPointer) -> CFMachPort? {
        return CGEvent.tapCreate(
            tap: location,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: Router.tapCallback,
            userInfo: ctx
        )
    }

    private func attach(_ tap: CFMachPort) {
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        let ready = DispatchSemaphore(value: 0)
        var loop: CFRunLoop?
        let thread = Thread {
            loop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "tinyGreen.tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        self.eventTap = tap
        self.runLoopSource = source
        self.tapRunLoop = loop
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let loop = tapRunLoop {
            if let source = runLoopSource {
                CFRunLoopRemoveSource(loop, source, .commonModes)
            }
            CFRunLoopStop(loop)
        }
        eventTap = nil
        runLoopSource = nil
        tapRunLoop = nil
    }

    @discardableResult
    func recreate() -> Bool {
        stop()
        return start()
    }

    @discardableResult
    func revalidate() -> Bool {
        guard let tap = eventTap else { return false }
        CGEvent.tapEnable(tap: tap, enable: true)
        return CGEvent.tapIsEnabled(tap: tap)
    }

    private func handleTapDisabled() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
        if !CGEvent.tapIsEnabled(tap: tap) {
            onTapNeedsRecreate?()
        }
    }

    private static let tapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo = userInfo else { return Unmanaged.passUnretained(event) }
        let router = Unmanaged<Router>.fromOpaque(userInfo).takeUnretainedValue()

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            log.notice("tap disabled (\(type == .tapDisabledByTimeout ? "timeout" : "userInput", privacy: .public)) — 재활성 위임")
            DispatchQueue.main.async {
                router.handleTapDisabled()
            }
            return Unmanaged.passUnretained(event)
        }

        if type == .keyDown {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

            if keyCode == Int64(kVK_F19) {
                if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
                    return nil
                }
                let flags = event.flags
                let onlyShift = flags.contains(.maskShift)
                    && !flags.contains(.maskCommand)
                    && !flags.contains(.maskAlternate)
                    && !flags.contains(.maskControl)
                if onlyShift && Settings.shiftLockEnabled {
                    let isKorean = router.tapState.withLock { $0.isKorean }
                    DispatchQueue.main.async {
                        if isKorean {
                            router.onShiftCapsKorean?()
                        } else {
                            router.shiftLock?.toggle()
                        }
                    }
                    return nil
                }
                return Unmanaged.passUnretained(event)
            }

            let state = router.tapState.withLock { $0 }
            if state.shiftLockActive, !state.isKorean,
               Router.alphabetKeyCodes.contains(keyCode) {
                let flags = event.flags
                let hasOtherModifier = flags.contains(.maskCommand)
                    || flags.contains(.maskAlternate)
                    || flags.contains(.maskControl)
                if !hasOtherModifier {
                    event.flags = flags.union(.maskShift)
                }
            }
        }

        return Unmanaged.passUnretained(event)
    }
}
