import Foundation

enum LEDKind {
    case menuBar, capsLock

    var menuTitle: String {
        switch self {
        case .menuBar: return "메뉴 막대 인디케이터"
        case .capsLock: return "키보드 인디케이터"
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

    var inverted: Bool { Settings.ledInverted }
}

enum LEDLanguage {
    case korean, english

    init(inverted: Bool) {
        self = inverted ? .english : .korean
    }

    var inverted: Bool { self == .english }
}
