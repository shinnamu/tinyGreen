import Foundation

/// LED 종류 — 메뉴바 도트 vs 키보드 Caps Lock LED.
enum LEDKind {
    case menuBar, capsLock

    var menuTitle: String {
        switch self {
        // 애플 한국어 용어: indicator = 표시기 (Mac 사용 설명서 "개인정보 보호 표시기", iPhone "상태 막대의 주황색 및 녹색 표시기"). 2026-09-16.
        case .menuBar: return "메뉴 막대 표시기"
        case .capsLock: return "키보드 표시기"
        }
    }

    var symbolName: String {
        switch self {
        case .menuBar: return "menubar.rectangle"
        case .capsLock: return "keyboard"
        }
    }

    var enabled: Bool {
        get {
            switch self {
            case .menuBar: return Settings.menuBarLEDEnabled
            case .capsLock: return Settings.capsLockLEDEnabled
            }
        }
        nonmutating set {
            switch self {
            case .menuBar: Settings.menuBarLEDEnabled = newValue
            case .capsLock: Settings.capsLockLEDEnabled = newValue
            }
        }
    }

    /// 매핑은 LED 종류 무관 공통.
    var inverted: Bool { Settings.ledInverted }
}

/// LED 매핑 라디오 옵션 — 어느 언어 활성 시 LED ON 인지. NSMenuItem.representedObject 에 직접 set.
enum LEDLanguage {
    case korean, english

    init(inverted: Bool) {
        self = inverted ? .english : .korean
    }

    var inverted: Bool { self == .english }
}
