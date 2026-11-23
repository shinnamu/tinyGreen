import XCTest
import CoreGraphics

// 호스트 앱 없음 — 대상 소스가 테스트 번들에 직접 컴파일되어 internal 그대로 접근
// (@testable import 불필요). 왜 호스트를 안 붙이는지는 project.yml 의 tinyGreenTests 주석.

// MARK: - TransitionKey / Remap mapping contract

final class TransitionKeyTests: XCTestCase {
    private let src = "HIDKeyboardModifierMappingSrc"
    private let dst = "HIDKeyboardModifierMappingDst"
    private let f19: UInt64 = 0x70000006E
    private let f18: UInt64 = 0x70000006D

    func testSupportedKeysHaveDistinctPhysicalUsages() {
        XCTAssertEqual(TransitionKey.capsLock.hidUsage, 0x700000039)
        XCTAssertEqual(TransitionKey.rightCommand.hidUsage, 0x7000000E7)
        XCTAssertNotEqual(TransitionKey.capsLock.hidUsage, TransitionKey.rightCommand.hidUsage)
    }

    /// 두 모드 다 Caps를 시스템에 남기지 않는다 — Caps Lock 모드는 Caps→F19 하나,
    /// Right Command 모드는 RCmd→F19 + Caps→F18 둘.
    func testEachModeOwnsItsFullWiring() {
        XCTAssertEqual(Remap.mappings(for: .capsLock), [
            [src: TransitionKey.capsLock.hidUsage, dst: f19]
        ])
        XCTAssertEqual(Remap.mappings(for: .rightCommand), [
            [src: TransitionKey.rightCommand.hidUsage, dst: f19],
            [src: TransitionKey.capsLock.hidUsage, dst: f18]
        ])
    }

    /// Caps→F19(Caps 모드 소유)와 Caps→F18(RCmd 모드 소유)은 서로의 것이 아니다 —
    /// 모드 전환 시 이전 모드 매핑만 정확히 걷어내는 계약.
    func testModesDoNotClaimEachOthersMappings() {
        let capsToF19: [String: UInt64] = [src: TransitionKey.capsLock.hidUsage, dst: f19]
        let capsToF18: [String: UInt64] = [src: TransitionKey.capsLock.hidUsage, dst: f18]
        let rcmdToF19: [String: UInt64] = [src: TransitionKey.rightCommand.hidUsage, dst: f19]
        XCTAssertTrue(Remap.isOurMapping(capsToF19, for: .capsLock))
        XCTAssertFalse(Remap.isOurMapping(capsToF19, for: .rightCommand))
        XCTAssertTrue(Remap.isOurMapping(capsToF18, for: .rightCommand))
        XCTAssertFalse(Remap.isOurMapping(capsToF18, for: .capsLock))
        XCTAssertTrue(Remap.isOurMapping(rcmdToF19, for: .rightCommand))
        XCTAssertFalse(Remap.isOurMapping(rcmdToF19, for: .capsLock))
    }

    /// 대문자 잠금은 모드 무관 단일 합성 Shift Lock — 주입 판정은 모드를 모른다.
    func testShiftInjectionIsModeAgnostic() {
        XCTAssertTrue(TransitionBehavior.shouldInjectShift(
            shiftLockActive: true, isKorean: false, isAlphabet: true, hasOtherModifier: false
        ))
        XCTAssertFalse(TransitionBehavior.shouldInjectShift(
            shiftLockActive: true, isKorean: true, isAlphabet: true, hasOtherModifier: false
        ))
        XCTAssertFalse(TransitionBehavior.shouldInjectShift(
            shiftLockActive: true, isKorean: false, isAlphabet: false, hasOtherModifier: false
        ))
        XCTAssertFalse(TransitionBehavior.shouldInjectShift(
            shiftLockActive: true, isKorean: false, isAlphabet: true, hasOtherModifier: true
        ))
        XCTAssertFalse(TransitionBehavior.shouldInjectShift(
            shiftLockActive: false, isKorean: false, isAlphabet: true, hasOtherModifier: false
        ))
    }

    /// 점멸도 같은 상태 하나에서 — 영문 + 잠금 활성일 때만.
    func testBlinkFollowsSyntheticLockOnly() {
        XCTAssertTrue(TransitionBehavior.shouldBlink(shiftLockActive: true, isKorean: false))
        XCTAssertFalse(TransitionBehavior.shouldBlink(shiftLockActive: true, isKorean: true))
        XCTAssertFalse(TransitionBehavior.shouldBlink(shiftLockActive: false, isKorean: false))
    }
}

// MARK: - Remap.parseMappings

/// hidutil 출력 파싱 회귀 방어. v1.0.1 크리티컬 버그 ("(null)" 을 실패로 오인 →
/// 모든 새 사용자 apply abort) 와 OpenStep string 함정이 다시 안 새어들게.
final class RemapParseTests: XCTestCase {
    private let src = "HIDKeyboardModifierMappingSrc"
    private let dst = "HIDKeyboardModifierMappingDst"
    private let capsLock: UInt64 = 0x700000039  // = 30064771129
    private let f19: UInt64 = 0x70000006E       // = 30064771182

    /// 빈 출력 = 진짜 빈 매핑. 실패(nil) 아님.
    func testEmptyOutputIsEmptyMapping() {
        XCTAssertEqual(Remap.parseMappings(""), [])
    }

    /// 깨끗한 사용자 (UserKeyMapping 한 번도 set 안 함) — hidutil 출력 "(null)".
    /// 공백/개행 변형 포함 전부 빈 매핑으로. v1.0.1 fix 의 핵심.
    func testNullOutputIsEmptyMapping() {
        XCTAssertEqual(Remap.parseMappings("(null)"), [])
        XCTAssertEqual(Remap.parseMappings("(null)\n"), [])
        XCTAssertEqual(Remap.parseMappings("  (null)  \n"), [])
    }

    /// hidutil 실제 출력 형식 (OpenStep plist) — 모든 scalar 가 *string*.
    /// remap.swift 주석의 함정 증명: NSNumber cast 만으론 여기서 값이 다 빠진다.
    func testOpenStepPlistParsesStringScalars() {
        let output = """
        (
                {
                HIDKeyboardModifierMappingDst = "30064771182";
                HIDKeyboardModifierMappingSrc = "30064771129";
            }
        )
        """
        XCTAssertEqual(Remap.parseMappings(output), [[src: capsLock, dst: f19]])
    }

    /// XML plist (미래 호환) — 진짜 NSNumber 로 parse 되는 fallback 경로.
    func testXMLPlistParsesNumberFallback() {
        let output = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <array>
            <dict>
                <key>HIDKeyboardModifierMappingSrc</key>
                <integer>30064771129</integer>
                <key>HIDKeyboardModifierMappingDst</key>
                <integer>30064771182</integer>
            </dict>
        </array>
        </plist>
        """
        XCTAssertEqual(Remap.parseMappings(output), [[src: capsLock, dst: f19]])
    }

    /// 깨진 입력 = 실패(nil). 빈 매핑([]) 과 반드시 구분 — 오인하면 apply 가
    /// 사용자 매핑 전체를 덮어쓴다 (코덱스 review P1).
    func testGarbageIsFailure() {
        XCTAssertNil(Remap.parseMappings("( { broken = "))
    }

    /// array 아닌 plist (dict 등) 도 실패(nil).
    func testNonArrayPlistIsFailure() {
        XCTAssertNil(Remap.parseMappings("{ UserKeyMapping = 1; }"))
    }

    /// 해석 불가 값이 섞인 항목 = 전체 실패(nil). 그 항목만 조용히 빠뜨리면
    /// apply 의 re-set 이 사용자 항목을 소실시킨다 (2.0.1 fix).
    func testUnparseableValueIsFailure() {
        let output = """
        (
                {
                HIDKeyboardModifierMappingDst = "not-a-number";
                HIDKeyboardModifierMappingSrc = "30064771129";
            }
        )
        """
        XCTAssertNil(Remap.parseMappings(output))
    }

    // MARK: macOS 27 표 형식 (2026-09-17 실측)

    /// 깨끗한 사용자 — 모든 서비스 행이 (null). 빈 매핑([]), 실패 아님.
    func testTableAllNullIsEmptyMapping() {
        let output = """
        RegistryID  Key                   Value
        1000008dd   UserKeyMapping   (null)
        1000004f0   UserKeyMapping   (null)
        100000ad1   UserKeyMapping   (null)

        """
        XCTAssertEqual(Remap.parseMappings(output), [])
    }

    /// `--set` 뒤 실제 출력 — 값이 여러 줄에 걸치고 scalar 가 따옴표 없는 숫자.
    func testTableRowsParseMultilineValue() {
        let output = """
        RegistryID  Key                   Value
        1000008dd   UserKeyMapping   (
                {
                HIDKeyboardModifierMappingDst = 30064771182;
                HIDKeyboardModifierMappingSrc = 30064771129;
            }
        )
        100000ad1   UserKeyMapping   (
                {
                HIDKeyboardModifierMappingDst = 30064771182;
                HIDKeyboardModifierMappingSrc = 30064771129;
            }
        )
        """
        XCTAssertEqual(Remap.parseMappings(output), [[src: capsLock, dst: f19]])
    }

    /// (null) 행과 값 있는 행이 섞이면 값 있는 행을 따른다 (아직 안 퍼진 서비스는 무시).
    func testTableMixedNullAndValueFollowsValue() {
        let output = """
        RegistryID  Key                   Value
        1000008dd   UserKeyMapping   (null)
        100000ad1   UserKeyMapping   (
                {
                HIDKeyboardModifierMappingDst = 30064771182;
                HIDKeyboardModifierMappingSrc = 30064771129;
            }
        )
        1000004f0   UserKeyMapping   (null)
        """
        XCTAssertEqual(Remap.parseMappings(output), [[src: capsLock, dst: f19]])
    }

    /// 값 있는 행끼리 다르면 장치별 매핑 — 전역 re-set 이 덮으므로 실패(nil).
    func testTableDivergentRowsIsFailure() {
        let output = """
        RegistryID  Key                   Value
        1000008dd   UserKeyMapping   (
                {
                HIDKeyboardModifierMappingDst = 30064771182;
                HIDKeyboardModifierMappingSrc = 30064771129;
            }
        )
        100000ad1   UserKeyMapping   (
                {
                HIDKeyboardModifierMappingDst = 30064771113;
                HIDKeyboardModifierMappingSrc = 30064771129;
            }
        )
        """
        XCTAssertNil(Remap.parseMappings(output))
    }

    /// 헤더만 있고 행이 없으면 빈 매핑으로 오인하지 않는다 — 실패(nil).
    func testTableHeaderOnlyIsFailure() {
        XCTAssertNil(Remap.parseMappings("RegistryID  Key                   Value\n"))
    }

    /// 행 하나가 깨져 있으면 전체 실패(nil).
    func testTableBrokenRowIsFailure() {
        let output = """
        RegistryID  Key                   Value
        1000008dd   UserKeyMapping   ( { broken =
        """
        XCTAssertNil(Remap.parseMappings(output))
    }
}

// MARK: - ExtraKey / Remap.planExtras (ADR-0008)

final class ExtraKeyTests: XCTestCase {
    private let src = "HIDKeyboardModifierMappingSrc"
    private let dst = "HIDKeyboardModifierMappingDst"
    private let capsToF19: [String: UInt64] = ["HIDKeyboardModifierMappingSrc": 0x700000039, "HIDKeyboardModifierMappingDst": 0x70000006E]
    private let micToF18: [String: UInt64] = ["HIDKeyboardModifierMappingSrc": 0xC000000CF, "HIDKeyboardModifierMappingDst": 0x70000006D]
    private let searchToF17: [String: UInt64] = ["HIDKeyboardModifierMappingSrc": 0xC00000221, "HIDKeyboardModifierMappingDst": 0x70000006C]
    private let noStash: (ExtraKey) -> UInt64? = { _ in nil }

    func testExtrasWireToF18AndF17() {
        XCTAssertEqual(Remap.mappings(for: [.dictation]), [micToF18])
        XCTAssertEqual(Remap.mappings(for: [.search, .dictation]), [micToF18, searchToF17])
        XCTAssertEqual(Remap.mappings(for: []), [])
    }

    /// 옵션 Src는 전환 키 Src와 겹치지 않고, 🔍 목적지는 Router가 이미 의미를 붙인 F18·F19가 아니다.
    func testExtrasDoNotCollideWithTransitionKeys() {
        let modeSources = Set(TransitionKey.allCases.map(\.hidUsage))
        XCTAssertTrue(modeSources.isDisjoint(with: ExtraKey.allCases.map(\.srcUsage)))
        XCTAssertFalse([0x70000006D, 0x70000006E].contains(ExtraKey.search.dstUsage))
    }

    /// Right Command 모드는 Caps→F18을 쓰니 🎤를 배선에서 뺀다.
    func testRightCommandModeDropsDictation() {
        XCTAssertEqual(ExtraWiring.effective(enabled: [.dictation, .search], mode: .rightCommand), [.search])
        XCTAssertEqual(ExtraWiring.effective(enabled: [.dictation, .search], mode: .capsLock), [.dictation, .search])
    }

    /// robots launchd가 걸어 둔 🎤→F18 — 같은 매핑이면 stash 없이 인수, 배열 내용은 그대로.
    func testAdoptsIdenticalMapping() {
        var mappings = [capsToF19, micToF18]
        let plan = Remap.planExtras(&mappings, previous: [], selected: [.dictation], stashed: noStash)
        XCTAssertEqual(plan, Remap.ExtraPlan())
        XCTAssertEqual(mappings, [capsToF19, micToF18])
    }

    func testStashesDifferentMapping() {
        let micToThree: [String: UInt64] = [src: 0xC000000CF, dst: 0x700000020]
        var mappings = [capsToF19, micToThree]
        let plan = Remap.planExtras(&mappings, previous: [], selected: [.dictation], stashed: noStash)
        XCTAssertEqual(plan?.pendingStashes, [.dictation: 0x700000020])
        XCTAssertEqual(mappings, [capsToF19, micToF18])
    }

    func testTurningOffRestoresStash() {
        var mappings = [capsToF19, micToF18, searchToF17]
        let plan = Remap.planExtras(&mappings, previous: [.dictation, .search], selected: [.search],
                                    stashed: { $0 == .dictation ? 0x700000020 : nil })
        XCTAssertEqual(plan?.stashToClear, [.dictation])
        XCTAssertEqual(mappings, [capsToF19, [src: 0xC000000CF, dst: 0x700000020], searchToF17])
    }

    /// 인수한 매핑은 우리 것 — 끄면 사라지고 고아로 남지 않는다.
    func testAdoptedMappingLeavesOnRevert() {
        var mappings = [capsToF19, micToF18]
        _ = Remap.planExtras(&mappings, previous: [], selected: [.dictation], stashed: noStash)
        let plan = Remap.planExtras(&mappings, previous: [.dictation], selected: [], stashed: noStash)
        XCTAssertEqual(plan, Remap.ExtraPlan())
        XCTAssertEqual(mappings, [capsToF19])
    }

    func testDuplicateSourceAborts() {
        var mappings = [micToF18, [src: 0xC000000CF, dst: 0x700000020]]
        XCTAssertNil(Remap.planExtras(&mappings, previous: [], selected: [.dictation], stashed: noStash))
    }

    /// 옵션을 모두 끈 채로는 사용자의 🎤 매핑을 건드리지 않는다.
    func testNoExtrasLeavesUserMappingAlone() {
        var mappings = [capsToF19, micToF18]
        XCTAssertEqual(Remap.planExtras(&mappings, previous: [], selected: [], stashed: noStash), Remap.ExtraPlan())
        XCTAssertEqual(mappings, [capsToF19, micToF18])
    }
}

// MARK: - Morse.buildSequence

final class MorseTests: XCTestCase {
    /// 시퀀스를 run-length 역디코드해 "tinygreen" 모스와 대조.
    /// ON 1=dot, ON 3=dash / OFF 1=점 사이, OFF 3=글자 사이 — 그 외 run 은 형식 위반.
    func testSequenceDecodesToTinygreen() {
        let seq = Morse.buildSequence()
        XCTAssertEqual(seq.first, true, "패딩 없이 첫 단위부터 ON")
        XCTAssertEqual(seq.last, true, "마지막 단위로 끝 — 뒤 OFF 패딩 없음")

        var morse = ""
        var i = 0
        while i < seq.count {
            var j = i
            while j < seq.count && seq[j] == seq[i] { j += 1 }
            let run = j - i
            switch (seq[i], run) {
            case (true, 1): morse += "."
            case (true, 3): morse += "-"
            case (false, 1): break          // 점 사이
            case (false, 3): morse += " "   // 글자 사이
            default: XCTFail("형식 위반 run: \(seq[i]) × \(run) at \(i)")
            }
            i = j
        }
        XCTAssertEqual(morse, "- .. -. -.-- --. .-. . . -.")
    }
}

// MARK: - Settings.migrateLegacyKeys


