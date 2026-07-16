import Foundation

extension Notification.Name {
    static let tinyGreenInputSourceChanged = Notification.Name("\(bundleID).inputSourceChanged")

    static let tinyGreenCoreError = Notification.Name("\(bundleID).coreError")

    static let tinyGreenShiftLockChanged = Notification.Name("\(bundleID).shiftLockChanged")

    static let tinyGreenEasterEggChanged = Notification.Name("\(bundleID).easterEggChanged")

    static let tinyGreenSettingsChanged = Notification.Name("\(bundleID).settingsChanged")

    static let tinyGreenAutoShowLEDOpenAlert = Notification.Name("\(bundleID).autoShowLedOpenAlert")
}

enum CoreErrorCategory: String {
    case permissions
    case mappingApply
    case routerStart
    case ledOpen

    var systemFailure: SystemFailure? {
        SystemFailure(rawValue: rawValue)
    }
}

enum SystemFailure: String {
    case mappingApply
    case routerStart
    case ledOpen
}

extension Notification {
    static let isKoreanKey = "isKorean"
    static let errorMessageKey = "errorMessage"
    static let errorCategoryKey = "errorCategory"
    static let shiftLockActiveKey = "shiftLockActive"
    static let easterEggActiveKey = "easterEggActive"
    static let easterEggPhaseKey = "easterEggPhase"

    static func postTinyGreenCoreError(_ message: String?, category: CoreErrorCategory? = nil) {
        var userInfo: [String: Any] = [:]
        if let message = message {
            userInfo[Self.errorMessageKey] = message
        }
        if let category = category {
            userInfo[Self.errorCategoryKey] = category.rawValue
        }
        NotificationCenter.default.post(
            name: .tinyGreenCoreError,
            object: nil,
            userInfo: userInfo.isEmpty ? nil : userInfo
        )
    }
}
