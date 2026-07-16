import Foundation
import os

private let log = Logger.tinyGreen("Remap")

enum Remap {
    private static let f19HIDUsage: UInt64 = 0x70000006E
    private static let f18HIDUsage: UInt64 = 0x70000006D

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
    private static var ownedTransitionKey: TransitionKey?

    static func ownedPairs(for mode: TransitionKey) -> [(source: TransitionKey, dst: UInt64)] {
        switch mode {
        case .capsLock: return [(.capsLock, f19HIDUsage)]
        case .rightCommand: return [(.rightCommand, f19HIDUsage), (.capsLock, f18HIDUsage)]
        }
    }

    static func mappings(for mode: TransitionKey) -> [[String: UInt64]] {
        ownedPairs(for: mode).map { [srcKey: $0.source.hidUsage, dstKey: $0.dst] }
    }

    static func isOurMapping(_ map: [String: UInt64], for mode: TransitionKey) -> Bool {
        ownedPairs(for: mode).contains { map[srcKey] == $0.source.hidUsage && map[dstKey] == $0.dst }
    }

    static func apply() -> Bool {
        apply(for: Settings.transitionKey)
    }

    @discardableResult
    static func switchTransitionKey(to key: TransitionKey) -> Bool {
        apply(for: key)
    }

    private static func apply(for selected: TransitionKey) -> Bool {
        guard var mappings = currentMappingArray() else {
            log.error("apply: 매핑 조회 실패 — abort (사용자 매핑 보호)")
            return false
        }
        log.info("apply: \(selected.menuTitle, privacy: .public) 시작 — 현재 array size \(mappings.count, privacy: .public)")

        let previousOwner = ownedTransitionKey
            ?? Settings.appliedTransitionKey
            ?? legacyCapsOwner(in: mappings)
        var stashToClear = Set<TransitionKey>()

        let newSources = Set(ownedPairs(for: selected).map(\.source))

        if let previousOwner {
            mappings.removeAll { isOurMapping($0, for: previousOwner) }

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

        var pendingStashes: [TransitionKey: UInt64] = [:]
        for source in ownedPairs(for: selected).map(\.source) {
            let conflicts = mappings.filter { $0[srcKey] == source.hidUsage }
            if conflicts.count > 1 {
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
        let ok = setMappings(mappings)
        if ok {
            didAddOurMapping = true
            ownedTransitionKey = selected
            Settings.appliedTransitionKey = selected
            for oldKey in stashToClear {
                Settings.setStashedDst(nil, for: oldKey)
            }
            for (source, pendingStash) in pendingStashes {
                if let old = Settings.stashedDst(for: source), old != pendingStash {
                    log.notice("apply: 기존 \(source.menuTitle, privacy: .public) stash dst=\(keyName(old), privacy: .public) → \(keyName(pendingStash), privacy: .public) 덮어씀")
                }
                Settings.setStashedDst(pendingStash, for: source)
            }
            log.info("apply: \(selected.menuTitle, privacy: .public) 모드 배선 완료 (\(self.ownedPairs(for: selected).count, privacy: .public)개), didAddOurMapping=true")
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
        guard let owned = ownedTransitionKey else {
            didAddOurMapping = false
            return true
        }
        let ok = removeOurMappings(for: owned, logPrefix: "revert")
        if ok {
            didAddOurMapping = false
            ownedTransitionKey = nil
            Settings.appliedTransitionKey = nil
        }
        return ok
    }

    static func currentMapping() -> String? {
        return runHidutil(args: ["property", "--get", "UserKeyMapping"])
    }

    private static func removeOurMappings(for owned: TransitionKey, logPrefix: String) -> Bool {
        guard var mappings = currentMappingArray() else {
            log.error("\(logPrefix, privacy: .public): 매핑 조회 실패 — abort (사용자 매핑 보호)")
            return false
        }
        let before = mappings
        mappings.removeAll(where: { isOurMapping($0, for: owned) })

        var stashesRestored = Set<TransitionKey>()
        var stashesDiscarded = Set<TransitionKey>()
        for source in ownedPairs(for: owned).map(\.source) {
            guard let stashed = Settings.stashedDst(for: source) else { continue }
            if mappings.contains(where: { $0[srcKey] == source.hidUsage }) {
                log.notice("\(logPrefix, privacy: .public): 사용자가 \(source.menuTitle, privacy: .public) 새 매핑 보유 — 복원 skip, stash 폐기")
                stashesDiscarded.insert(source)
            } else {
                mappings.append([srcKey: source.hidUsage, dstKey: stashed])
                stashesRestored.insert(source)
                log.notice("\(logPrefix, privacy: .public): 사용자 \(source.menuTitle, privacy: .public) 매핑 복원 dst=\(keyName(stashed), privacy: .public)")
            }
        }

        if mappings == before {
            for source in stashesDiscarded { Settings.setStashedDst(nil, for: source) }
            log.info("\(logPrefix, privacy: .public): 변경 없음 — no-op")
            return true
        }
        let ok = setMappings(mappings)
        if ok {
            for source in stashesRestored.union(stashesDiscarded) {
                Settings.setStashedDst(nil, for: source)
            }
            log.info("\(logPrefix, privacy: .public): 정리/복원 완료 (\(before.count, privacy: .public) → \(mappings.count, privacy: .public))")
        } else {
            log.error("\(logPrefix, privacy: .public): setMappings 실패 — stash 보존(다음 시도 복원)")
        }
        return ok
    }

    private static func legacyCapsOwner(in mappings: [[String: UInt64]]) -> TransitionKey? {
        if Settings.stashedCapsDst != nil || mappings.contains(where: { isOurMapping($0, for: .capsLock) }) {
            return .capsLock
        }
        return nil
    }

    private static func currentMappingArray() -> [[String: UInt64]]? {
        guard let output = runHidutil(args: ["property", "--get", "UserKeyMapping"]) else {
            log.error("currentMappingArray: hidutil --get 실패")
            return nil
        }
        return parseMappings(output)
    }

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

    private static func parseSingle(_ output: String) -> [[String: UInt64]]? {
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
