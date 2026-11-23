import Foundation

extension Notification.Name {
    /// 입력 소스 변화 — 시스템 알림 + 내부 트리거 둘 다 발행.
    /// userInfo["isKorean": Bool] 으로 현재 상태 전달 (관찰자가 TIS 재조회 안 하게).
    static let tinyGreenInputSourceChanged = Notification.Name("\(bundleID).inputSourceChanged")

    /// 코어 에러 발생 — userInfo["errorMessage": String] 으로 메시지 전달.
    static let tinyGreenCoreError = Notification.Name("\(bundleID).coreError")

    /// Shift Lock 모드 변화 — userInfo["shiftLockActive": Bool] 로 현재 상태.
    static let tinyGreenShiftLockChanged = Notification.Name("\(bundleID).shiftLockChanged")

    /// Easter Egg 모드 변화 + phase 토글 — userInfo[easterEggActive: Bool, easterEggPhase: Bool].
    /// 한국어 모드 Shift+Caps 트리거. ~14.2초 동안 모스 부호로 "tinygreen" 점멸.
    static let tinyGreenEasterEggChanged = Notification.Name("\(bundleID).easterEggChanged")

    /// 설정 변경 — 입력 소스 변화는 아니지만 LED/메뉴바 hardware 갱신 필요할 때 발행.
    /// LED 사용 토글 / LED 라디오 (매핑 언어) 변경 등. `tinyGreenInputSourceChanged` 와
    /// 분리되어 있어 옵저버는 한영 전환 의도된 부작용 (Shift Lock 자동 해제) 안 거침.
    /// userInfo 없음.
    static let tinyGreenSettingsChanged = Notification.Name("\(bundleID).settingsChanged")

    /// F5 (LED 연결 실패) alert 자동 표시 트리거. CapsLockLED 가 IOHIDManagerOpen 실패 시
    /// 발행. StatusMenu 가 받아 alert 띄움. errorItem 클릭 경로와 별개 — 사용자 인지 보장.
    /// userInfo 없음.
    static let tinyGreenAutoShowLEDOpenAlert = Notification.Name("\(bundleID).autoShowLedOpenAlert")
}

/// 코어 에러 카테고리 — errorItem 클릭 시 분기 (시스템 설정 vs 자세한 정보 alert).
/// permissions: F1/F2 — 시스템 설정 자동 열기 (사용자 해결 가능).
/// 그 외: F3-F5 — 자세한 정보 alert (시스템 레벨 실패 / 사용자 안내).
enum CoreErrorCategory: String {
    case permissions
    case mappingApply
    case routerStart
    case ledOpen

    /// 시스템 레벨 실패로의 좁히기. nil = permissions (클릭 = 설정 열기).
    /// rawValue 로 잇는 부분집합이라 중복 switch 없이 갈래가 한 곳에 산다.
    var systemFailure: SystemFailure? {
        SystemFailure(rawValue: rawValue)
    }
}

/// CoreErrorCategory 의 시스템 레벨 실패 부분집합 (F3-F5) — alert 본문이 여기 매달려
/// "권한 카테고리엔 alert 본문 없음"이 컴파일 타임에 성립 (옛 빈 AlertContent placeholder 제거).
enum SystemFailure: String {
    case mappingApply
    case routerStart
    case ledOpen
}

extension Notification {
    /// `.tinyGreenInputSourceChanged` userInfo 의 isKorean 키.
    static let isKoreanKey = "isKorean"
    /// `.tinyGreenCoreError` userInfo 의 메시지 키.
    static let errorMessageKey = "errorMessage"
    /// `.tinyGreenCoreError` userInfo 의 카테고리 키 (rawValue).
    static let errorCategoryKey = "errorCategory"
    /// `.tinyGreenShiftLockChanged` userInfo 의 active 키.
    static let shiftLockActiveKey = "shiftLockActive"
    /// `.tinyGreenEasterEggChanged` userInfo 의 active / phase 키.
    static let easterEggActiveKey = "easterEggActive"
    static let easterEggPhaseKey = "easterEggPhase"
    /// 코어 에러 알림 발행. nil = 에러 클리어. AppDelegate / CapsLockLED 에서 사용.
    /// `category` 는 errorItem 클릭 분기에 사용. 클리어 (message=nil) 시 category 무시.
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
