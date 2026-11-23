import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// 한영 전환에 사용할 물리 키. hidutil은 이 키를 F19로 바꾸고,
/// 이후의 전환은 macOS의 "다음 입력 소스 선택"에 맡긴다.
///
/// Caps Lock이 첫 버전부터 쓰던 기본값이라, 키가 저장돼 있지 않거나 알 수 없는
/// 값이면 항상 `.capsLock`으로 돌아간다. rawValue는 UserDefaults에 저장되는 계약이라
/// 케이스 이름을 바꾸지 않는다.
enum TransitionKey: String, CaseIterable, Hashable {
    case capsLock = "capsLock"
    case rightCommand = "rightCommand"

    /// HID usage page 0x07 + usage. Remap이 F19 매핑을 만들 때 사용하는 값.
    var hidUsage: UInt64 {
        switch self {
        case .capsLock: return 0x700000039
        case .rightCommand: return 0x7000000E7
        }
    }

    /// 메뉴/접근성 표면에서 사용할 짧은 이름.
    var menuTitle: String {
        switch self {
        case .capsLock: return "Caps Lock"
        case .rightCommand: return "Right Command"
        }
    }

    /// 전환 키 메뉴 "영문 대문자 잠금" 줄의 단축키 표기 — 이 키를 고르면 어떤 조합이
    /// 잠금을 여는지. 시스템 메뉴의 단축키 필드 문법(⌘Q 식)을 따른다.
    var lockKeyGlyphs: String {
        switch self {
        case .capsLock: return "⇧⇪"
        case .rightCommand: return "⇪"
        }
    }
}

/// 전환 키와 따로 켜고 끄는 기능 키 배선(ADR-0008). 모드가 아니라 옵션이라 전환 키 라디오와
/// 섞지 않는다. 앱이 소유하는 배선 = 모드 배선 ∪ 켜진 옵션 배선 — Remap이 한 번의 set으로 건다.
/// rawValue는 UserDefaults 계약이라 케이스 이름을 바꾸지 않는다.
enum ExtraKey: String, CaseIterable, Hashable {
    /// 🎤(F5 자리) → F18. hidutil 배선만 — 앱은 소비하지 않는다.
    case dictation = "dictation"
    /// 🔍(F4 자리) → F17. Router가 F17을 소비하고 ⌃⌥A를 합성한다.
    case search = "search"

    /// 내장 키보드가 보내는 HID usage. fn 표(ioreg FnFunctionUsageMap)가 F5/F4 자리를
    /// Consumer 0xCF(Voice Command) / 0x221(AC Search)로 바꿔 보낸다.
    var srcUsage: UInt64 {
        switch self {
        case .dictation: return 0xC000000CF
        case .search: return 0xC00000221
        }
    }

    var dstUsage: UInt64 {
        switch self {
        case .dictation: return 0x70000006D  // F18
        case .search: return 0x70000006C     // F17
        }
    }

    var menuTitle: String {
        switch self {
        case .dictation: return "🎤 → F18"
        case .search: return "🔍 → ⌃⌥A"
        }
    }
}

/// 켜 둔 옵션 중 실제로 걸 배선. Right Command 모드는 Caps→F18을 대문자 잠금 방아쇠로
/// 이미 소유해서(Router가 F18을 소비) 🎤→F18을 빼 거짓 토글을 막는다. 켜 둔 값은 남는다.
enum ExtraWiring {
    static func effective(enabled: Set<ExtraKey>, mode: TransitionKey) -> Set<ExtraKey> {
        mode == .rightCommand ? enabled.subtracting([.dictation]) : enabled
    }
}

/// 입력 변형(synthetic Shift)과 표시(blink)의 판정을 한 곳에서 정의한다.
/// 대문자 잠금은 두 모드 모두 앱 소유 합성 Shift Lock 하나다 — native Caps는 존재하지
/// 않는다(두 모드 다 Caps 키를 hidutil로 떼어내 시스템 alpha-shift가 켜질 일이 없다).
/// 모드가 바꾸는 건 방아쇠뿐: Caps Lock 모드 = Shift+F19, Right Command 모드 = F18.
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

/// 사용자 설정 (UserDefaults). 매핑은 공통, 사용 토글만 LED 별 분리.
enum Settings {
    private static let ledInvertedKey = "\(bundleID).ledInverted"
    private static let menuBarLEDEnabledKey = "\(bundleID).menuBarLEDEnabled"
    private static let capsLockLEDEnabledKey = "\(bundleID).capsLockLEDEnabled"
    private static let showInputSourceKey = "\(bundleID).showInputSource"
    private static let hasAskedAboutLoginItemKey = "\(bundleID).hasAskedAboutLoginItem"
    private static let hasShownPermissionAlertKey = "\(bundleID).hasShownPermissionAlert"
    private static let ledOpenAlertSuppressedKey = "\(bundleID).ledOpenAlertSuppressed"
    /// 한영 전환용 물리 키. 미존재/알 수 없는 값은 Caps Lock 기본값.
    private static let transitionKeyKey = "\(bundleID).transitionKey"
    /// 마지막으로 tinyGreen이 hidutil에 소유권을 기록한 키. 크래시 뒤 다음 시작에서
    /// 예전 키 하나만 안전하게 치우기 위한 메타데이터이며, 사용자 선택값과는 별개다.
    /// registerDefaults에 등록하지 않아 부재(nil)와 Caps 기본값을 구분한다.
    private static let appliedTransitionKeyKey = "\(bundleID).appliedTransitionKey"
    /// 충돌 시 우리가 밀어낸 사용자의 Caps Lock 매핑 dst (HID usage).
    /// src 는 정의상 항상 Caps Lock (0x700000039) 이므로 dst 만 보관.
    /// 부재(nil) = stash 없음. **registerDefaults 에 default 등록 금지** — 등록하면
    /// "stash 없음"과 구분 불가. object(forKey:) nil 체크로만 판정.
    /// Remap.apply 충돌 시 set, revert/cleanup 복원 후 clear.
    private static let stashedCapsDstKey = "\(bundleID).stashedCapsDst"
    /// Right Command 충돌 stash. Caps용 기존 키는 그대로 유지해 구버전 stash를 읽는다.
    private static let stashedRightCommandDstKey = "\(bundleID).stashedRightCommandDst"
    /// 마지막으로 tinyGreen이 hidutil에 건 옵션 배선 집합. appliedTransitionKey와 같은 이유로
    /// 기본값을 등록하지 않는다 — 부재(nil) = 기록 없음.
    private static let appliedExtrasKey = "\(bundleID).appliedExtras"

    private static func extraEnabledKey(_ key: ExtraKey) -> String { "\(bundleID).extra.\(key.rawValue)" }
    /// 옵션별 충돌 stash. 모드 stash처럼 부재 = stash 없음이라 기본값을 등록하지 않는다.
    private static func stashedExtraDstKey(_ key: ExtraKey) -> String { "\(bundleID).stashedExtraDst.\(key.rawValue)" }

    /// 앱 시작 시 한 번 호출 — 키 미존재 시 기본값을 register.
    /// 이미 저장된 사용자 값은 덮어쓰지 않음.
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            ledInvertedKey: true,
            menuBarLEDEnabledKey: true,
            capsLockLEDEnabledKey: true,
            showInputSourceKey: false,
            hasAskedAboutLoginItemKey: false,
            hasShownPermissionAlertKey: false,
            ledOpenAlertSuppressedKey: false,
            transitionKeyKey: TransitionKey.capsLock.rawValue,
            // 배포본 기본 꺼짐 — 받는 쪽엔 F18·⌃⌥A를 받을 도구가 없다(ADR-0008).
            extraEnabledKey(.dictation): false,
            extraEnabledKey(.search): false
        ])
    }

    static func extraEnabled(_ key: ExtraKey) -> Bool {
        UserDefaults.standard.bool(forKey: extraEnabledKey(key))
    }

    static func setExtraEnabled(_ key: ExtraKey, _ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: extraEnabledKey(key))
    }

    /// 사용자가 켜 둔 옵션 전부 (모드에 따른 실효는 ExtraWiring.effective).
    static var enabledExtras: Set<ExtraKey> {
        Set(ExtraKey.allCases.filter { extraEnabled($0) })
    }

    /// 마지막으로 실제 적용에 성공한 옵션 배선. 크래시 뒤 stale 매핑의 소유자를 식별한다.
    static var appliedExtras: Set<ExtraKey>? {
        get {
            guard let raws = UserDefaults.standard.stringArray(forKey: appliedExtrasKey) else { return nil }
            return Set(raws.compactMap(ExtraKey.init(rawValue:)))
        }
        set {
            if let keys = newValue {
                UserDefaults.standard.set(keys.map(\.rawValue).sorted(), forKey: appliedExtrasKey)
            } else {
                UserDefaults.standard.removeObject(forKey: appliedExtrasKey)
            }
        }
    }

    static func stashedDst(forExtra key: ExtraKey) -> UInt64? {
        UserDefaults.standard.string(forKey: stashedExtraDstKey(key)).flatMap { UInt64($0) }
    }

    static func setStashedDst(_ value: UInt64?, forExtra key: ExtraKey) {
        if let value {
            UserDefaults.standard.set(String(value), forKey: stashedExtraDstKey(key))
        } else {
            UserDefaults.standard.removeObject(forKey: stashedExtraDstKey(key))
        }
    }

    /// 현재 사용자가 고른 전환 키. 기존 사용자와 손상된 설정은 Caps Lock으로 유지한다.
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

    /// 마지막으로 실제 적용에 성공한 키. 앱 크래시 뒤 stale mapping의 소유자를 식별한다.
    /// 설정 선택값과 달리 기본값을 등록하지 않는다.
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

    /// 메뉴바 도트 오른쪽에 한/A 박스 합성 표시. default false.
    static var showInputSource: Bool {
        get { UserDefaults.standard.bool(forKey: showInputSourceKey) }
        set { UserDefaults.standard.set(newValue, forKey: showInputSourceKey) }
    }

    /// 충돌 시 밀어낸 사용자 Caps 매핑 dst. nil = stash 없음.
    /// OpenStep plist 교훈대로 String 저장 + UInt64(_:) 파싱 (Remap 와 일관).
    /// set nil → 키 제거 (부재 = stash 없음 불변식 유지).
    static var stashedCapsDst: UInt64? {
        get { stashedDst(for: .capsLock) }
        set { setStashedDst(newValue, for: .capsLock) }
    }

    /// 선택 키별 stash 접근. Caps는 기존 `stashedCapsDst` 키를 그대로 읽어 migration 호환.
    /// Right Command는 별도 슬롯 — 키를 바꿔도 두 사용자의 매핑을 서로 덮지 않는다.
    static func stashedDst(for key: TransitionKey) -> UInt64? {
        let storageKey = key == .capsLock ? stashedCapsDstKey : stashedRightCommandDstKey
        if let string = UserDefaults.standard.string(forKey: storageKey) {
            return UInt64(string)
        }
        // 테스트/구버전의 NSNumber 저장도 안전하게 읽는다.
        if let number = UserDefaults.standard.object(forKey: storageKey) as? NSNumber {
            return number.uint64Value
        }
        return nil
    }

    /// nil은 키를 제거한다. set 성공 후에만 Remap이 호출해 원본 보존 불변식을 지킨다.
    static func setStashedDst(_ value: UInt64?, for key: TransitionKey) {
        let storageKey = key == .capsLock ? stashedCapsDstKey : stashedRightCommandDstKey
        if let value {
            UserDefaults.standard.set(String(value), forKey: storageKey)
        } else {
            UserDefaults.standard.removeObject(forKey: storageKey)
        }
    }

    /// LED 매핑 반전 (공통). default true (영어 활성 시 LED ON).
    static var ledInverted: Bool {
        get { UserDefaults.standard.bool(forKey: ledInvertedKey) }
        set { UserDefaults.standard.set(newValue, forKey: ledInvertedKey) }
    }

    /// 메뉴바 도트 표시 ON/OFF. default true.
    static var menuBarLEDEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: menuBarLEDEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: menuBarLEDEnabledKey) }
    }

    /// 키보드 Caps Lock LED 동작 ON/OFF. default true.
    static var capsLockLEDEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: capsLockLEDEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: capsLockLEDEnabledKey) }
    }

    /// 첫 실행 시 "로그인 시 열기" alert 표시 후 true 로. 다음 실행부터는 안 묻기.
    /// 사용자가 alert "예/아니오" 어느 쪽을 눌렀든 true 가 되어 재질문 안 함 (UX 압박 회피).
    /// default false (첫 실행 시 alert 떠야 함).
    static var hasAskedAboutLoginItem: Bool {
        get { UserDefaults.standard.bool(forKey: hasAskedAboutLoginItemKey) }
        set { UserDefaults.standard.set(newValue, forKey: hasAskedAboutLoginItemKey) }
    }

    /// 첫 실행 (권한 부족 시) 모달 alert 표시 후 true 로. 다음 실행부터는 안 띄움.
    /// 권한 부족 자체는 메뉴바 빨간 도트 + 에러 항목으로 계속 안내 — 사용자가
    /// 메뉴바 도트 클릭 → 에러 항목 클릭 시 부족한 권한 페이지로 이동 (F6).
    /// default false.
    static var hasShownPermissionAlert: Bool {
        get { UserDefaults.standard.bool(forKey: hasShownPermissionAlertKey) }
        set { UserDefaults.standard.set(newValue, forKey: hasShownPermissionAlertKey) }
    }

    /// F5 (LED 연결 실패) alert 의 "이 메시지 다시 보지 않음" 체크. true 면 다음 실행부터
    /// alert 자동 표시 X + errorState (메뉴바 주황 도트 + errorItem) 표시 자체 X.
    /// 외장 키보드 사용자 (LED 제어 미지원이 자연 원인) 가 영구 경고 노이즈 안 보게.
    /// default false.
    static var ledOpenAlertSuppressed: Bool {
        get { UserDefaults.standard.bool(forKey: ledOpenAlertSuppressedKey) }
        set { UserDefaults.standard.set(newValue, forKey: ledOpenAlertSuppressedKey) }
    }

    /// 매핑은 두 LED 공통(ledInverted) — enabled 게이트만 표면마다 다르다.
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
