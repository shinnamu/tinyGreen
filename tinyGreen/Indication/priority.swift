import Foundation

/// 입력 소스·synthetic Shift Lock·native Caps·Easter Egg 네 신호를 모아 *무엇을 비출지*
/// 한 곳에서 판가름한다. 우선순위: Easter Egg > Shift Lock/native Caps blink > base(한영).
/// 결과 = `DisplayIntent`.
/// 표면(LED·메뉴바 인디케이터)은 이걸 콜백(`onChange`)으로 받아 *어떻게* 비출지(자기 게이트)만 정한다.
/// "무엇을"(여기) / "어떻게"(표면) 분리 — 두 표면에 흩어졌던 우선순위 중복을 모음.
///
/// 점멸 타이밍도 여기 소유: Shift Lock 점멸(shiftLockActive && !isKorean → 200ms 토글).
/// Easter Egg phase 는 Morse 가 알림으로 줘 받기만 한다.
///
/// **error 는 여기 없다** — 메뉴바 표면 전용(LED 는 에러를 LED 로 표현 안 함). 표면이 따로 단락.
/// 모든 상태 접근은 main thread (알림·타이머 전부 main) 라 lock 불필요.
final class Priority {
    /// 무엇을 비출지 — 어느 층이 이겼나 + 그 층의 점멸 위상. isKorean 은 항상 동봉:
    /// 표면이 자기 게이트로 층을 무를 때(예: 인디케이터 점멸 OFF) base 로 폴백하는 데 쓴다.
    struct DisplayIntent: Equatable {
        let layer: Layer
        let isKorean: Bool
    }

    enum Layer: Equatable {
        case easterEgg(lit: Bool)    // Easter Egg phase (모스 시퀀스)
        case shiftLock(blink: Bool)  // Shift Lock 점멸 위상 (200ms)
        case base                    // 한영 전환 결과 — 표면이 isKorean 으로 렌더
    }

    /// intent 변할 때마다 호출 (표면 구독). AppDelegate 가 두 표면 indicate 로 배선. main thread.
    var onChange: ((DisplayIntent) -> Void)?

    private var isKorean = false
    private var shiftLockActive = false
    private var easterEggActive = false
    private var easterEggPhase = false
    private var blinking = false
    private var blinkPhase = false
    private var blinkTimer: Timer?

    private let observers = ObserverBag()

    func start() {
        observers.add(name: .tinyGreenInputSourceChanged) { [weak self] notif in
            guard let self = self else { return }
            self.isKorean = (notif.userInfo?[Notification.isKoreanKey] as? Bool) ?? false
            self.updateBlinking()  // 한글 모드 진입 시 Shift Lock 점멸 멈춤 (base 복귀)
            self.emit()
        }
        observers.add(name: .tinyGreenShiftLockChanged) { [weak self] notif in
            guard let self = self else { return }
            self.shiftLockActive = (notif.userInfo?[Notification.shiftLockActiveKey] as? Bool) ?? false
            self.updateBlinking()
            self.emit()
        }
        observers.add(name: .tinyGreenEasterEggChanged) { [weak self] notif in
            guard let self = self else { return }
            self.easterEggActive = (notif.userInfo?[Notification.easterEggActiveKey] as? Bool) ?? false
            self.easterEggPhase = (notif.userInfo?[Notification.easterEggPhaseKey] as? Bool) ?? false
            self.emit()
        }
    }

    func stop() {
        observers.removeAll()
        stopBlinkTimer()
        blinking = false
    }

    /// 현재 상태로 intent 산출 (emit 이 매 변화에 호출). 초기 렌더는 알림 경로로 구동 —
    /// watcher.start() 의 첫 publish + AppDelegate 시작 sync post 가 input 옵저버→emit 을 깨운다.
    private func currentIntent() -> DisplayIntent {
        let layer: Layer
        if easterEggActive {
            layer = .easterEgg(lit: easterEggPhase)
        } else if blinking {
            layer = .shiftLock(blink: blinkPhase)
        } else {
            layer = .base
        }
        return DisplayIntent(layer: layer, isKorean: isKorean)
    }

    /// 합성 Shift Lock이 활성이고 영문일 때만 점멸 타이머 가동. 한글 모드면 멈추고
    /// base 복귀. 두 모드 공통 — 방아쇠(Shift+F19 / F18)만 다르고 상태는 하나다.
    private func updateBlinking() {
        let shouldBlink = TransitionBehavior.shouldBlink(
            shiftLockActive: shiftLockActive,
            isKorean: isKorean
        )
        guard blinking != shouldBlink else { return }
        blinking = shouldBlink
        if shouldBlink {
            blinkPhase = false
            let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                self.blinkPhase.toggle()
                self.emit()
            }
            // .common — default 모드 타이머는 메뉴 트래킹·모달 중 멈춰 점멸이 얼어붙는다.
            RunLoop.main.add(timer, forMode: .common)
            blinkTimer = timer
        } else {
            stopBlinkTimer()
        }
    }

    private func stopBlinkTimer() {
        blinkTimer?.invalidate()
        blinkTimer = nil
    }

    private func emit() {
        onChange?(currentIntent())
    }
}
