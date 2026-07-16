import Foundation
import os

private let log = Logger.tinyGreen("Remap")

enum Remap {
    private static let capsLockHIDUsage: UInt64 = 0x700000039
    private static let f19HIDUsage: UInt64 = 0x70000006E

    private static let srcKey = "HIDKeyboardModifierMappingSrc"
    private static let dstKey = "HIDKeyboardModifierMappingDst"

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
    ]

    static func keyName(_ usage: UInt64) -> String {
        if let name = knownKeys[usage] { return name }
        return String(format: "0x%llX", usage)
    }

    private static var didAddOurMapping = false

    static func apply() -> Bool {
        guard var mappings = currentMappingArray() else {
            log.error("apply: 매핑 조회 실패 — abort (사용자 매핑 보호)")
            return false
        }
        log.info("apply: 시작 — 현재 array size \(mappings.count, privacy: .public)")

        if mappings.contains(where: { isOurMapping($0) }) {
            log.info("apply: 옛 잔존 Caps→F19 매핑 발견 — 제거 후 재추가 (ownership 박기)")
            mappings.removeAll(where: { isOurMapping($0) })
        }

        var pendingStash: UInt64?
        if let conflictIndex = mappings.firstIndex(where: { $0[srcKey] == capsLockHIDUsage }) {
            let dst = mappings[conflictIndex][dstKey] ?? 0
            if dst != 0 {
                pendingStash = dst
            } else {
                log.notice("apply: Caps 충돌 항목 dst 없음 — stash 없이 제거")
            }
            mappings.remove(at: conflictIndex)
        }

        mappings.append([srcKey: capsLockHIDUsage, dstKey: f19HIDUsage])
        let ok = setMappings(mappings)
        if ok {
            didAddOurMapping = true
            if let ps = pendingStash {
                if let old = Settings.stashedCapsDst, old != ps {
                    log.notice("apply: 기존 stash dst=\(keyName(old), privacy: .public) → \(keyName(ps), privacy: .public) 덮어씀 (사용자 최신 Caps 매핑 우선)")
                }
                Settings.stashedCapsDst = ps
                log.notice("apply: Caps→\(keyName(ps), privacy: .public) 충돌 — stash 후 무음 교체")
            }
            log.info("apply: 우리 매핑 추가 완료, didAddOurMapping=true")
        } else {
            log.error("apply: setMappings 실패")
        }
        return ok
    }

    @discardableResult
    static func revert() -> Bool {
        guard didAddOurMapping else {
            log.info("revert: didAddOurMapping=false — 우리가 안 박은 매핑이라 제거 skip (시스템 매핑 보존)")
            return true
        }
        let ok = removeOurMappings(logPrefix: "revert")
        if ok { didAddOurMapping = false }
        return ok
    }

    static func currentMapping() -> String? {
        return runHidutil(args: ["property", "--get", "UserKeyMapping"])
    }

    private static func removeOurMappings(logPrefix: String) -> Bool {
        guard var mappings = currentMappingArray() else {
            log.error("\(logPrefix, privacy: .public): 매핑 조회 실패 — abort (사용자 매핑 보호)")
            return false
        }
        let before = mappings
        mappings.removeAll(where: { isOurMapping($0) })

        var stashRestored = false
        if let stashed = Settings.stashedCapsDst {
            if mappings.contains(where: { $0[srcKey] == capsLockHIDUsage }) {
                log.notice("\(logPrefix, privacy: .public): 사용자가 Caps 새 매핑 보유 — 복원 skip, stash 폐기")
                Settings.stashedCapsDst = nil
            } else {
                mappings.append([srcKey: capsLockHIDUsage, dstKey: stashed])
                stashRestored = true
                log.notice("\(logPrefix, privacy: .public): 사용자 Caps 매핑 복원 dst=\(keyName(stashed), privacy: .public)")
            }
        }

        if mappings == before {
            log.info("\(logPrefix, privacy: .public): 변경 없음 — no-op")
            return true
        }
        let ok = setMappings(mappings)
        if ok {
            if stashRestored { Settings.stashedCapsDst = nil }
            log.info("\(logPrefix, privacy: .public): 정리/복원 완료 (\(before.count, privacy: .public) → \(mappings.count, privacy: .public))")
        } else {
            log.error("\(logPrefix, privacy: .public): setMappings 실패 — stash 보존(다음 시도 복원)")
        }
        return ok
    }

    private static func isOurMapping(_ map: [String: UInt64]) -> Bool {
        return map[srcKey] == capsLockHIDUsage && map[dstKey] == f19HIDUsage
    }

    private static func currentMappingArray() -> [[String: UInt64]]? {
        guard let output = runHidutil(args: ["property", "--get", "UserKeyMapping"]) else {
            log.error("currentMappingArray: hidutil --get 실패")
            return nil
        }
        return parseMappings(output)
    }

    static func parseMappings(_ output: String) -> [[String: UInt64]]? {
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
            if plist is NSNull {
                return []
            }
            guard let array = plist as? [[String: Any]] else {
                log.error("parseMappings: plist 가 array 형식 아님 — type: \(type(of: plist), privacy: .public)")
                return nil
            }
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
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            if task.terminationStatus != 0 {
                log.error("hidutil non-zero exit: \(task.terminationStatus, privacy: .public)")
                return nil
            }
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            log.error("hidutil 실행 실패: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
