import AppKit

/// 메뉴바 도트 시각상태 — Priority 가 준 intent 를 indicate 로 받아 그리는 표현 표면. CapsLockLED 의 형제.
/// 무엇을 비출지(우선순위 easterEgg>shiftLock>base · 점멸 타이밍)는 Priority 소유. 여기선 *어떻게* —
/// 메뉴바 게이트로 옮긴다: error 단락(메뉴바 전용) > 이긴 층의 점멸 위상(shiftLock 만 게이트) > base.
/// 도형은 Render. error 플래그는 StatusMenu 가 setError 로 push (메뉴바 표면 전용 — LED 엔 error 표시 없음).
///
/// CapsLockLED 와 형제이되 덜 자족적이다: LED 는 자기 IOHIDManager(자원)를 start/stop 으로 열고 닫지만,
/// 도트는 자원이 없고 StatusMenu 의 statusItem.button 에 attach/detach 로 얹힌다 (button 소유 안 함, weak).
/// start/stop 은 settingsChanged 구독 lifecycle 만 — LED 미러.
final class MenuBarLED {
    /// StatusMenu 의 statusItem.button 을 주입받아 weak 보유 — statusItem 파괴 시 자동 nil.
    private weak var button: NSStatusBarButton?

    /// Priority 가 준 마지막 intent — 무엇을 비출지. 도트 렌더의 단일 기준. 점멸 타이밍은 Priority 소유.
    /// hide(detach) 중에도 indicate 가 계속 갱신해 와 show(attach) 시 마지막 intent 그대로 복구.
    private var lastIntent = Priority.DisplayIntent(layer: .base, isKorean: false)
    /// 활성 에러 여부 — true 면 메뉴바 도트 주황색. StatusMenu.applyErrorMessage 가 setError 로 push (단방향).
    private var errorActive = false

    private let observers = ObserverBag()

    private lazy var iconActive: NSImage = Render.menuBarDot(active: true)
    private lazy var iconInactive: NSImage = Render.menuBarDot(active: false)
    private lazy var iconError: NSImage = Render.menuBarDot(active: false, error: true)
    // "입력 소스 보기" ON 시 사용 — 6 variants + Shift Lock green narrow:
    //   narrow (22pt) — LED 사용 OFF
    //   wide unlit (24pt, 도트 없음) — LED 사용 ON 이지만 현재 언어 매핑 inactive
    //   wide lit (24pt + 도트) — LED 사용 ON + 현재 언어 매핑 active
    //   narrow green (22pt, systemGreen) — Shift Lock 깜빡 phase (LED OFF + 입력 소스 보기 ON)
    private lazy var iconInputNarrowKorean: NSImage = Render.menuBarInputSourceImage(wide: false, lit: false, isKorean: true)
    private lazy var iconInputNarrowEnglish: NSImage = Render.menuBarInputSourceImage(wide: false, lit: false, isKorean: false)
    private lazy var iconInputWideUnlitKorean: NSImage = Render.menuBarInputSourceImage(wide: true, lit: false, isKorean: true)
    private lazy var iconInputWideUnlitEnglish: NSImage = Render.menuBarInputSourceImage(wide: true, lit: false, isKorean: false)
    private lazy var iconInputWideLitKorean: NSImage = Render.menuBarInputSourceImage(wide: true, lit: true, isKorean: true)
    private lazy var iconInputWideLitEnglish: NSImage = Render.menuBarInputSourceImage(wide: true, lit: true, isKorean: false)
    private lazy var iconInputNarrowGreenKorean: NSImage = Render.menuBarInputSourceImageGreen(isKorean: true)
    private lazy var iconInputNarrowGreenEnglish: NSImage = Render.menuBarInputSourceImageGreen(isKorean: false)

    /// settingsChanged 자가구독 — LED 매핑 / 사용 토글 등 설정 변경 시 게이트만 바뀌니 마지막 intent 를
    /// 다시 그린다 (Priority 는 설정을 모름 = 표면 게이트). CapsLockLED.start 의 settingsChanged 구독 미러.
    func start() {
        observers.add(name: .tinyGreenSettingsChanged) { [weak self] _ in
            self?.refresh()
        }
    }

    func stop() {
        observers.removeAll()
    }

    /// StatusMenu.makeStatusItem 이 statusItem 생성 직후 button 주입 — 즉시 현재 상태 렌더.
    func attach(_ button: NSStatusBarButton?) {
        self.button = button
        refresh()
    }

    /// button 회수 (hide/stop). lastIntent·errorActive 는 보존 — show 시 그대로 복구.
    func detach() {
        button = nil
    }

    /// Priority 가 intent 변할 때마다 호출 (AppDelegate 배선). main thread.
    func indicate(_ intent: Priority.DisplayIntent) {
        lastIntent = intent
        refresh()
    }

    /// 코어 에러 활성 여부 — StatusMenu.applyErrorMessage 가 push. 도트 색만 정함 (에러 메뉴줄은 StatusMenu 소유).
    func setError(active: Bool) {
        errorActive = active
        refresh()
    }

    /// 이긴 층 → 메뉴바 도트 깜빡 위상. Easter Egg·Shift Lock 점멸 모두 항상 honor —
    /// 키보드 LED 와 같은 움직임 (점멸 게이트 설정은 2026-08-04 제거, 옵션이던 시절의 잔재).
    private func invertedPhase() -> Bool {
        switch lastIntent.layer {
        case .easterEgg(let lit): return lit
        case .shiftLock(let blink): return blink
        case .base: return false
        }
    }

    /// 메뉴바 도트 + a11y label 갱신. 에러 활성 시 빨간 도트 우선 표시 (메뉴바 전용 단락).
    /// "입력 소스 보기" ON 시 도트 + 한/A 박스 합성 이미지 사용.
    /// 우선순위: Easter Egg phase > Shift Lock blinkPhase > 정상 (Priority 가 가린 층을 inverted 로 받음).
    /// inverted=true 일 때 케이스별 토글:
    ///   - 도트만 (showInputSource OFF) → active ↔ inactive
    ///   - 박스만 (LED OFF + showInputSource ON) → narrow ↔ narrowGreen
    ///   - 박스+도트 (LED ON + showInputSource ON) → lit ↔ unlit
    /// button 이 nil (hide·detach 중) 이면 no-op — show 시 attach 가 다시 그린다.
    func refresh() {
        guard let button = button else { return }
        if errorActive {
            button.image = iconError
            button.setAccessibilityLabel("TinyGreen — 오류")
            return
        }
        let isKor = lastIntent.isKorean
        button.setAccessibilityLabel(menuBarA11yLabel(isKorean: isKor))
        let isActive = Settings.menuBarLEDShouldBeOn(isKorean: isKor)
        let inverted = invertedPhase()
        if Settings.showInputSource {
            if Settings.menuBarLEDEnabled {
                // 박스+도트 — lit/unlit 토글로 도트 깜빡 (박스는 정적).
                let effectiveLit = inverted ? !isActive : isActive
                if effectiveLit {
                    button.image = isKor ? iconInputWideLitKorean : iconInputWideLitEnglish
                } else {
                    button.image = isKor ? iconInputWideUnlitKorean : iconInputWideUnlitEnglish
                }
            } else {
                // 박스만 — 정상 ↔ green 박스 토글 (박스 자체가 깜빡).
                if inverted {
                    button.image = isKor ? iconInputNarrowGreenKorean : iconInputNarrowGreenEnglish
                } else {
                    button.image = isKor ? iconInputNarrowKorean : iconInputNarrowEnglish
                }
            }
        } else {
            // 도트만 — active/inactive 토글.
            let effectiveActive = inverted ? !isActive : isActive
            button.image = effectiveActive ? iconActive : iconInactive
        }
    }

    private func menuBarA11yLabel(isKorean: Bool) -> String {
        isKorean ? "TinyGreen — 한국어 입력 중" : "TinyGreen — 영어 입력 중"
    }
}
