import AppKit
import Carbon.HIToolbox
import os

private let log = Logger.tinyGreen("Router")

/// CGEventTap 으로 F19 keydown 감지 + Caps Lock 모드의 synthetic Shift Lock 알파벳 주입.
/// 위치: kCGHIDEventTap (가장 이른 가로채기) + headInsertEventTap.
///
/// 스레딩 — tap 은 전용 스레드("tinyGreen.tap")의 런루프에 산다. 시스템의 모든 keydown 이
/// 이 콜백을 동기로 거치므로, 메인에 두면 앱의 메인 작업(LED HID 쓰기·메뉴 렌더·모달)이
/// 시스템 전체 키 전달을 밀리게 한다. 경계 규칙:
///   - 콜백이 동기로 읽는 가변 상태는 `tapState`(lock 스냅샷) 하나 — 메인이 push, 콜백이 read.
///   - 콜백에서 나가는 행동(shiftLock.toggle·onShiftCapsKorean·disable 후처리)은 main 으로 되던짐.
///   - 배선 프로퍼티(shiftLock·onShiftCapsKorean·onTapNeedsRecreate)는 start() *전에만* 설정 —
///     Thread.start() 가 메모리 배리어라 콜백에서 lock 없이 안전 읽기. start 후 변경 금지.
///   - eventTap·runLoopSource·tapRunLoop 은 main 소유 — 콜백은 안 만진다.
///
/// 분기 (F19) — 한영 전환은 OS 위임(C②): F19 → 시스템 "다음 입력 소스 선택" 단축키가 담당.
/// Caps Lock 모드에서만 Shift+F19를 synthetic Shift Lock/Easter Egg 트리거로 소비한다.
/// Right Command 모드의 Shift+F19는 항상 흘려보내며 synthetic Shift Lock을 건드리지 않는다.
///
/// 분기 (F18) — Right Command 모드의 Caps Lock (hidutil Caps→F18). 항상 소비하며,
/// 영문 = Shift Lock 토글 / 한국어+Shift = Easter Egg / 한국어 plain = no-op.
/// 대문자 잠금은 두 모드 모두 같은 합성 Shift Lock 엔진 — 방아쇠만 다르다.
///
/// 분기 (F17) — 🔍 기능 키 옵션 (hidutil 🔍→F17, ADR-0008). 켜져 있으면 소비하고 그 자리에서
/// ⌃⌥A(Aside 미니 팝업) down·up을 합성해 쏜다. 버퍼·타이머 없음, mask는 keyDown 그대로(ADR-0001) —
/// F17 keyUp은 짝 없는 keyUp으로 흘러간다. 합성 이벤트는 userData 표식으로 콜백 맨 앞에서 통과.
///
/// 분기 (⌃⌘←/→/F/C) — 창 배치 옵션(ADR-0009). 켜져 있으면 소비하고 main 에서 창을 놓는다.
/// F17과 같은 길 — 버퍼·타이머 없음, mask는 keyDown 그대로라 짝 keyUp은 앱으로 흘러간다.
///
/// 분기 (알파벳):
/// - Shift Lock 활성 + 영문 모드 + Cmd/Option/Ctrl 미포함 → event.flags |= .maskShift (1878 Shift Lock 방식)
/// - letters-only (1968 Kerr) — 숫자/기호는 그대로
final class Router {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    /// tap 전용 스레드의 런루프 — stop() 의 CFRunLoopStop 대상. main 소유.
    private var tapRunLoop: CFRunLoop?
    /// Shift Lock 토글용 (main 으로 되던져 호출). isActive 는 콜백이 tapState 스냅샷으로 읽는다.
    var shiftLock: ShiftLock?

    /// 콜백(tap 스레드)이 동기로 읽는 상태 스냅샷 — 메인이 update 로 push, 콜백이 read.
    /// 갱신원: AppDelegate (입력 소스·Shift Lock 옵저버 자리).
    private struct TapState {
        var isKorean = false
        var shiftLockActive = false
        var transitionKey: TransitionKey = .capsLock
        var searchKeyEnabled = false
    }
    private let tapState = OSAllocatedUnfairLock(initialState: TapState())

    func update(isKorean: Bool) {
        tapState.withLock { $0.isKorean = isKorean }
    }

    func update(shiftLockActive: Bool) {
        tapState.withLock { $0.shiftLockActive = shiftLockActive }
    }

    /// 물리 전환 키 모드 스냅샷. Native Caps 상태와 synthetic Shift 상태를 섞지 않기
    /// 위해 Router는 모드만 읽고, native 상태는 display 경로로만 전달한다.
    func update(transitionKey: TransitionKey) {
        tapState.withLock { $0.transitionKey = transitionKey }
    }
    /// 🔍 옵션이 실제로 배선됐는지. 꺼져 있으면 F17은 사용자 것이라 흘려보낸다.
    func update(searchKeyEnabled: Bool) {
        tapState.withLock { $0.searchKeyEnabled = searchKeyEnabled }
    }

    /// 우리가 쏜 ⌃⌥A 표식 ("tgkeys"). cghid head tap이라 자기 합성 이벤트를 다시 받는다.
    private static let synthMarker: Int64 = 0x7467_6b65_7973
    /// privateState — 실제로 눌린 수정키 상태가 합성 이벤트에 섞이지 않게.
    private static let synthSource = CGEventSource(stateID: .privateState)

    /// ⌃⌥A down·up. flags는 OR이 아니라 덮어쓰기 — ⇧·⌘를 누른 채 🔍를 눌러도 같은 단축키.
    private static func postSearchShortcut() {
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: synthSource, virtualKey: CGKeyCode(kVK_ANSI_A), keyDown: down) else {
                log.error("⌃⌥A 합성 실패")
                return
            }
            event.flags = [.maskControl, .maskAlternate]
            event.setIntegerValueField(.eventSourceUserData, value: synthMarker)
            event.post(tap: .cghidEventTap)
        }
        log.notice("🔍 → ⌃⌥A")
    }

    /// 한국어 모드 + Shift+F19 → Easter Egg 트리거 콜백 (한영 전환 안 함, Shift Lock 토글도 안 함).
    var onShiftCapsKorean: (() -> Void)?
    /// tap 자가치유 요청 — 재활성(tapEnable)이 죽은 포트라 실패했을 때 호출.
    /// handleTapDisabled(main) 에서 올라오므로 항상 main — 호출측이 바로 stop()+start() 재생성해도 안전.
    var onTapNeedsRecreate: (() -> Void)?

    /// 알파벳 keyCode (kVK_ANSI_A..Z) — Shift 끼얹기 letters-only 판정.
    /// macOS keyCode 는 비연속이라 Set 으로.
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

        // 1순위: kCGHIDEventTap (가장 이른 위치, 시스템 전역)
        if let tap = createTap(at: .cghidEventTap, mask: mask, ctx: selfPtr) {
            attach(tap)
            return true
        }

        // 2순위 fallback: kCGSessionEventTap (세션 레벨)
        // — HID tap 권한 부족 또는 환경 제약 시 우회
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

    /// tap 전용 스레드 기동 + source 부착. 콜백이 이 스레드에서 돈다 (클래스 주석 "스레딩" 참조).
    /// 세마포어로 런루프 준비를 기다린 뒤 반환 — 직후 stop() 이 와도 tapRunLoop 이 확실히 잡혀 있게.
    private func attach(_ tap: CFMachPort) {
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        let ready = DispatchSemaphore(value: 0)
        var loop: CFRunLoop?
        let thread = Thread {
            loop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            ready.signal()
            CFRunLoopRun()  // stop() 의 CFRunLoopStop 까지 상주
        }
        thread.name = "tinyGreen.tap"
        thread.qualityOfService = .userInteractive  // 키 전달 경로 — 시스템 입력 지연 최소화
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
        // source 제거·런루프 정지는 크로스 스레드 안전 (CFRunLoop 문서 보장). 루프가 멈추면
        // 스레드가 스스로 내려간다. 진행 중이던 콜백은 CF 가 dispatch 동안 port 를 retain 해 안전.
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

    /// 죽은 CFMachPort 재생성 — tapEnable 로 못 살리는 무효 포트는 stop()+start() 로 새로 만든다.
    /// start() 가 콜백 프로퍼티(onShiftCapsKorean 등)를 보존하니 재주입 불필요. churn 억제·에러 UI 는
    /// 앱 정책이라 호출측(AppDelegate.restartRouter)에 남는다 — 여기선 '재생성=stop+start' 만 감춘다.
    @discardableResult
    func recreate() -> Bool {
        stop()
        return start()
    }

    /// Sleep/wake 후 외부 트리거로 tap 강제 재활성. 이벤트 도착 없이도 enable 보장.
    /// `tapEnable(true)` 는 idempotent — 이미 enabled 면 noop. 첫 Caps 입력 lag 방지.
    /// 반환: 재활성 후 실제 enabled 상태. 깊은 sleep/TCC 토글/WindowServer 재시작으로
    /// CFMachPort 자체가 무효화되면 tapEnable 은 silent no-op 이라 false → 호출측이 재생성해야 함.
    @discardableResult
    func revalidate() -> Bool {
        guard let tap = eventTap else { return false }
        CGEvent.tapEnable(tap: tap, enable: true)
        return CGEvent.tapIsEnabled(tap: tap)
    }

    /// tap disable 이벤트 후처리 — 콜백(tap 스레드)이 main 으로 위임. eventTap 이 main 소유라
    /// 여기서만 만진다. 재활성이 안 먹으면 (죽은 포트) 재생성 요청.
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

        // tap 비활성화 이벤트 — 통과시키고 후처리(재활성·재생성 판단)는 main 으로.
        // eventTap 프로퍼티가 main 소유라 콜백(tap 스레드)에선 안 만진다.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // notice = 디스크 영속 — 간헐 입력 이상(조합 중 글자 사라짐 등) 사후 부검용.
            log.notice("tap disabled (\(type == .tapDisabledByTimeout ? "timeout" : "userInput", privacy: .public)) — 재활성 위임")
            DispatchQueue.main.async {
                router.handleTapDisabled()
            }
            return Unmanaged.passUnretained(event)
        }

        if type == .keyDown {
            if event.getIntegerValueField(.eventSourceUserData) == Router.synthMarker {
                return Unmanaged.passUnretained(event)
            }
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let state = router.tapState.withLock { $0 }

            // F17 = 🔍 기능 키 (hidutil이 바꿔 보냄). 길게 눌러도 한 번만 연다.
            if keyCode == Int64(kVK_F17), state.searchKeyEnabled {
                if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                    Router.postSearchShortcut()
                }
                return nil
            }

            // F18 = Right Command 모드의 Caps Lock (hidutil이 바꿔 보냄) — 대문자 잠금 방아쇠.
            // 이 모드에선 항상 소비한다: Caps는 앱 소유 키라 OS로 흘리면 유령 F18이 된다.
            // 영문 → Shift Lock 토글 / 한국어 + Shift → Easter Egg (Caps Lock 모드와 같은 움직임)
            // / 한국어 plain → 아무 일 없음 (한글에선 대문자 잠금을 만들지 않는 규칙).
            if keyCode == Int64(kVK_F18), state.transitionKey == .rightCommand {
                if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
                    return nil
                }
                let flags = event.flags
                let hasHardModifier = flags.contains(.maskCommand)
                    || flags.contains(.maskAlternate)
                    || flags.contains(.maskControl)
                let isKorean = state.isKorean
                if !hasHardModifier {
                    let onlyShift = flags.contains(.maskShift)
                    DispatchQueue.main.async {
                        if isKorean {
                            if onlyShift { router.onShiftCapsKorean?() }
                        } else {
                            router.shiftLock?.toggle()
                        }
                    }
                }
                return nil
            }

            if keyCode == Int64(kVK_F19) {
                // autorepeat F19 는 삼킨다 — hold 시 OS 가 반복 전환하지 않게 (한 번만).
                if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
                    return nil
                }
                let flags = event.flags
                let onlyShift = flags.contains(.maskShift)
                    && !flags.contains(.maskCommand)
                    && !flags.contains(.maskAlternate)
                    && !flags.contains(.maskControl)
                // Caps Lock 모드에서 앱이 가로채는 유일한 F19: Shift+F19.
                //   영문 → Shift Lock 토글 / 한국어 → Easter Egg. (소비 = OS 로 안 흘림)
                // Settings 는 UserDefaults 직독 — 스레드 세이프.
                if onlyShift && state.transitionKey == .capsLock {
                    let isKorean = state.isKorean
                    // 행동은 main 으로 — ShiftLock(단일 진실 출처)·Morse 는 main 에서만 산다.
                    DispatchQueue.main.async {
                        if isKorean {
                            router.onShiftCapsKorean?()
                        } else {
                            router.shiftLock?.toggle()
                        }
                    }
                    return nil
                }
                // 그 외 모든 F19 (plain·Cmd/Option/Ctrl·Right Command의 Shift+F19) → 흘려보내기.
                // plain F19 는 OS "다음 입력 소스" 단축키가 한영 전환. (한영 전환 OS 위임 — C②)
                return Unmanaged.passUnretained(event)
            }

            // Shift Lock 활성 + 영문 + Cmd/Option/Ctrl 미포함 → 알파벳 keydown 에 Shift flag 끼얹기.
            // 스냅샷 읽기 — 토글 직후 main 왕복 (~ms) 동안 옛 상태로 처리될 수 있는 창이 있으나,
            // 사람 타이핑으론 사실상 못 열고 어긋나도 글자 하나 대소문자 밀림에 그침 (설계 수용).
            let flags = event.flags
            let hasOtherModifier = flags.contains(.maskCommand)
                    || flags.contains(.maskAlternate)
                    || flags.contains(.maskControl)
            if TransitionBehavior.shouldInjectShift(
                shiftLockActive: state.shiftLockActive,
                isKorean: state.isKorean,
                isAlphabet: Router.alphabetKeyCodes.contains(keyCode),
                hasOtherModifier: hasOtherModifier
            ) {
                event.flags = flags.union(.maskShift)
            }
        }

        return Unmanaged.passUnretained(event)
    }
}
