import Foundation
import os

private let log = Logger.tinyGreen("Remap")

/// 시스템 레벨 전환 키 → F19 매핑 + 옵션 기능 키 배선(ADR-0008). `hidutil property --set` CLI 사용.
///
/// **사용자 매핑 보존 원칙**: hidutil 의 UserKeyMapping 은 array 통째로 set 하는 구조라,
/// 단순 `--set` 으로 우리 매핑만 박으면 사용자의 다른 매핑이 영구 손실.
/// `apply()` / `revert()` 는 현재 array 를 fetch → 우리 매핑만 add/remove → re-set 으로 다른 매핑 보존.
///
/// **충돌 처리 (무음 stash/복원)**: 사용자가 선택한 전환 키를 다른 키로 매핑한 상태면
/// `apply` 가 다이얼로그 없이 그 dst 를 선택 키별 stash에 보관한 뒤 우리 매핑으로 교체한다.
/// `revert()` 가 우리 매핑 제거 후 해당 stash를 복원한다
/// (슬롯이 비어있을 때만 — 사용자가 그새 새 매핑을 만들면 그걸 덮지 않고 stash 폐기).
/// 동의 모달이 사주는 값이 거의 없음 (Caps 리매퍼를 깐 시점에 동의 내포) + 복원이
/// 실제 안전장치 — 그래서 모달 제거. 복원 트리거: 정상종료(teardown/SignalGuard) +
/// 크래시 후 다음 시작 (apply() 의 옛 잔존 정리).
enum Remap {
    /// HID Usage Page 0x07 (Keyboard) + Usage 0x6E (F19).
    private static let f19HIDUsage: UInt64 = 0x70000006E
    /// Usage 0x6D (F18) — Right Command 모드에서 Caps Lock이 향하는 앱 전용 신호.
    /// F19(한영)와 다른 키여야 Router가 물리 키를 구분한다. 대문자 잠금은 이 신호를
    /// 받은 앱이 합성 Shift Lock으로 처리한다 — 시스템 alpha-shift는 관여하지 않는다.
    private static let f18HIDUsage: UInt64 = 0x70000006D

    private static let srcKey = "HIDKeyboardModifierMappingSrc"
    private static let dstKey = "HIDKeyboardModifierMappingDst"

    /// 흔한 HID usage 의 사람 이름. 모르면 hex.
    private static let knownKeys: [UInt64: String] = [
        0x700000029: "Esc",
        0x70000003A: "F1",  0x70000003B: "F2",  0x70000003C: "F3",  0x70000003D: "F4",
        0x70000003E: "F5",  0x70000003F: "F6",  0x700000040: "F7",  0x700000041: "F8",
        0x700000042: "F9",  0x700000043: "F10", 0x700000044: "F11", 0x700000045: "F12",
        0x700000068: "F13", 0x700000069: "F14", 0x70000006A: "F15", 0x70000006B: "F16",
        0x70000006C: "F17", 0x70000006D: "F18", 0x70000006E: "F19", 0x70000006F: "F20",
        0x7000000E0: "Left Control",
        0x7000000E1: "Left Shift",
        0x7000000E2: "Left Option",
        0x7000000E3: "Left Command",
        0x7000000E4: "Right Control",
        0x7000000E5: "Right Shift",
        0x7000000E6: "Right Option",
        0x7000000E7: "Right Command",
        0xC000000CF: "🎤 (Voice Command)",
        0xC00000221: "🔍 (AC Search)",
    ]

    /// HID usage code → 사람 이름 또는 hex.
    static func keyName(_ usage: UInt64) -> String {
        if let name = knownKeys[usage] { return name }
        return String(format: "0x%llX", usage)
    }

    /// 우리가 이번 process에서 매핑을 박았는지. false면 revert가 같은 목적지의
    /// 사용자/시스템 매핑을 추측해 지우지 않는다.
    private static var didAddOurMapping = false
    /// 현재 process에서 소유한 물리 키. UserDefaults의 appliedTransitionKey는 크래시 뒤
    /// stale 매핑을 다음 시작에서 한 번 정리할 때만 사용한다.
    private static var ownedTransitionKey: TransitionKey?
    /// 현재 process에서 소유한 옵션 배선. 디스크의 appliedExtras는 크래시 뒤 정리용.
    private static var ownedExtras: Set<ExtraKey> = []

    /// 모드가 소유하는 (물리 키 → 목적지) 배선. 물리 키의 신원은 TransitionKey로 표현한다
    /// (stash 키와 동일 축). Caps Lock 모드 = Caps→F19 하나. Right Command 모드 =
    /// RCmd→F19(한영) + Caps→F18(대문자 잠금) 둘 — Caps를 시스템에 남기지 않는다.
    static func ownedPairs(for mode: TransitionKey) -> [(source: TransitionKey, dst: UInt64)] {
        switch mode {
        case .capsLock: return [(.capsLock, f19HIDUsage)]
        case .rightCommand: return [(.rightCommand, f19HIDUsage), (.capsLock, f18HIDUsage)]
        }
    }

    /// 테스트/UI가 같은 매핑 계약을 공유할 수 있도록 순수 값으로 노출.
    static func mappings(for mode: TransitionKey) -> [[String: UInt64]] {
        ownedPairs(for: mode).map { [srcKey: $0.source.hidUsage, dstKey: $0.dst] }
    }

    /// 주어진 매핑이 특정 모드의 tinyGreen 매핑인지.
    static func isOurMapping(_ map: [String: UInt64], for mode: TransitionKey) -> Bool {
        ownedPairs(for: mode).contains { map[srcKey] == $0.source.hidUsage && map[dstKey] == $0.dst }
    }

    /// 옵션 배선의 매핑. 순서는 ExtraKey.allCases를 따라 같은 집합이면 같은 배열이 된다.
    static func mappings(for extras: Set<ExtraKey>) -> [[String: UInt64]] {
        ExtraKey.allCases.filter(extras.contains).map { [srcKey: $0.srcUsage, dstKey: $0.dstUsage] }
    }

    static func isOurMapping(_ map: [String: UInt64], forExtra key: ExtraKey) -> Bool {
        map[srcKey] == key.srcUsage && map[dstKey] == key.dstUsage
    }

    /// 현재 설정 키와 켜 둔 옵션에 매핑 적용. 사용자의 다른 매핑은 보존한다.
    static func apply() -> Bool {
        let mode = Settings.transitionKey
        return apply(for: mode, extras: ExtraWiring.effective(enabled: Settings.enabledExtras, mode: mode))
    }

    /// 메뉴에서 전환 키를 바꿀 때 호출하는 안전한 재배선.
    /// 성공해야만 새 키를 소유하고, 실패하면 기존 매핑/설정 메타데이터를 건드리지 않는다.
    /// 호출자는 성공 반환 뒤 `Settings.transitionKey`를 저장한다.
    @discardableResult
    static func switchTransitionKey(to key: TransitionKey) -> Bool {
        apply(for: key, extras: ExtraWiring.effective(enabled: Settings.enabledExtras, mode: key))
    }

    /// 메뉴에서 옵션을 켜고 끌 때의 재배선. 모드 배선은 그대로 두고 같은 apply 길을 탄다.
    /// 호출자는 성공 반환 뒤 Settings에 켜짐 값을 저장한다.
    @discardableResult
    static func switchExtras(to enabled: Set<ExtraKey>) -> Bool {
        let mode = ownedTransitionKey ?? Settings.transitionKey
        return apply(for: mode, extras: ExtraWiring.effective(enabled: enabled, mode: mode))
    }

    /// 조회 → 이전 소유 매핑 제거/원본 복원 → 새 충돌 stash → 새 매핑 추가를 한 번의
    /// hidutil set으로 수행한다. 중간 상태를 외부에 노출하지 않아 키 전환 중에도 안전하다.
    private static func apply(for selected: TransitionKey, extras selectedExtras: Set<ExtraKey>) -> Bool {
        guard var mappings = currentMappingArray() else {
            log.error("apply: 매핑 조회 실패 — abort (사용자 매핑 보호)")
            return false
        }
        log.info("apply: \(selected.menuTitle, privacy: .public) 시작 — 현재 array size \(mappings.count, privacy: .public)")

        // 이전 process가 소유했던 키를 우선 확인한다. 구버전에는 persisted owner가 없지만
        // Caps→F19 또는 Caps stash는 구버전 tinyGreen의 흔적이므로 Caps만 migration으로
        // 인정한다. Right Command의 동일 매핑은 사용자 소유일 수 있어 stash 후 보존한다.
        let previousOwner = ownedTransitionKey
            ?? Settings.appliedTransitionKey
            ?? legacyCapsOwner(in: mappings)
        var stashToClear = Set<TransitionKey>()

        let newSources = Set(ownedPairs(for: selected).map(\.source))

        if let previousOwner {
            mappings.removeAll { isOurMapping($0, for: previousOwner) }

            // 이전 모드만 쓰던 물리 키의 원본을 복구한다. 새 모드도 쓰는 키(예: Caps)는
            // stash를 그대로 이월한다. 사용자가 그 사이 새 매핑을 넣었으면 덮지 않고 폐기.
            for released in ownedPairs(for: previousOwner).map(\.source) where !newSources.contains(released) {
                guard let stashed = Settings.stashedDst(for: released) else { continue }
                if mappings.contains(where: { $0[srcKey] == released.hidUsage }) {
                    log.notice("apply: 이전 \(released.menuTitle, privacy: .public) 슬롯에 새 사용자 매핑 — stash 폐기")
                } else {
                    mappings.append([srcKey: released.hidUsage, dstKey: stashed])
                    log.notice("apply: 이전 \(released.menuTitle, privacy: .public) 매핑 복원 dst=\(keyName(stashed), privacy: .public)")
                }
                stashToClear.insert(released)
            }
        }

        // 새 모드가 소유할 각 물리 키의 기존 mapping은 사용자 충돌이다. 같은 process/이전
        // owner의 exact mapping은 위에서 제거됐으므로 여기서는 사용자 값만 stash한다.
        var pendingStashes: [TransitionKey: UInt64] = [:]
        for source in ownedPairs(for: selected).map(\.source) {
            let conflicts = mappings.filter { $0[srcKey] == source.hidUsage }
            if conflicts.count > 1 {
                // 같은 src가 여러 개면 단일 stash로 모든 사용자 의도를 표현할 수 없다. 배열을
                // 건드리지 않고 abort하는 편이 조용한 손실보다 안전하다.
                log.error("apply: \(source.menuTitle, privacy: .public) 슬롯에 중복 사용자 매핑 — abort (원본 보호)")
                return false
            }
            if let conflict = conflicts.first {
                guard let dst = conflict[dstKey], dst != 0 else {
                    log.error("apply: \(source.menuTitle, privacy: .public) 충돌 dst 없음 — abort (원본 보호)")
                    return false
                }
                pendingStashes[source] = dst
                mappings.removeAll { $0[srcKey] == source.hidUsage }
                log.notice("apply: \(source.menuTitle, privacy: .public)→\(keyName(dst), privacy: .public) 충돌 — stash 후 교체")
            }
        }

        mappings.append(contentsOf: Self.mappings(for: selected))

        let previousExtras = didAddOurMapping ? ownedExtras : (Settings.appliedExtras ?? [])
        guard let extraPlan = planExtras(&mappings, previous: previousExtras, selected: selectedExtras,
                                         stashed: Settings.stashedDst(forExtra:)) else {
            return false
        }

        let ok = setMappings(mappings)
        if ok {
            didAddOurMapping = true
            ownedTransitionKey = selected
            Settings.appliedTransitionKey = selected
            ownedExtras = selectedExtras
            Settings.appliedExtras = selectedExtras
            for key in extraPlan.stashToClear {
                Settings.setStashedDst(nil, forExtra: key)
            }
            for (key, dst) in extraPlan.pendingStashes {
                Settings.setStashedDst(dst, forExtra: key)
            }
            for oldKey in stashToClear {
                Settings.setStashedDst(nil, for: oldKey)
            }
            for (source, pendingStash) in pendingStashes {
                if let old = Settings.stashedDst(for: source), old != pendingStash {
                    log.notice("apply: 기존 \(source.menuTitle, privacy: .public) stash dst=\(keyName(old), privacy: .public) → \(keyName(pendingStash), privacy: .public) 덮어씀")
                }
                Settings.setStashedDst(pendingStash, for: source)
            }
            log.info("apply: \(selected.menuTitle, privacy: .public) 모드 배선 완료 (\(self.ownedPairs(for: selected).count, privacy: .public)개) + 옵션 \(selectedExtras.count, privacy: .public)개, didAddOurMapping=true")
        } else {
            log.error("apply: setMappings 실패")
        }
        return ok
    }

    struct ExtraPlan: Equatable {
        var stashToClear: Set<ExtraKey> = []
        var pendingStashes: [ExtraKey: UInt64] = [:]
    }

    /// 옵션 배선 계획 — 모드 쪽 apply와 같은 길(이전 소유분 제거·원본 복원 → 충돌 stash → 추가)을
    /// `mappings` 위에서 밟는다. hidutil·UserDefaults를 만지지 않는 순수 함수라 테스트가 직접 부른다.
    /// nil = abort (배열을 쓰지 말 것).
    ///
    /// **인수 규칙(옵션에만)**: 새로 소유할 Src에 우리와 똑같은 dst의 매핑이 이미 있으면 사용자
    /// 충돌로 stash하지 않고 넘겨받는다 — robots launchd가 걸어 둔 🎤→F18을 옮겨올 때, stash하면
    /// robots를 걷은 뒤에도 tinyGreen 종료마다 그 매핑이 되살아나 주인 없는 고아가 된다.
    /// 모드 배선은 지금처럼 인수하지 않는다(위 apply의 Right Command 주석).
    static func planExtras(
        _ mappings: inout [[String: UInt64]],
        previous: Set<ExtraKey>,
        selected: Set<ExtraKey>,
        stashed: (ExtraKey) -> UInt64?
    ) -> ExtraPlan? {
        var plan = ExtraPlan()
        mappings.removeAll { map in previous.contains { isOurMapping(map, forExtra: $0) } }

        for released in ExtraKey.allCases where previous.contains(released) && !selected.contains(released) {
            guard let dst = stashed(released) else { continue }
            if mappings.contains(where: { $0[srcKey] == released.srcUsage }) {
                log.notice("apply: 이전 \(released.rawValue, privacy: .public) 슬롯에 새 사용자 매핑 — stash 폐기")
            } else {
                mappings.append([srcKey: released.srcUsage, dstKey: dst])
                log.notice("apply: 이전 \(released.rawValue, privacy: .public) 매핑 복원 dst=\(keyName(dst), privacy: .public)")
            }
            plan.stashToClear.insert(released)
        }

        for key in ExtraKey.allCases where selected.contains(key) {
            let conflicts = mappings.filter { $0[srcKey] == key.srcUsage }
            if conflicts.count > 1 {
                log.error("apply: \(key.rawValue, privacy: .public) 슬롯에 중복 사용자 매핑 — abort (원본 보호)")
                return nil
            }
            guard let conflict = conflicts.first else { continue }
            guard let dst = conflict[dstKey], dst != 0 else {
                log.error("apply: \(key.rawValue, privacy: .public) 충돌 dst 없음 — abort (원본 보호)")
                return nil
            }
            mappings.removeAll { $0[srcKey] == key.srcUsage }
            if dst == key.dstUsage {
                log.notice("apply: \(key.rawValue, privacy: .public) 같은 매핑이 이미 있음 — 인수")
            } else {
                plan.pendingStashes[key] = dst
                log.notice("apply: \(key.rawValue, privacy: .public)→\(keyName(dst), privacy: .public) 충돌 — stash 후 교체")
            }
        }

        mappings.append(contentsOf: Self.mappings(for: selected))
        return plan
    }

    /// 우리 매핑만 제거. 사용자의 다른 매핑은 보존.
    /// **didAddOurMapping=false 면 제거 skip** — 다른 프로세스/시스템 매핑을 우리 거로
    /// 오인해 삭제하지 않는다. stale 매핑은 다음 apply()가 persisted owner로 정리한다.
    @discardableResult
    static func revert() -> Bool {
        guard didAddOurMapping else {
            log.info("revert: didAddOurMapping=false — 우리가 안 박은 매핑이라 제거 skip (시스템 매핑 보존)")
            return true
        }
        guard let owned = ownedTransitionKey else {
            didAddOurMapping = false
            return true
        }
        let ok = removeOurMappings(for: owned, extras: ownedExtras, logPrefix: "revert")
        if ok {
            didAddOurMapping = false
            ownedTransitionKey = nil
            Settings.appliedTransitionKey = nil
            ownedExtras = []
            Settings.appliedExtras = nil
        }
        return ok
    }

    /// 디버그용 — 현재 매핑 raw 출력.
    static func currentMapping() -> String? {
        return runHidutil(args: ["property", "--get", "UserKeyMapping"])
    }

    /// 현재 array 에서 우리 매핑만 filter out 후 set. revert() 의 핵심 로직.
    /// **조회 실패 abort 이유** — 빈 array 로 오인하면 사용자 매핑 전체 덮어쓰기 위험.
    /// revert() 가 false 받으면 매핑 잔존 가능성 — 다음 시작 시 apply() 가 정리.
    /// - Parameter logPrefix: 호출자 구분용 log 메시지 prefix.
    /// - Returns: 성공 (true). 조회 실패 / setMappings 실패 (false).
    private static func removeOurMappings(for owned: TransitionKey, extras: Set<ExtraKey>, logPrefix: String) -> Bool {
        guard var mappings = currentMappingArray() else {
            log.error("\(logPrefix, privacy: .public): 매핑 조회 실패 — abort (사용자 매핑 보호)")
            return false
        }
        let before = mappings
        mappings.removeAll(where: { isOurMapping($0, for: owned) })

        // stash 복원 — 우리 매핑 제거 후 각 물리 키 슬롯이 비었을 때만 사용자 원본 재추가.
        // 사용자가 그새 새 매핑을 했으면 그걸 덮지 않고 stash 폐기 (틀린 복원 < 안 함).
        // 우리 매핑이 휘발(재부팅)로 이미 사라진 케이스도 before==mappings 이지만 stash
        // append 로 변경 발생 → setMappings 가 복원 수행 (no-op 조기반환에 안 걸림).
        // 복원이 setMappings 로 영속되기 *전엔* stash 를 clear 하지 않음 — set 실패 시
        // 사용자 원본 영구 유실 방지 (review #2 반영). 폐기 케이스는 디스크에 아무것도
        // 안 쓰므로 즉시 clear 안전.
        var stashesRestored = Set<TransitionKey>()   // append 함 → setMappings 성공 후에만 clear
        var stashesDiscarded = Set<TransitionKey>()
        for source in ownedPairs(for: owned).map(\.source) {
            guard let stashed = Settings.stashedDst(for: source) else { continue }
            if mappings.contains(where: { $0[srcKey] == source.hidUsage }) {
                log.notice("\(logPrefix, privacy: .public): 사용자가 \(source.menuTitle, privacy: .public) 새 매핑 보유 — 복원 skip, stash 폐기")
                stashesDiscarded.insert(source)  // set 불필요한 폐기 path도 아래에서 clear
            } else {
                mappings.append([srcKey: source.hidUsage, dstKey: stashed])
                stashesRestored.insert(source)
                log.notice("\(logPrefix, privacy: .public): 사용자 \(source.menuTitle, privacy: .public) 매핑 복원 dst=\(keyName(stashed), privacy: .public)")
            }
        }

        // 옵션 배선도 같은 규칙으로 걷는다 — 옵션 전부를 놓는 계획(selected = [])과 같다.
        guard let extraPlan = planExtras(&mappings, previous: extras, selected: [],
                                         stashed: Settings.stashedDst(forExtra:)) else {
            return false
        }

        if mappings == before {
            for source in stashesDiscarded { Settings.setStashedDst(nil, for: source) }
            for key in extraPlan.stashToClear { Settings.setStashedDst(nil, forExtra: key) }
            log.info("\(logPrefix, privacy: .public): 변경 없음 — no-op")
            return true
        }
        let ok = setMappings(mappings)
        if ok {
            for source in stashesRestored.union(stashesDiscarded) {  // 영속 확정 후 clear
                Settings.setStashedDst(nil, for: source)
            }
            for key in extraPlan.stashToClear { Settings.setStashedDst(nil, forExtra: key) }
            log.info("\(logPrefix, privacy: .public): 정리/복원 완료 (\(before.count, privacy: .public) → \(mappings.count, privacy: .public))")
        } else {
            log.error("\(logPrefix, privacy: .public): setMappings 실패 — stash 보존(다음 시도 복원)")
        }
        return ok
    }

    /// 구버전(2.0.1 이전)에 persisted owner가 없을 때의 Caps stash/매핑 migration.
    /// Right Command의 동일 mapping은 사용자 설정일 수 있어 여기서 소유로 추측하지 않는다.
    private static func legacyCapsOwner(in mappings: [[String: UInt64]]) -> TransitionKey? {
        if Settings.stashedCapsDst != nil || mappings.contains(where: { isOurMapping($0, for: .capsLock) }) {
            return .capsLock
        }
        return nil
    }

    /// `hidutil property --get UserKeyMapping` 결과 (OpenStep plist) 를 array 로 parse.
    ///
    /// **반환값**:
    /// - `[]` — 진짜 빈 매핑 (사용자 hidutil 안 쓴 깨끗한 상태). 정상 path.
    /// - `nil` — 실패 (subprocess fail, plist parse 실패, cast 실패). 호출자가 abort 해야.
    ///   *빈 array 와 실패를 분간 안 하면* 일시 fail 시 우리가 빈 array 로 잘못 인식 → apply 가
    ///   사용자 매핑 전체 덮어쓰기 위험. 코덱스 review 에서 짚힌 P1.
    ///
    /// **OpenStep plist 의 함정**: 모든 scalar value 를 *string* 으로 표현 (예: "30064771182").
    /// PropertyListSerialization 가 number 를 NSNumber 가 아닌 NSCFString 으로 parse —
    /// `as? NSNumber` 만 시도하면 항상 nil → array 가 빈 채로 인식됨. `as? String + UInt64(_:)`
    /// 우선, XML/binary plist (미래 호환) 는 NSNumber fallback.
    private static func currentMappingArray() -> [[String: UInt64]]? {
        guard let output = runHidutil(args: ["property", "--get", "UserKeyMapping"]) else {
            log.error("currentMappingArray: hidutil --get 실패")
            return nil
        }
        return parseMappings(output)
    }

    /// hidutil 출력 문자열 → 매핑 array. subprocess 없는 순수 함수 — 유닛 테스트가
    /// "(null)"·OpenStep string 함정·macOS 27 표 형식 회귀를 잡는다 (internal 은 그 접근용).
    ///
    /// **macOS 27 (2026-09-17 실측)**: `--get` 이 단일 plist 대신 서비스별 표를 낸다.
    /// ```
    /// RegistryID  Key                   Value
    /// 1000008dd   UserKeyMapping   (null)
    /// 100000ad1   UserKeyMapping   (
    ///         { HIDKeyboardModifierMappingDst = 30064771182; ... }
    /// )
    /// ```
    /// `--set` 은 여전히 전역이라(모든 서비스에 같은 값이 들어감 — 실측) 쓰기 경로는 그대로.
    /// 읽기는 행마다 값을 parse 해 합의를 구한다 — (null) 행은 "이 서비스엔 아직 안 퍼진 값"으로
    /// 무시하되, 값이 있는 행끼리 다르면 장치별 매핑이 있는 것이므로 abort (전역 re-set 이 덮는다).
    static func parseMappings(_ output: String) -> [[String: UInt64]]? {
        if let rows = tableRows(output) {
            guard !rows.isEmpty else {
                log.error("parseMappings: 표에 행 없음 — abort (사용자 매핑 보호)")
                return nil
            }
            var consensus: [[String: UInt64]]? = nil
            for row in rows {
                guard let parsed = parseSingle(row) else { return nil }
                if parsed.isEmpty { continue }
                if let seen = consensus, seen != parsed {
                    log.error("parseMappings: 서비스별 UserKeyMapping 불일치 — abort (사용자 매핑 보호)")
                    return nil
                }
                consensus = parsed
            }
            return consensus ?? []
        }
        return parseSingle(output)
    }

    /// macOS 27 표 형식이면 행별 Value 문자열 목록, 아니면 nil (단일 plist 형식).
    /// 행 시작 = 들여쓰기 없는 `<hex RegistryID> UserKeyMapping <value...>`; 그 외 줄은 직전 행의 이어짐.
    private static func tableRows(_ output: String) -> [String]? {
        let lines = output.components(separatedBy: .newlines)
        guard let header = lines.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
              header.hasPrefix("RegistryID") else {
            return nil
        }
        var rows: [String] = []
        var current: String? = nil
        for line in lines {
            if line == header { continue }
            if let value = rowStart(line) {
                if let done = current { rows.append(done) }
                current = value
            } else if current != nil {
                current! += "\n" + line
            }
        }
        if let done = current { rows.append(done) }
        return rows
    }

    /// `1000008dd   UserKeyMapping   (null)` 꼴이면 Value 부분을 돌려준다.
    private static func rowStart(_ line: String) -> String? {
        guard let first = line.first, !first.isWhitespace else { return nil }
        let parts = line.split(maxSplits: 2, omittingEmptySubsequences: true, whereSeparator: { $0 == " " || $0 == "\t" })
        guard parts.count >= 2,
              parts[0].allSatisfy({ $0.isHexDigit }),
              parts[1] == "UserKeyMapping" else {
            return nil
        }
        return parts.count == 3 ? String(parts[2]) : ""
    }

    /// 단일 plist 문자열(macOS 26 이하 전체 출력, 또는 27 표의 한 행 Value) → 매핑 array.
    private static func parseSingle(_ output: String) -> [[String: UInt64]]? {
        // 깨끗한 사용자 (UserKeyMapping 한 번도 set 안 함) — hidutil 출력 = "(null)".
        // macOS Tahoe (26) 부터 확인. 빈 매핑 자체를 실패로 분류하면 *모든 새 사용자* apply
        // abort → critical bug (v1.0.1 fix). trim 후 매칭으로 *진짜 빈 매핑* 정상 처리.
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "(null)" {
            return []
        }

        guard let data = output.data(using: .utf8) else {
            log.error("parseMappings: utf8 변환 실패")
            return nil
        }
        do {
            let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            // NSNull 도 빈 매핑 (PropertyListSerialization 가 null 자체를 NSNull 로 parse 하는 경우).
            if plist is NSNull {
                return []
            }
            guard let array = plist as? [[String: Any]] else {
                log.error("parseMappings: plist 가 array 형식 아님 — type: \(type(of: plist), privacy: .public)")
                return nil
            }
            // 값 하나라도 해석 못 하면 전체 실패(nil) — 이해 못 한 항목을 조용히 빠뜨린 채
            // apply 가 re-set 하면 그 항목이 소실된다 (미래 포맷 변화·제3자 항목 보호).
            var result: [[String: UInt64]] = []
            for dict in array {
                var r: [String: UInt64] = [:]
                for (k, v) in dict {
                    if let str = v as? String, let num = UInt64(str) {
                        r[k] = num
                    } else if let num = v as? NSNumber {
                        r[k] = num.uint64Value
                    } else {
                        log.error("parseMappings: 해석 불가 값 (key: \(k, privacy: .public)) — abort (사용자 매핑 보호)")
                        return nil
                    }
                }
                result.append(r)
            }
            return result
        } catch {
            log.error("UserKeyMapping plist parse 실패: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// `{"UserKeyMapping": [...]}` JSON 직렬화 후 `--set`.
    /// 빈 array 도 허용 (revert 시 우리 매핑이 마지막이었던 경우 = 실질 비움 = 시스템 default 복귀).
    private static func setMappings(_ mappings: [[String: UInt64]]) -> Bool {
        let dict: [String: Any] = ["UserKeyMapping": mappings]
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: []),
              let json = String(data: data, encoding: .utf8) else {
            log.error("UserKeyMapping JSON 직렬화 실패")
            return false
        }
        return runHidutil(args: ["property", "--set", json]) != nil
    }

    private static func runHidutil(args: [String]) -> String? {
        let task = Process()
        task.launchPath = "/usr/bin/hidutil"
        task.arguments = args
        let outPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            // 읽기 먼저, 기다리기 나중. --get 출력은 HID 서비스마다 매핑을 되풀이해서
            // (서비스 180개 × 3줄 ≈ 69KB) 파이프 버퍼 64KB를 넘는다. 거꾸로 하면 hidutil은 쓰기에서,
            // 우리는 waitUntilExit에서 서로를 기다리며 멈춘다.
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            if task.terminationStatus != 0 {
                log.error("hidutil non-zero exit: \(task.terminationStatus, privacy: .public)")
                return nil
            }
            return String(data: data, encoding: .utf8)
        } catch {
            log.error("hidutil 실행 실패: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
