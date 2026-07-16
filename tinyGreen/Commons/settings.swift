import Foundation

enum Settings {
    private static let ledInvertedKey = "\(bundleID).ledInverted"
    private static let menuBarLEDEnabledKey = "\(bundleID).menuBarLEDEnabled"
    private static let capsLockLEDEnabledKey = "\(bundleID).capsLockLEDEnabled"
    private static let showInputSourceKey = "\(bundleID).showInputSource"
    private static let shiftLockEnabledKey = "\(bundleID).shiftLockEnabled"
    private static let shiftLockMenuBarIndicatorEnabledKey = "\(bundleID).shiftLockMenuBarIndicatorEnabled"
    private static let legacyShiftLockMenuBarAlertEnabledKey = "\(bundleID).shiftLockMenuBarAlertEnabled"
    private static let hasAskedAboutLoginItemKey = "\(bundleID).hasAskedAboutLoginItem"
    private static let hasShownPermissionAlertKey = "\(bundleID).hasShownPermissionAlert"
    private static let ledOpenAlertSuppressedKey = "\(bundleID).ledOpenAlertSuppressed"
    private static let stashedCapsDstKey = "\(bundleID).stashedCapsDst"

    static func registerDefaults() {
        migrateLegacyKeys()
        UserDefaults.standard.register(defaults: [
            ledInvertedKey: true,
            menuBarLEDEnabledKey: true,
            capsLockLEDEnabledKey: true,
            showInputSourceKey: false,
            shiftLockEnabledKey: true,
            shiftLockMenuBarIndicatorEnabledKey: true,
            hasAskedAboutLoginItemKey: false,
            hasShownPermissionAlertKey: false,
            ledOpenAlertSuppressedKey: false
        ])
    }

    static func migrateLegacyKeys(ud: UserDefaults = .standard) {
        if ud.object(forKey: shiftLockMenuBarIndicatorEnabledKey) == nil,
           let legacy = ud.object(forKey: legacyShiftLockMenuBarAlertEnabledKey) {
            ud.set(legacy, forKey: shiftLockMenuBarIndicatorEnabledKey)
            ud.removeObject(forKey: legacyShiftLockMenuBarAlertEnabledKey)
        }
    }

    static var showInputSource: Bool {
        get { UserDefaults.standard.bool(forKey: showInputSourceKey) }
        set { UserDefaults.standard.set(newValue, forKey: showInputSourceKey) }
    }

    static var stashedCapsDst: UInt64? {
        get {
            guard let s = UserDefaults.standard.string(forKey: stashedCapsDstKey) else { return nil }
            return UInt64(s)
        }
        set {
            if let v = newValue {
                UserDefaults.standard.set(String(v), forKey: stashedCapsDstKey)
            } else {
                UserDefaults.standard.removeObject(forKey: stashedCapsDstKey)
            }
        }
    }

    static var shiftLockEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: shiftLockEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: shiftLockEnabledKey) }
    }

    static var shiftLockMenuBarIndicatorEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: shiftLockMenuBarIndicatorEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: shiftLockMenuBarIndicatorEnabledKey) }
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
