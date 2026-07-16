import AppKit

final class MenuBarLED {
    private weak var button: NSStatusBarButton?

    private var lastIntent = Priority.DisplayIntent(layer: .base, isKorean: false)
    private var errorActive = false

    private let observers = ObserverBag()

    private lazy var iconActive: NSImage = Render.menuBarDot(active: true)
    private lazy var iconInactive: NSImage = Render.menuBarDot(active: false)
    private lazy var iconError: NSImage = Render.menuBarDot(active: false, error: true)
    private lazy var iconInputNarrowKorean: NSImage = Render.menuBarInputSourceImage(wide: false, lit: false, isKorean: true)
    private lazy var iconInputNarrowEnglish: NSImage = Render.menuBarInputSourceImage(wide: false, lit: false, isKorean: false)
    private lazy var iconInputWideUnlitKorean: NSImage = Render.menuBarInputSourceImage(wide: true, lit: false, isKorean: true)
    private lazy var iconInputWideUnlitEnglish: NSImage = Render.menuBarInputSourceImage(wide: true, lit: false, isKorean: false)
    private lazy var iconInputWideLitKorean: NSImage = Render.menuBarInputSourceImage(wide: true, lit: true, isKorean: true)
    private lazy var iconInputWideLitEnglish: NSImage = Render.menuBarInputSourceImage(wide: true, lit: true, isKorean: false)
    private lazy var iconInputNarrowGreenKorean: NSImage = Render.menuBarInputSourceImageGreen(isKorean: true)
    private lazy var iconInputNarrowGreenEnglish: NSImage = Render.menuBarInputSourceImageGreen(isKorean: false)

    func start() {
        observers.add(name: .tinyGreenSettingsChanged) { [weak self] _ in
            self?.refresh()
        }
    }

    func stop() {
        observers.removeAll()
    }

    func attach(_ button: NSStatusBarButton?) {
        self.button = button
        refresh()
    }

    func detach() {
        button = nil
    }

    func indicate(_ intent: Priority.DisplayIntent) {
        lastIntent = intent
        refresh()
    }

    func setError(active: Bool) {
        errorActive = active
        refresh()
    }

    private func invertedPhase() -> Bool {
        switch lastIntent.layer {
        case .easterEgg(let lit): return lit
        case .shiftLock(let blink): return Settings.shiftLockMenuBarIndicatorEnabled ? blink : false
        case .base: return false
        }
    }

    func refresh() {
        guard let button = button else { return }
        if errorActive {
            button.image = iconError
            button.setAccessibilityLabel("tinyGreen — 오류")
            return
        }
        let isKor = lastIntent.isKorean
        button.setAccessibilityLabel(menuBarA11yLabel(isKorean: isKor))
        let isActive = Settings.menuBarLEDShouldBeOn(isKorean: isKor)
        let inverted = invertedPhase()
        if Settings.showInputSource {
            if Settings.menuBarLEDEnabled {
                let effectiveLit = inverted ? !isActive : isActive
                if effectiveLit {
                    button.image = isKor ? iconInputWideLitKorean : iconInputWideLitEnglish
                } else {
                    button.image = isKor ? iconInputWideUnlitKorean : iconInputWideUnlitEnglish
                }
            } else {
                if inverted {
                    button.image = isKor ? iconInputNarrowGreenKorean : iconInputNarrowGreenEnglish
                } else {
                    button.image = isKor ? iconInputNarrowKorean : iconInputNarrowEnglish
                }
            }
        } else {
            let effectiveActive = inverted ? !isActive : isActive
            button.image = effectiveActive ? iconActive : iconInactive
        }
    }

    private func menuBarA11yLabel(isKorean: Bool) -> String {
        isKorean ? "tinyGreen — 한국어 입력 중" : "tinyGreen — 영어 입력 중"
    }
}
