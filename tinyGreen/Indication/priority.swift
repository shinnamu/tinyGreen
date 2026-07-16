import Foundation

final class Priority {
    struct DisplayIntent: Equatable {
        let layer: Layer
        let isKorean: Bool
    }

    enum Layer: Equatable {
        case easterEgg(lit: Bool)
        case shiftLock(blink: Bool)
        case base
    }

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
            self.updateBlinking()
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

    private func updateBlinking() {
        let shouldBlink = shiftLockActive && !isKorean
        guard blinking != shouldBlink else { return }
        blinking = shouldBlink
        if shouldBlink {
            blinkPhase = false
            let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                self.blinkPhase.toggle()
                self.emit()
            }
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
