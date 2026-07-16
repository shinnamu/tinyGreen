import Foundation

enum TransitionKey: String, CaseIterable, Hashable {
    case capsLock = "capsLock"
    case rightCommand = "rightCommand"

    var hidUsage: UInt64 {
        switch self {
        case .capsLock: return 0x700000039
        case .rightCommand: return 0x7000000E7
        }
    }

    var menuTitle: String {
        switch self {
        case .capsLock: return "Caps Lock"
        case .rightCommand: return "Right Command"
        }
    }

    var lockKeyGlyphs: String {
        switch self {
        case .capsLock: return "⇧⇪"
        case .rightCommand: return "⇪"
        }
    }
}

enum TransitionBehavior {
    static func shouldInjectShift(
        shiftLockActive: Bool,
        isKorean: Bool,
        isAlphabet: Bool,
        hasOtherModifier: Bool
    ) -> Bool {
        shiftLockActive
            && !isKorean
            && isAlphabet
            && !hasOtherModifier
    }

    static func shouldBlink(
        shiftLockActive: Bool,
        isKorean: Bool
    ) -> Bool {
        shiftLockActive && !isKorean
    }
}

enum Settings {
    private static let ledInvertedKey = "\(bundleID).ledInverted"
    private static let menuBarLEDEnabledKey = "\(bundleID).menuBarLEDEnabled"
    private static let capsLockLEDEnabledKey = "\(bundleID).capsLockLEDEnabled"
    private static let showInputSourceKey = "\(bundleID).showInputSource"
    private static let hasAskedAboutLoginItemKey = "\(bundleID).hasAskedAboutLoginItem"
    private static let hasShownPermissionAlertKey = "\(bundleID).hasShownPermissionAlert"
    private static let ledOpenAlertSuppressedKey = "\(bundleID).ledOpenAlertSuppressed"
    private static let transitionKeyKey = "\(bundleID).transitionKey"
    private static let appliedTransitionKeyKey = "\(bundleID).appliedTransitionKey"
    private static let stashedCapsDstKey = "\(bundleID).stashedCapsDst"
    private static let stashedRightCommandDstKey = "\(bundleID).stashedRightCommandDst"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            ledInvertedKey: true,
            menuBarLEDEnabledKey: true,
            capsLockLEDEnabledKey: true,
            showInputSourceKey: false,
            hasAskedAboutLoginItemKey: false,
            hasShownPermissionAlertKey: false,
            ledOpenAlertSuppressedKey: false,
            transitionKeyKey: TransitionKey.capsLock.rawValue
        ])
    }

    static var transitionKey: TransitionKey {
        get {
            guard let raw = UserDefaults.standard.string(forKey: transitionKeyKey),
                  let key = TransitionKey(rawValue: raw) else {
                return .capsLock
            }
            return key
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: transitionKeyKey)
        }
    }

    static var appliedTransitionKey: TransitionKey? {
        get {
            guard let raw = UserDefaults.standard.string(forKey: appliedTransitionKeyKey) else {
                return nil
            }
            return TransitionKey(rawValue: raw)
        }
        set {
            if let key = newValue {
                UserDefaults.standard.set(key.rawValue, forKey: appliedTransitionKeyKey)
            } else {
                UserDefaults.standard.removeObject(forKey: appliedTransitionKeyKey)
            }
        }
    }

    static var showInputSource: Bool {
        get { UserDefaults.standard.bool(forKey: showInputSourceKey) }
        set { UserDefaults.standard.set(newValue, forKey: showInputSourceKey) }
    }

    static var stashedCapsDst: UInt64? {
        get { stashedDst(for: .capsLock) }
        set { setStashedDst(newValue, for: .capsLock) }
    }

    static func stashedDst(for key: TransitionKey) -> UInt64? {
        let storageKey = key == .capsLock ? stashedCapsDstKey : stashedRightCommandDstKey
        if let string = UserDefaults.standard.string(forKey: storageKey) {
            return UInt64(string)
        }
        if let number = UserDefaults.standard.object(forKey: storageKey) as? NSNumber {
            return number.uint64Value
        }
        return nil
    }

    static func setStashedDst(_ value: UInt64?, for key: TransitionKey) {
        let storageKey = key == .capsLock ? stashedCapsDstKey : stashedRightCommandDstKey
        if let value {
            UserDefaults.standard.set(String(value), forKey: storageKey)
        } else {
            UserDefaults.standard.removeObject(forKey: storageKey)
        }
    }

    static var ledInverted: Bool {
        get { UserDefaults.standard.bool(forKey: ledInvertedKey) }
        set { UserDefaults.standard.set(newValue, forKey: ledInvertedKey) }
    }

    static var menuBarLEDEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: menuBarLEDEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: menuBarLEDEnabledKey) }
    }

    static var capsLockLEDEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: capsLockLEDEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: capsLockLEDEnabledKey) }
    }

    static var hasAskedAboutLoginItem: Bool {
        get { UserDefaults.standard.bool(forKey: hasAskedAboutLoginItemKey) }
        set { UserDefaults.standard.set(newValue, forKey: hasAskedAboutLoginItemKey) }
    }

    static var hasShownPermissionAlert: Bool {
        get { UserDefaults.standard.bool(forKey: hasShownPermissionAlertKey) }
        set { UserDefaults.standard.set(newValue, forKey: hasShownPermissionAlertKey) }
    }

    static var ledOpenAlertSuppressed: Bool {
        get { UserDefaults.standard.bool(forKey: ledOpenAlertSuppressedKey) }
        set { UserDefaults.standard.set(newValue, forKey: ledOpenAlertSuppressedKey) }
    }

    private static func ledOn(enabled: Bool, isKorean: Bool) -> Bool {
        guard enabled else { return false }
        return ledInverted ? !isKorean : isKorean
    }

    static func menuBarLEDShouldBeOn(isKorean: Bool) -> Bool {
        ledOn(enabled: menuBarLEDEnabled, isKorean: isKorean)
    }

    static func capsLockLEDShouldBeOn(isKorean: Bool) -> Bool {
        ledOn(enabled: capsLockLEDEnabled, isKorean: isKorean)
    }
}
